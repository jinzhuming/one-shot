import AppKit
import Foundation
import ShotKit

enum ScrollCaptureWarning: Sendable {
    case needsSlowerScrolling
    case lengthLimitReached
    case memoryLimitReached
}

struct ScrollCaptureProgress: Sendable {
    let frameCount: Int
    let outputHeightPixels: Int
    let direction: ScrollDirection?
    let warning: ScrollCaptureWarning?
}

struct ScrollCaptureTarget: Sendable {
    let windowID: CGWindowID
    let frame: CGRect
}

struct ScrollStitchSegment: @unchecked Sendable {
    let image: CGImage
    let top: Int
}

struct ScrollStitchSnapshot: @unchecked Sendable {
    let segments: [ScrollStitchSegment]
    let width: Int
    let height: Int
}

private struct ScrollMatch {
    let direction: ScrollDirection
    let overlap: Int
    let error: Double
    let margin: Double
}

private enum ScrollMatchResult {
    case unchanged
    case matched(ScrollMatch)
    case needsSlowerScrolling
}

final class ScrollStitcher: @unchecked Sendable {
    private let maxOutputHeightPixels: Int
    private let maxFrameCount: Int
    private let maxOutputBytes: Int64
    private var segments: [ScrollStitchSegment] = []
    private var lastAcceptedFrame: CGImage?
    private var lengthLimitReached = false
    private var memoryLimitReached = false

    private(set) var direction: ScrollDirection?
    private(set) var frameCount = 0
    private(set) var outputHeightPixels = 0

    init(
        maxOutputHeightPixels: Int = 200_000,
        maxFrameCount: Int = 400,
        maxOutputBytes: Int = 512 * 1024 * 1024
    ) {
        self.maxOutputHeightPixels = max(1, maxOutputHeightPixels)
        self.maxFrameCount = max(1, maxFrameCount)
        self.maxOutputBytes = Int64(max(1, maxOutputBytes))
    }

    var hasContent: Bool { !segments.isEmpty }

    func append(_ frame: CGImage) throws -> ScrollCaptureProgress {
        guard frame.width > 0, frame.height > 0 else {
            throw CaptureError.scrollCaptureFailed
        }

        if memoryLimitReached {
            return progress(warning: .memoryLimitReached)
        }
        if lengthLimitReached {
            return progress(warning: .lengthLimitReached)
        }

        if let lastAcceptedFrame {
            guard frame.width == lastAcceptedFrame.width,
                  frame.height == lastAcceptedFrame.height else {
                throw CaptureError.scrollCaptureFailed
            }

            let matchResult = try Self.match(previous: lastAcceptedFrame, current: frame)

            if case .unchanged = matchResult {
                return progress()
            }
            guard case .matched(let match) = matchResult else {
                return progress(warning: .needsSlowerScrolling)
            }
            if let direction, direction != match.direction {
                throw CaptureError.scrollCaptureDirectionChanged
            }
            direction = match.direction

            guard let advance = ScrollCaptureGeometry.advance(
                viewportHeight: frame.height,
                overlap: match.overlap
            ), advance > 0 else {
                return progress()
            }
            guard outputHeightPixels + advance <= maxOutputHeightPixels else {
                lengthLimitReached = true
                return progress(warning: .lengthLimitReached)
            }
            guard frameCount < maxFrameCount else {
                lengthLimitReached = true
                return progress(warning: .lengthLimitReached)
            }

            let stripHeight = frame.height - match.overlap
            let projectedBytes = Int64(frame.width)
                * Int64(outputHeightPixels + stripHeight)
                * 4
            guard projectedBytes <= maxOutputBytes else {
                memoryLimitReached = true
                return progress(warning: .memoryLimitReached)
            }

            guard let stripRect = ScrollCaptureGeometry.newStripRect(
                direction: match.direction,
                viewportSize: CGSize(width: frame.width, height: frame.height),
                overlap: CGFloat(match.overlap)
            ), let strip = frame.cropping(to: stripRect) else {
                throw CaptureError.scrollCaptureFailed
            }

            switch match.direction {
            case .down:
                segments.append(ScrollStitchSegment(image: strip, top: outputHeightPixels))
            case .up:
                let shifted = segments.map {
                    ScrollStitchSegment(
                        image: $0.image,
                        top: ScrollCaptureGeometry.shiftedTop(
                            direction: .up,
                            existingTop: $0.top,
                            newStripHeight: strip.height
                        )
                    )
                }
                segments = [ScrollStitchSegment(image: strip, top: 0)] + shifted
            }
            outputHeightPixels += strip.height
            frameCount += 1
            self.lastAcceptedFrame = frame
        } else {
            guard frame.height <= maxOutputHeightPixels else {
                throw CaptureError.scrollCaptureTooLong
            }
            let initialBytes = Int64(frame.width) * Int64(frame.height) * 4
            guard initialBytes <= maxOutputBytes else {
                throw CaptureError.scrollCaptureTooLong
            }
            segments = [ScrollStitchSegment(image: frame, top: 0)]
            outputHeightPixels = frame.height
            frameCount = 1
            lastAcceptedFrame = frame
        }

        return progress()
    }

