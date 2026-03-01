import Foundation
import UIKit
import Vision

final class ReceiptScannerService {
    static let shared = ReceiptScannerService()

    /// Recognize text from a receipt image using on-device Vision, then parse via AI.
    func process(image: UIImage) async throws -> [ParsedFinanceEntry] {
        let ocrText = try await recognizeText(from: image)
        guard !ocrText.isEmpty else { throw ReceiptError.noTextFound }
        return try await FinanceAIService.shared.parseReceipt(text: ocrText)
    }

    private func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw ReceiptError.invalidImage }

        return try await withCheckedThrowingContinuation { continuation in
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

enum ReceiptError: LocalizedError {
    case invalidImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Не удалось обработать изображение"
        case .noTextFound: return "Текст на чеке не найден"
        }
    }
}
