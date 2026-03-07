import Foundation

enum DateFormattingUtility {
    private static let formatterQueue = DispatchQueue(label: "mynaswift.date-formatters")

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func displayDate(fromUTCISOString value: String) -> String? {
        guard let date = parseUTCISODate(value) else {
            return nil
        }
        return displayDate(from: date)
    }

    static func displayDate(fromUnixOrISO value: String) -> String? {
        guard !value.isEmpty else {
            return nil
        }

        if let unixValue = Int64(value) {
            let seconds =
                unixValue > 9_999_999_999
                ? TimeInterval(unixValue) / 1000.0
                : TimeInterval(unixValue)
            return displayDate(from: Date(timeIntervalSince1970: seconds))
        }

        if let date = parseUTCISODate(value) {
            return displayDate(from: date)
        }

        return value
    }

    private static func displayDate(from date: Date) -> String {
        formatterQueue.sync {
            displayFormatter.string(from: date)
        }
    }

    private static func parseUTCISODate(_ value: String) -> Date? {
        formatterQueue.sync {
            if let date = isoFormatterWithFractionalSeconds.date(from: value) {
                return date
            }
            return isoFormatterStandard.date(from: value)
        }
    }
}
