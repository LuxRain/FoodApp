import Foundation

public enum ScanCodeScheme: String, Codable, Sendable { case upcA = "upc_a", ean8 = "ean_8", ean13 = "ean_13", gtin14 = "gtin_14", gs1, qr, code128 = "code_128", unknown }
public struct ParsedScan: Equatable, Sendable { public let scheme: ScanCodeScheme; public let raw: String; public let normalizedGTIN: String?; public let lot: String?; public let dateYYMMDD: String? }

public enum ScanParser {
    public static func parse(_ raw: String) -> ParsedScan {
        let digits = raw.filter(\.isNumber)
        if [8, 12, 13, 14].contains(digits.count), isValidGTIN(digits) {
            let scheme: ScanCodeScheme = digits.count == 8 ? .ean8 : digits.count == 12 ? .upcA : digits.count == 13 ? .ean13 : .gtin14
            return ParsedScan(scheme: scheme, raw: raw, normalizedGTIN: digits.leftPadded(to: 14), lot: nil, dateYYMMDD: nil)
        }
        if raw.hasPrefix("]C1") || raw.contains("(01)") {
            let compact = raw.replacingOccurrences(of: "]C1", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            let gtin = value(after: "01", length: 14, in: compact)
            let bestBefore = value(after: "15", length: 6, in: compact)
            let expiry = value(after: "17", length: 6, in: compact)
            return ParsedScan(scheme: .gs1, raw: raw, normalizedGTIN: gtin, lot: nil, dateYYMMDD: expiry ?? bestBefore)
        }
        return ParsedScan(scheme: raw.contains("://") ? .qr : .unknown, raw: raw, normalizedGTIN: nil, lot: nil, dateYYMMDD: nil)
    }

    public static func isValidGTIN(_ digits: String) -> Bool {
        guard digits.allSatisfy(\.isNumber), [8, 12, 13, 14].contains(digits.count), let expected = digits.last?.wholeNumberValue else { return false }
        let body = digits.dropLast().reversed()
        let sum = body.enumerated().reduce(0) { $0 + ($1.element.wholeNumberValue ?? 0) * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        return (10 - sum % 10) % 10 == expected
    }

    private static func value(after identifier: String, length: Int, in string: String) -> String? {
        guard let range = string.range(of: identifier) else { return nil }
        let suffix = string[range.upperBound...]
        guard suffix.count >= length else { return nil }
        return String(suffix.prefix(length))
    }
}

private extension String {
    func leftPadded(to width: Int) -> String { String(repeating: "0", count: max(0, width - count)) + self }
}