    func snapshot() throws -> ScrollStitchSnapshot {
        guard let first = segments.first,
              segments.allSatisfy({ $0.image.width == first.image.width }) else {
            throw CaptureError.scrollCaptureFailed
        }
        return ScrollStitchSnapshot(
            segments: segments,
            width: first.image.width,
            height: outputHeightPixels
        )
    }

    private func progress(warning: ScrollCaptureWarning? = nil) -> ScrollCaptureProgress {
        ScrollCaptureProgress(
            frameCount: frameCount,
            outputHeightPixels: outputHeightPixels,
            direction: direction,
            warning: warning
        )
    }

    private static func match(previous: CGImage, current: CGImage) throws -> ScrollMatchResult {
        let previousGray = try GrayImage(cgImage: previous)
        let currentGray = try GrayImage(cgImage: current)
        guard previousGray.width == currentGray.width,
              previousGray.height == currentGray.height else {
            throw CaptureError.scrollCaptureFailed
        }

        let movement = meanDifference(previousGray, currentGray)
        if movement < 4.5 {
            return .unchanged
        }

        let candidates: [(ScrollDirection, Double, Int)] = [
            bestCandidate(previous: previousGray, current: currentGray, direction: .down),
            bestCandidate(previous: previousGray, current: currentGray, direction: .up)
        ]
        let ordered = candidates.sorted { $0.1 < $1.1 }
        guard let best = ordered.first,
              best.1 <= 58,
              let second = ordered.dropFirst().first else {
            return .needsSlowerScrolling
        }

        let margin = second.1 - best.1
        guard margin >= 0.6 else {
            return .needsSlowerScrolling
        }

        let overlap = Int(
            (Double(best.2) / Double(previousGray.height) * Double(previous.height)).rounded()
        )
        guard overlap > 0, overlap < previous.height else {
            return .needsSlowerScrolling
        }
        return .matched(ScrollMatch(
            direction: best.0,
            overlap: overlap,
            error: best.1,
            margin: margin
        ))
    }

    private static func bestCandidate(
        previous: GrayImage,
        current: GrayImage,
        direction: ScrollDirection
    ) -> (ScrollDirection, Double, Int) {
        let minimumOverlap = max(4, previous.height / 8)
        // Keep the one-pixel advance case searchable. The former 92% cap
        // rejected slow, incremental scrolling because a 96px viewport moved
        // by one pixel needs a 95px overlap.
        let maximumOverlap = max(minimumOverlap + 1, previous.height - 1)
        var bestError = Double.greatestFiniteMagnitude
        var bestOverlap = minimumOverlap

        for overlap in minimumOverlap...maximumOverlap {
            let error = overlapError(
                previous: previous,
                current: current,
                overlap: overlap,
                direction: direction
            )
            if error < bestError {
                bestError = error
                bestOverlap = overlap
            }
        }
        return (direction, bestError, bestOverlap)
    }

    private static func overlapError(
        previous: GrayImage,
        current: GrayImage,
        overlap: Int,
        direction: ScrollDirection
    ) -> Double {
        let xStart = previous.width / 10
        let xEnd = previous.width - xStart
        guard xEnd > xStart, overlap > 0 else { return .greatestFiniteMagnitude }

        var total = 0.0
        var count = 0
        for row in 0..<overlap {
            let previousRow: Int
            let currentRow: Int
            switch direction {
            case .down:
                previousRow = previous.height - overlap + row
                currentRow = row
            case .up:
                previousRow = row
                currentRow = current.height - overlap + row
            }
            let previousOffset = previousRow * previous.width
            let currentOffset = currentRow * current.width
            for column in xStart..<xEnd {
                total += abs(Double(previous.pixels[previousOffset + column]) - Double(current.pixels[currentOffset + column]))
                count += 1
            }
        }
        return count == 0 ? .greatestFiniteMagnitude : total / Double(count)
    }

    private static func meanDifference(_ lhs: GrayImage, _ rhs: GrayImage) -> Double {
        guard lhs.pixels.count == rhs.pixels.count, !lhs.pixels.isEmpty else {
            return .greatestFiniteMagnitude
        }
        var total = 0.0
        for index in lhs.pixels.indices {
            total += abs(Double(lhs.pixels[index]) - Double(rhs.pixels[index]))
        }
        return total / Double(lhs.pixels.count)
    }
}

