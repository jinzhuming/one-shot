#!/usr/bin/env swift

import Darwin
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let sourceRoot = root.appendingPathComponent("Sources/Shot", isDirectory: true)
let resourceURL = sourceRoot.appendingPathComponent("Localizable.xcstrings")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("localization validation failed: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

func normalizedKey(_ key: String) -> String {
    var result = ""
    var index = key.startIndex
    while index < key.endIndex {
        let next = key.index(after: index)
        if key[index] == "\\", next < key.endIndex, key[next] == "(" {
            var depth = 0
            var cursor = next
            while cursor < key.endIndex {
                if key[cursor] == "(" {
                    depth += 1
                } else if key[cursor] == ")" {
                    depth -= 1
                    if depth == 0 {
                        cursor = key.index(after: cursor)
                        break
                    }
                }
                cursor = key.index(after: cursor)
            }
            result += "%@"
            index = cursor
        } else {
            result.append(key[index])
            index = next
        }
    }
    return result
}

guard let sourceEnumerator = FileManager.default.enumerator(
    at: sourceRoot,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
) else {
    fail("cannot enumerate \(sourceRoot.path)")
}

let pattern = try! NSRegularExpression(pattern: #"String\(localized:\s*"([^"]*)""#)
var sourceKeys = Set<String>()
while let item = sourceEnumerator.nextObject() as? URL {
    guard item.pathExtension == "swift",
          let source = try? String(contentsOf: item, encoding: .utf8) else { continue }
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    for match in pattern.matches(in: source, range: range) {
        guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
        sourceKeys.insert(normalizedKey(String(source[keyRange])))
    }
}

guard let data = try? Data(contentsOf: resourceURL),
      let object = try? JSONSerialization.jsonObject(with: data),
      let plist = object as? [String: Any],
      let strings = plist["strings"] as? [String: Any] else {
    fail("cannot parse \(resourceURL.path)")
}

let missing = sourceKeys.filter { key in
    guard let entry = strings[key] as? [String: Any],
          let localizations = entry["localizations"] as? [String: Any],
          let zhHans = localizations["zh-Hans"] as? [String: Any],
          let stringUnit = zhHans["stringUnit"] as? [String: Any],
          let value = stringUnit["value"] as? String else {
        return true
    }
    return value.isEmpty
}.sorted()

if !missing.isEmpty {
    fail("missing zh-Hans keys:\n  \(missing.joined(separator: "\n  "))")
}

print("Validated \(sourceKeys.count) localized source keys.")
