import Foundation
import UIKit
import Vision
import PDFKit

/// PDF/image text extraction for Share Extension (no dependency on main app).
enum ReceiptTextExtractor {
    static func extractFromPDF(url: URL) async throws -> String {
        guard let doc = PDFDocument(url: url) else { throw ExtractError.invalidPDF }
        let pageCount = doc.pageCount
        guard pageCount > 0 else { throw ExtractError.noText }

        var fullText = ""
        for i in 0..<pageCount {
            guard let page = doc.page(at: i) else { continue }
            if let pageText = page.string, !pageText.isEmpty {
                fullText += pageText + "\n"
            }
        }

        if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let page = doc.page(at: 0) else { throw ExtractError.noText }
            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: pageRect.size))
                ctx.cgContext.translateBy(x: 0, y: pageRect.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            guard let cgImage = image.cgImage else { throw ExtractError.noText }
            fullText = try await recognizeText(from: UIImage(cgImage: cgImage))
        }

        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractError.noText
        }
        return fullText
    }

    static func extractFromImage(_ image: UIImage) async throws -> String {
        try await recognizeText(from: image)
    }

    private static func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw ExtractError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: ExtractError.noText)
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
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum ExtractError: LocalizedError {
    case invalidPDF
    case invalidImage
    case noText
    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "Не удалось открыть PDF"
        case .invalidImage: return "Не удалось обработать изображение"
        case .noText: return "Текст на чеке не найден"
        }
    }
}
