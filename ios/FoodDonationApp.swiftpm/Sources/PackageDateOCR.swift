import FoodDonationCore
import Foundation
import ImageIO
import UIKit
import Vision

enum PackageDateOCR {
    @MainActor
    static func normalizedJPEG(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AppValidationError("The selected photo could not be opened. Choose a JPEG, PNG, HEIC, HEIF, WebP, AVIF, GIF, or TIFF image.")
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3072,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw AppValidationError("The selected photo could not be decoded.")
        }
        let image = UIImage(cgImage: thumbnail)
        let size = CGSize(width: thumbnail.width, height: thumbnail.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let jpeg = normalized.jpegData(compressionQuality: 0.88)
        let compressed = jpeg.flatMap { $0.count <= 10 * 1024 * 1024 ? $0 : normalized.jpegData(compressionQuality: 0.72) }
        guard let compressed, compressed.count <= 10 * 1024 * 1024 else {
            throw AppValidationError("The photo is too large to upload. Try a closer picture of the date label.")
        }
        return compressed
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
