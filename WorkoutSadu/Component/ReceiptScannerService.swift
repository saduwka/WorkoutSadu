import Foundation
import UIKit
@preconcurrency import Vision
import PDFKit

final class ReceiptScannerService {
    static let shared = ReceiptScannerService()

    /// Recognize text from a receipt image using on-device Vision, then parse via AI.
    func process(image: UIImage) async throws -> [ParsedFinanceEntry] {
        let ocrText = try await recognizeText(from: image)
        guard !ocrText.isEmpty else { throw ReceiptError.noTextFound }
        return try await FinanceAIService.shared.parseReceipt(text: ocrText)
    }

    /// Extract text from a PDF (e.g. Kaspi receipt). Uses PDFKit text; if none, renders first page and runs OCR.
    func extractTextFromPDF(url: URL) async throws -> String {
        guard let doc = PDFDocument(url: url) else { throw ReceiptError.invalidPDF }
        let pageCount = doc.pageCount
        guard pageCount > 0 else { throw ReceiptError.noTextFound }

        var fullText = ""
        for i in 0..<pageCount {
            guard let page = doc.page(at: i) else { continue }
            if let pageText = page.string, !pageText.isEmpty {
                fullText += pageText + "\n"
            }
        }

        if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // PDF is image-based (e.g. scanned receipt) — render first page and OCR
            guard let page = doc.page(at: 0) else { throw ReceiptError.noTextFound }
            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: pageRect.size))
                ctx.cgContext.translateBy(x: 0, y: pageRect.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            guard let cgImage = image.cgImage else { throw ReceiptError.noTextFound }
            fullText = try await recognizeText(from: UIImage(cgImage: cgImage))
        }

        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReceiptError.noTextFound
        }
        return fullText
    }

    /// Process a PDF receipt: extract text then parse via AI.
    func processPDF(url: URL) async throws -> [ParsedFinanceEntry] {
        let text = try await extractTextFromPDF(url: url)
        return try await FinanceAIService.shared.parseReceipt(text: text)
    }

    /// Extract text from image only (OCR). Use from Share Extension when AI runs in main app.
    func extractTextFromImage(_ image: UIImage) async throws -> String {
        try await recognizeText(from: image)
    }

    private func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw ReceiptError.invalidImage }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(throwing: ReceiptError.noTextFound)
                        return
                    }
                    let text = observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    continuation.resume(returning: text)
                }
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["ru-RU", "en-US"]
                request.usesLanguageCorrection = false

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum ReceiptError: LocalizedError {
    case invalidImage
    case invalidPDF
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Не удалось обработать изображение"
        case .invalidPDF: return "Не удалось открыть PDF"
        case .noTextFound: return "Текст на чеке не найден"
        }
    }
}
