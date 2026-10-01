import FoodDonationCore
import Foundation
import UIKit
import Vision

enum PackageDateOCR {
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
