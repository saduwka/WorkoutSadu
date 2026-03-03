import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

/// Share Extension: «Это оплата?» → Да → извлечь текст из PDF/фото → сохранить в App Group → «Чек успешно добавлен. Продолжите в приложении» → закрыть.
final class ShareViewController: UIViewController {
    private var attachmentURL: URL?
    private var isPDF = false
    private var imageForOCR: UIImage?
    private var currentStep: ShareStep = .askPayment {
        didSet { updateView() }
    }
    private var hosting: UIHostingController<ShareReceiptView>?
    private var lastExtractedText: String?
    private var currentParsedItem: ParsedReceiptItem?
    /// Редактируемые поля для экрана «Добавить в Деньги?»
    private var editableReceiptName: String = ""
    private var editableReceiptCategory: String = "Другое"
    private var receiptEditState: ReceiptEditState?

    override func viewDidLoad() {
        super.viewDidLoad()
        fetchAttachment()
    }

    private func fetchAttachment() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let item = items.first,
              let attachments = item.attachments else {
            finish(error: "Нет вложения")
            return
        }

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { [weak self] item, _ in
                    DispatchQueue.main.async {
                        if let url = item as? URL {
                            self?.attachmentURL = self?.copyToTemp(url: url)
                            self?.isPDF = true
                            self?.showUI()
                        } else if let data = item as? Data {
                            self?.handlePDFData(data)
                        } else {
                            self?.finish(error: "Не удалось открыть PDF")
                        }
                    }
                }
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
                    DispatchQueue.main.async {
                        if let url = item as? URL {
                            self?.attachmentURL = self?.copyToTemp(url: url)
                            self?.isPDF = false
                            self?.showUI()
                        } else if let image = item as? UIImage {
                            self?.imageForOCR = image
                            self?.isPDF = false
                            self?.showUI()
                        } else {
                            self?.finish(error: "Не удалось открыть изображение")
                        }
                    }
                }
                return
            }
        }
        finish(error: "Поддерживаются только PDF и изображения")
    }

    private func copyToTemp(url: URL) -> URL? {
        let needSecurity = url.startAccessingSecurityScopedResource()
        defer { if needSecurity { url.stopAccessingSecurityScopedResource() } }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: temp)
        do {
            try FileManager.default.copyItem(at: url, to: temp)
            return temp
        } catch {
            return url
        }
    }

    private func handlePDFData(_ data: Data) {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("receipt.pdf")
        try? FileManager.default.removeItem(at: temp)
        do {
            try data.write(to: temp)
            attachmentURL = temp
            isPDF = true
            showUI()
        } catch {
            finish(error: "Не удалось сохранить PDF")
        }
    }

    private func showUI() {
        updateView()
    }

    private func updateView() {
        if receiptEditState == nil { receiptEditState = ReceiptEditState() }
        receiptEditState?.name = editableReceiptName
        receiptEditState?.category = editableReceiptCategory
        let view = ShareReceiptView(
            step: currentStep,
            editState: receiptEditState!,
            onConfirm: { [weak self] in self?.extractAndSave() },
            onCancel: { [weak self] in self?.finish() },
            onConfirmAdd: { [weak self] in self?.confirmAddInExtension() },
            onSkipToApp: { [weak self] in self?.savePendingAndFinish() }
        )
        if let h = hosting {
            h.rootView = view
        } else {
            let h = UIHostingController(rootView: view)
            h.view.backgroundColor = UIColor.clear
            addChild(h)
            self.view.addSubview(h.view)
            h.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                h.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                h.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                h.view.topAnchor.constraint(equalTo: self.view.topAnchor),
                h.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
            ])
            h.didMove(toParent: self)
            hosting = h
        }
    }

    private func extractAndSave() {
        currentStep = .loading
        Task { @MainActor in
            do {
                let text: String
                if isPDF, let url = attachmentURL {
                    text = try await ReceiptTextExtractor.extractFromPDF(url: url)
                } else if let img = imageForOCR {
                    text = try await ReceiptTextExtractor.extractFromImage(img)
                } else if let url = attachmentURL, let image = UIImage(contentsOfFile: url.path) {
                    text = try await ReceiptTextExtractor.extractFromImage(image)
                } else {
                    currentStep = .error("Нет файла для распознавания")
                    return
                }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    currentStep = .error("Текст на чеке не найден")
                    return
                }
                lastExtractedText = text
                if let item = SimpleReceiptParser.parse(text) {
                    currentParsedItem = item
                    editableReceiptName = item.name
                    editableReceiptCategory = item.category
                    currentStep = .parsed(item)
                } else {
                    ExtensionStorage.savePendingText(text)
                    currentStep = .success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.finish(success: true)
                    }
                }
            } catch {
                currentStep = .error(error.localizedDescription)
            }
        }
    }

    private func finish(success: Bool = false, error: String? = nil) {
        if success {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(domain: "ShareReceipt", code: -1, userInfo: [NSLocalizedDescriptionKey: error ?? "Ошибка"]))
        }
    }

    private func confirmAddInExtension() {
        guard let item = currentParsedItem else { return }
        let name = (receiptEditState?.name.isEmpty == false) ? receiptEditState!.name : editableReceiptName
        let cat = receiptEditState?.category ?? editableReceiptCategory
        let finalItem = ParsedReceiptItem(
            name: name.isEmpty ? item.name : name,
            amount: item.amount,
            category: cat,
            type: item.type,
            date: item.date
        )
        ExtensionStorage.saveConfirmedTransactions([finalItem])
        currentStep = .success
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.finish(success: true)
        }
    }

    private func savePendingAndFinish() {
        if let text = lastExtractedText {
            ExtensionStorage.savePendingText(text)
        }
        currentStep = .skipToApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.finish(success: true)
        }
    }
}

