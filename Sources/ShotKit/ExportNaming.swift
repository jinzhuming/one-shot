import Foundation

public enum ExportNaming {
    public static func filename(fileExtension: String, date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Shot \(formatter.string(from: date)).\(fileExtension)"
    }
}
