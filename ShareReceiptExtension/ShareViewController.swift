import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Combine
import CoreFoundation

/// Share Extension: «Это оплата?» → Да → сохранить файл в App Group → «Продолжите в приложении» → закрыть. Распознавание в приложении.
final class ShareViewController: UIViewController {
    private var attachmentURL: URL?
    private var isPDF = false
    private var imageForOCR: UIImage?
    private var currentStep: ShareStep = .askPayment {
        didSet { updateView() }
    }
    private var hosting: UIHostingController<ShareReceiptView>?
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
        let view = ShareReceiptView(
            step: currentStep,
            editState: receiptEditState!,
            onConfirm: { [weak self] in self?.saveFileAndFinish() },
            onCancel: { [weak self] in self?.finish() }
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

    /// Сохранить файл в App Group и уведомить приложение — распознавание в приложении.
    private func saveFileAndFinish() {
        let data: Data?
        let asPDF: Bool
        if isPDF, let url = attachmentURL {
            data = try? Data(contentsOf: url)
            asPDF = true
        } else if let img = imageForOCR, let jpeg = img.jpegData(compressionQuality: 0.9) {
            data = jpeg
            asPDF = false
        } else if let url = attachmentURL, let image = UIImage(contentsOfFile: url.path), let jpeg = image.jpegData(compressionQuality: 0.9) {
            data = jpeg
            asPDF = false
        } else {
            currentStep = .error("Не удалось прочитать файл")
            return
        }
        guard let data = data, ExtensionStorage.savePendingReceiptFile(data: data, isPDF: asPDF) else {
            currentStep = .error("Не удалось сохранить чек")
            return
        }
        postReceiptSavedDarwinNotification()
        currentStep = .success
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.finish(success: true)
        }
    }

    private static let receiptSavedDarwinName = "com.saduwka.WorkoutSadu.receiptSaved"

    private func postReceiptSavedDarwinNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: Self.receiptSavedDarwinName as CFString),
            nil,
            nil,
            true
        )
    }

    private func finish(success: Bool = false, error: String? = nil) {
        if success {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(domain: "ShareReceipt", code: -1, userInfo: [NSLocalizedDescriptionKey: error ?? "Ошибка"]))
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
    case success
    case error(String)
}

private struct ShareReceiptView: View {
    let step: ShareStep
    @ObservedObject var editState: ReceiptEditState
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color(hex: "#0e0e12").ignoresSafeArea()
            switch step {
            case .askPayment:
                askView
            case .success:
                successView
            case .error(let message):
                errorView(message: message)
            }
        }
        .preferredColorScheme(.dark)
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

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.forward.app")
                .font(.system(size: 56))
                .foregroundStyle(Color(hex: "#ffb830"))
            Text("Чек передан в приложение")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Text("Откройте приложение и продолжите в разделе «Деньги»")
                .font(.system(size: 15, weight: .medium))
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
