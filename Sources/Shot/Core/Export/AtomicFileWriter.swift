import Darwin
import Foundation
import ShotKit

enum ImageExportDestination: Sendable {
    case chosen(URL)
    case automatic(directory: URL, filename: String)
}

enum AtomicFileWriter {
    /// Call off the main actor. An automatically named file is reserved with
    /// O_EXCL, so another exporter or process can never overwrite it.
    static func write(_ data: Data, to destination: ImageExportDestination) throws -> URL {
        try commit(to: destination) { try data.write(to: $0) }
    }

    static func copy(_ source: URL, to destination: ImageExportDestination) throws -> URL {
        try commit(to: destination) { temporary in
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? output.close() }
            while true {
                try Task.checkCancellation()
                guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { break }
                try output.write(contentsOf: data)
            }
        }
    }

    private static func commit(to destination: ImageExportDestination, stage: (URL) throws -> Void) throws -> URL {
        try Task.checkCancellation()
        let directory: URL
        switch destination {
        case .chosen(let url): directory = url.deletingLastPathComponent()
        case .automatic(let url, _): directory = url
        }
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let target: URL
        let reserved: Bool
        switch destination {
        case .chosen(let url):
            target = url
            reserved = false
        case .automatic(_, let filename):
            target = try reserve(filename: filename, in: directory)
            reserved = true
        }
        let temporary = directory.appendingPathComponent(".shot-export-\(UUID().uuidString).tmp")
        var committed = false
        defer {
            try? files.removeItem(at: temporary)
            if reserved && !committed { try? files.removeItem(at: target) }
        }
        try Task.checkCancellation()
        try stage(temporary)
        try Task.checkCancellation()
        // This rename is the commit point. A later cancellation never removes
        // a completed user file, including an explicitly approved overwrite.
        guard rename(temporary.path, target.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        committed = true
        return target
    }

    private static func reserve(filename: String, in directory: URL) throws -> URL {
        let name = URL(fileURLWithPath: filename).lastPathComponent
        let file = URL(fileURLWithPath: name)
        let stem = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        var index = 1
        while true {
            try Task.checkCancellation()
            let suffix = index == 1 ? "" : " (\(index))"
            let candidate = directory.appendingPathComponent(stem + suffix + (ext.isEmpty ? "" : "." + ext))
            let descriptor = open(candidate.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            if descriptor >= 0 {
                close(descriptor)
                return candidate
            }
            guard errno == EEXIST else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            index += 1
        }
    }
}
