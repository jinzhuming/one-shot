import Foundation

public enum ExportNaming {
    public static func filename(fileExtension: String, date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Shot \(formatter.string(from: date)).\(fileExtension)"
    }

    /// Returns a filename that does not collide with an existing export.
    ///
    /// The first filename keeps the system screenshot naming style. When it is
    /// already taken, the suffix starts at `(2)` and increments until the
    /// supplied predicate reports an available name.
    public static func uniqueFilename(
        preferred: String,
        isTaken: (String) -> Bool
    ) -> String {
        guard isTaken(preferred) else { return preferred }

        let url = URL(fileURLWithPath: preferred)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var index = 2
        while true {
            let candidateStem = "\(stem) (\(index))"
            let candidate = ext.isEmpty ? candidateStem : "\(candidateStem).\(ext)"
            if !isTaken(candidate) {
                return candidate
            }
            index += 1
        }
    }
}
