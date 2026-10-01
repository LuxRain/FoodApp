import Foundation

public struct PrintedDateMatch: Sendable {
    public let date: Date
    public let dateType: String
    public let rawText: String
    public let confidence: Double

    public init(date: Date, dateType: String, rawText: String, confidence: Double) {
        self.date = date
        self.dateType = dateType
        self.rawText = rawText
        self.confidence = confidence
    }
}

public enum DateLabelParser {
    public static func bestMatch(in lines: [(text: String, confidence: Double)]) -> PrintedDateMatch? {
        let candidates = lines.enumerated().compactMap { index, line -> PrintedDateMatch? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let previous = index > 0 ? lines[index - 1].text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let source = labelType(in: text) == "unknown" && labelType(in: previous) != "unknown"
                ? "\(previous) \(text)" : text
            let type = labelType(in: source)

            guard let (date, formatConfidence) = parseDate(in: source) else { return nil }
            let labelConfidence = type == "unknown" ? 0.4 : 1.0
            return PrintedDateMatch(
                date: date,
                dateType: type,
                rawText: source,
                confidence: min(1, max(0, line.confidence) * formatConfidence * labelConfidence)
            )
        }
        return candidates.max { $0.confidence < $1.confidence }
    }

    private static func labelType(in text: String) -> String {
        let upper = text.uppercased()
        if upper.contains("BEST IF USED BY") { return "best_if_used_by" }
        if upper.contains("BEST BEFORE") || upper.contains("BEST BY") { return "best_before" }
        if upper.contains("USE BY") { return "use_by" }
        if upper.contains("EXP") { return "expiration" }
        if upper.contains("SELL BY") { return "sell_by" }
        return "unknown"
    }

    private static func parseDate(in text: String) -> (Date, Double)? {
        let uppercase = text.uppercased()
        let patterns: [(String, String, Double)] = [
            (#"\b\d{4}[-/.]\d{1,2}[-/.]\d{1,2}\b"#, "yyyy-MM-dd", 1),
            (#"\b[A-Z]{3,9}\.?\s+\d{1,2},?\s+\d{4}\b"#, "MMM d yyyy", 1),
            (#"\b\d{1,2}\s+[A-Z]{3,9}\.?\s+\d{4}\b"#, "d MMM yyyy", 1),
            (#"\b\d{1,2}[/.-]\d{1,2}[/.-]\d{4}\b"#, "M/d/yyyy", 0.78),
            (#"\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2}\b"#, "M/d/yy", 0.62),
        ]
        for (pattern, format, confidence) in patterns {
            guard let range = uppercase.range(of: pattern, options: .regularExpression) else { continue }
            let periodReplacement = format.contains("MMM") ? "" : (format == "yyyy-MM-dd" ? "-" : "/")
            let token = String(uppercase[range])
                .replacingOccurrences(of: ".", with: periodReplacement)
                .replacingOccurrences(of: "/", with: format == "yyyy-MM-dd" ? "-" : "/")
                .replacingOccurrences(of: "-", with: format == "yyyy-MM-dd" ? "-" : "/")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = false
            formatter.dateFormat = format
            if let date = formatter.date(from: token) { return (date, confidence) }
            if format == "MMM d yyyy" || format == "d MMM yyyy" {
                formatter.dateFormat = format.replacingOccurrences(of: "MMM", with: "MMMM")
                if let date = formatter.date(from: token) { return (date, confidence) }
            }
        }
        return nil
    }
}