// MARK: - SwiftUI

/// Состояние редактирования описания и категории в экране «Добавить в Деньги?»
private final class ReceiptEditState: ObservableObject {
    @Published var name: String = ""
    @Published var category: String = "Другое"
}

private enum ShareStep {
    case askPayment
    case loading
    case success
    case error(String)
    case parsed(ParsedReceiptItem)
    case skipToApp
}

/// Категории расхода для Share Extension (совпадают с FinanceCategory, без Доход/Переводы).
private let receiptExpenseCategories = [
    "Еда", "Транспорт", "Топливо", "Связь", "Подписки", "Коммунальные",
    "Здоровье", "Одежда", "Покупки", "Развлечения", "Другое"
]

private struct ShareReceiptView: View {
    let step: ShareStep
    @ObservedObject var editState: ReceiptEditState
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onConfirmAdd: () -> Void
    let onSkipToApp: () -> Void

    var body: some View {
        ZStack {
            Color(hex: "#0e0e12").ignoresSafeArea()
            switch step {
            case .askPayment:
                askView
            case .loading:
                loadingView
            case .success:
                successView
            case .error(let message):
                errorView(message: message)
            case .parsed(let item):
                parsedView(item: item)
            case .skipToApp:
                skipToAppView
            }
        }
        .preferredColorScheme(.dark)
    }

    private func formatAmount(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func parsedView(item: ParsedReceiptItem) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(hex: "#ffb830"))
                Text("Добавить в Деньги?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: "#f0f0f5"))

                VStack(alignment: .leading, spacing: 8) {
                    Text("ОПИСАНИЕ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .tracking(1)
                    TextField("Название расхода", text: $editState.name)
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                        .padding(12)
                        .background(Color(hex: "#1a1a24"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("КАТЕГОРИЯ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .tracking(1)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(receiptExpenseCategories, id: \.self) { cat in
                                Button {
                                    editState.category = cat
                                } label: {
                                    Text(cat)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(editState.category == cat ? .white : Color(hex: "#6b6b80"))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(editState.category == cat ? Color(hex: "#ff5c3a") : Color(hex: "#1a1a24"))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack(spacing: 6) {
                    Text("−\(formatAmount(item.amount)) ₸")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                HStack(spacing: 12) {
                    Button("Нет, в приложении") { onSkipToApp() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#1a1a24"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Button("Добавить") { onConfirmAdd() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#ff5c3a"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
            }
            .padding(24)
        }
    }

    private var askView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#ffb830"))
            Text("Это оплата?")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Text("Чек будет добавлен в раздел «Деньги»")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Нет") { onCancel() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "#1a1a24"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button("Да") { onConfirm() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "#ff5c3a"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
        }
        .padding(32)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Color(hex: "#ffb830")).scaleEffect(1.2)
            Text("Распознаю чек...")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(hex: "#3aff9e"))
            Text("Чек успешно добавлен")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Text("Продолжите в приложении")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var skipToAppView: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.forward.app")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#ffb830"))
            Text("Текст чека сохранён")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            VStack(spacing: 8) {
                Text("Откройте приложение → раздел «Финансы».")
                Text("Чек появится для редактирования и добавления в историю.")
            }
            .font(.system(size: 14))
            .foregroundStyle(Color(hex: "#6b6b80"))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color(hex: "#ff5c3a"))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .multilineTextAlignment(.center)
            Button("Закрыть") { onCancel() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "#ff5c3a"))
        }
        .padding(32)
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