private struct GrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(cgImage: CGImage) throws {
        let width = min(128, max(32, cgImage.width))
        let height = max(8, Int((Double(cgImage.height) / Double(cgImage.width) * Double(width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw CaptureError.scrollCaptureFailed }
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

enum ScrollStitchRenderer {
    static func render(_ snapshot: ScrollStitchSnapshot) throws -> CGImage {
        guard snapshot.width > 0, snapshot.height > 0 else {
            throw CaptureError.scrollCaptureFailed
        }
        guard let context = CGContext(
            data: nil,
            width: snapshot.width,
            height: snapshot.height,
            bitsPerComponent: 8,
            bytesPerRow: snapshot.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CaptureError.scrollCaptureFailed
        }
        context.interpolationQuality = .none
        for segment in snapshot.segments {
            let y = CGFloat(snapshot.height - segment.top - segment.image.height)
            context.draw(
                segment.image,
                in: CGRect(
                    x: 0,
                    y: y,
                    width: CGFloat(segment.image.width),
                    height: CGFloat(segment.image.height)
                )
            )
        }
        guard let image = context.makeImage() else {
            throw CaptureError.scrollCaptureFailed
        }
        return image
    }
}

struct ScrollCaptureOptions: Sendable {
    var sampleInterval: Duration = .milliseconds(120)
    var maxOutputHeightPixels = 200_000
    var maxFrameCount = 400
    var maxOutputBytes = 512 * 1024 * 1024
}

@MainActor
final class ScrollCaptureCoordinator {
    typealias ProgressHandler = @MainActor (ScrollCaptureProgress) -> Void

    private let captureService: CaptureService
    private let catalog: WindowCatalog
    private let options: ScrollCaptureOptions
    private let expectedWindow: ScrollCaptureTarget?
    private let onProgress: ProgressHandler?
    private var finishRequested = false

    init(
        captureService: CaptureService,
        catalog: WindowCatalog,
        options: ScrollCaptureOptions = ScrollCaptureOptions(),
        expectedWindow: CapturableWindow? = nil,
        onProgress: ProgressHandler? = nil
    ) {
        self.captureService = captureService
        self.catalog = catalog
        self.options = options
        self.expectedWindow = expectedWindow.map {
            ScrollCaptureTarget(windowID: $0.windowID, frame: $0.frame)
        }
        self.onProgress = onProgress
    }

    func finish() {
        finishRequested = true
    }

    func run(selection: RegionSelection) async throws -> CaptureResult {
        finishRequested = false
        try await AsyncTimeout.run(
            timeout: .seconds(15),
            timeoutError: CaptureError.timedOut
        ) {
            try await self.catalog.refreshLatest()
        }
        try Task.checkCancellation()
        try validateTargetWindow(for: selection)

        let initial = try currentScreen(for: selection)
        let first = try await captureService.captureRegionFrame(selection, catalog: catalog)
        guard first.screen.displayID == initial.displayID,
              first.screen.frame == initial.frame,
              first.screen.backingScaleFactor == initial.backingScaleFactor else {
            throw CaptureError.noDisplay
        }

        let stitcher = ScrollStitcher(
            maxOutputHeightPixels: options.maxOutputHeightPixels,
            maxFrameCount: options.maxFrameCount,
            maxOutputBytes: options.maxOutputBytes
        )
        let firstProgress = try stitcher.append(first.image)
        onProgress?(firstProgress)

        while !finishRequested {
            try await Task.sleep(for: options.sampleInterval)
            try Task.checkCancellation()
            guard !finishRequested else { break }
            let current = try currentScreen(for: selection)
            guard current.displayID == initial.displayID,
                  current.frame == initial.frame,
                  current.backingScaleFactor == initial.backingScaleFactor else {
                throw CaptureError.noDisplay
            }
            try validateTargetWindow(for: selection)

            let next = try await captureService.captureRegionFrame(selection, catalog: catalog)
            guard next.screen.displayID == initial.displayID,
                  next.screen.frame == initial.frame,
                  next.screen.backingScaleFactor == initial.backingScaleFactor,
                  next.image.width == first.image.width,
                  next.image.height == first.image.height else {
                throw CaptureError.noDisplay
            }
            let progress = try stitcher.append(next.image)
            onProgress?(progress)
        }

        let snapshot = try stitcher.snapshot()
        let image = try await Task.detached(priority: .userInitiated) {
            try ScrollStitchRenderer.render(snapshot)
        }.value
        let pointSize = CGSize(
            width: CGFloat(image.width) / first.scale,
            height: CGFloat(image.height) / first.scale
        )
        return CaptureResult(
            image: NSImage(cgImage: image, size: pointSize),
            rect: selection.rect,
            screen: initial,
            kind: .scrolling
        )
    }

    private func validateTargetWindow(for selection: RegionSelection) throws {
        guard let expectedWindow else { return }
        catalog.refreshWindowsFromCG()
        let point = CGPoint(x: selection.rect.midX, y: selection.rect.midY)
        guard let current = catalog.hitTest(point),
              current.windowID == expectedWindow.windowID,
              current.frame == expectedWindow.frame else {
            throw CaptureError.scrollCaptureTargetMoved
        }
    }

    private func currentScreen(for selection: RegionSelection) throws -> NSScreen {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == selection.displayID }),
              screen.frame.contains(selection.rect) else {
            throw CaptureError.noDisplay
        }
        return screen
    }
}
