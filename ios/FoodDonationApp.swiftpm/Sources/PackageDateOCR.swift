import FoodDonationCore
import Foundation
import UIKit
import Vision

enum PackageDateOCR {
    @MainActor
    static func normalizedJPEG(from data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw AppValidationError("The selected photo could not be opened.") }
        let longestEdge = max(image.size.width, image.size.height)
        let ratio = min(1, 2048 / max(1, longestEdge))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = normalized.jpegData(compressionQuality: 0.82), jpeg.count <= 10 * 1024 * 1024 else {
            throw AppValidationError("The photo is too large to upload. Try a closer picture of the date label.")
        }
        return jpeg
    }

    static func recognize(jpegData: Data) async throws -> PrintedDateMatch? {
        let lines = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(data: jpegData, options: [:])
            try handler.perform([request])
            let observations = (request.results ?? []).sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.03 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            return observations.compactMap { observation -> RecognizedDateLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedDateLine(text: candidate.string, confidence: Double(candidate.confidence))
            }
        }.value
        return DateLabelParser.bestMatch(in: lines.map { ($0.text, $0.confidence) })
    }
}

private struct RecognizedDateLine: Sendable {
    let text: String
    let confidence: Double
}
