import SwiftUI
import SwiftData

struct ReceiptCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FinanceAccount.createdAt) private var accounts: [FinanceAccount]

    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var isProcessing = false
    @State private var parsed: [ParsedFinanceEntry] = []
    @State private var errorMessage: String?
    @State private var didParse = false
    @State private var selectedAccountID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let img = capturedImage {
                            imagePreview(img)
                        } else {
                            captureButtons
                        }

                        if isProcessing { loadingView }
                        if let err = errorMessage { errorView(err) }
                        if didParse && !parsed.isEmpty { resultsCard }
                        if didParse && !parsed.isEmpty && !accounts.isEmpty { receiptAccountPicker }
                        if didParse && !parsed.isEmpty && !accounts.isEmpty && selectedAccountID == nil {
                            Text("Выберите счёт для сохранения")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#ff5c3a"))
                        }
                        if didParse && !parsed.isEmpty && accounts.isEmpty {
                            Text("Создайте счёт в разделе «Финансы»")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                        }
                        if didParse && !parsed.isEmpty { saveButton }
                        if didParse && parsed.isEmpty && !isProcessing {
                            emptyResultView
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("СКАНЕР ЧЕКА")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            .sheet(isPresented: $showCamera) {
                ReceiptImagePicker(image: $capturedImage, source: .camera)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showGallery) {
                ReceiptImagePicker(image: $capturedImage, source: .photoLibrary)
                    .ignoresSafeArea()
            }
            .onChange(of: capturedImage) {
                if capturedImage != nil { Task { await processImage() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Capture

    private var captureButtons: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#ffb830"))
                .padding(.bottom, 8)

            Text("Сфотографируйте чек или\nвыберите из галереи")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button { showCamera = true } label: {
                    Label("Камера", systemImage: "camera.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#ff5c3a"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button { showGallery = true } label: {
                    Label("Галерея", systemImage: "photo.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#5b8cff"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(24)
        .darkCard()
    }

    // MARK: - Image preview

    private func imagePreview(_ img: UIImage) -> some View {
        VStack(spacing: 10) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                capturedImage = nil
                parsed = []
                didParse = false
                errorMessage = nil
            } label: {
                Label("Другое фото", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "#5b8cff"))
            }
        }
        .padding(14)
        .darkCard()
    }

    // MARK: - Loading / Error / Empty

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Color(hex: "#ffb830"))
            Text("Распознаю чек...")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .padding(20)
        .darkCard()
    }

    private func errorView(_ msg: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: "#ff5c3a"))
            Text(msg).font(.system(size: 14)).foregroundStyle(Color(hex: "#f0f0f5"))
        }
        .padding(16)
        .darkCard()
    }

    private var emptyResultView: some View {
        VStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .font(.title2).foregroundStyle(Color(hex: "#6b6b80"))
            Text("Не удалось распознать данные")
                .font(.system(size: 14)).foregroundStyle(Color(hex: "#6b6b80"))
        }
        .padding(20)
        .darkCard()
    }

    // MARK: - Results

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("РЕЗУЛЬТАТ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
                .padding(.horizontal, 16).padding(.top, 12)

            ForEach(parsed) { entry in
                HStack(spacing: 12) {
                    let cat = FinanceCategory(rawValue: entry.category) ?? .other
                    Image(systemName: cat.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: cat.color))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: cat.color).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                        Text(entry.category)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                    Spacer()
                    Text("-\(entry.amount)")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }

            let total = parsed.reduce(0) { $0 + $1.amount }
            HStack {
                Spacer()
                Text("Итого: \(total)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "#ff5c3a"))
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .darkCard()
    }

    // MARK: - Account picker

    private var receiptAccountPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(accounts) { acc in
                    Button { selectedAccountID = acc.id } label: {
                        HStack(spacing: 6) {
                            Image(systemName: acc.icon).font(.system(size: 12))
                            Text(acc.name).font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(selectedAccountID == acc.id ? .white : Color(hex: "#6b6b80"))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedAccountID == acc.id ? Color(hex: acc.colorHex) : Color(hex: "#1a1a24"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Save

    private var canSaveReceipt: Bool {
        !parsed.isEmpty && !accounts.isEmpty && selectedAccountID != nil
    }

    private var saveButton: some View {
        Button {
            guard canSaveReceipt, let accountID = selectedAccountID else { return }
            for entry in parsed {
                let cat = FinanceCategory(rawValue: entry.category) ?? .other
                let type = FinanceType(rawValue: entry.type) ?? .expense
                let tx = FinanceTransaction(
                    name: entry.name,
                    amount: entry.amount,
                    category: cat,
                    type: type,
                    date: entry.date ?? Date(),
                    accountID: accountID
                )
                context.insert(tx)
            }
            try? context.save()
            dismiss()
        } label: {
            Text("Сохранить")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canSaveReceipt ? Color(hex: "#ff5c3a") : Color(hex: "#6b6b80").opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSaveReceipt)
    }

    // MARK: - Process

    private func processImage() async {
        guard let img = capturedImage else { return }
        isProcessing = true
        errorMessage = nil
        do {
            parsed = try await ReceiptScannerService.shared.process(image: img)
            didParse = true
        } catch {
            errorMessage = error.localizedDescription
            didParse = true
        }
        isProcessing = false
    }
}

// MARK: - UIImagePicker wrapper

struct ReceiptImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let source: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(source) ? source : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ReceiptImagePicker
        init(_ parent: ReceiptImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let ui = info[.originalImage] as? UIImage {
                parent.image = ui
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
