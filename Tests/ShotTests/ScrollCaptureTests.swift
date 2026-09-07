import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Shot

@Test func scrollStitcherAppendsDownwardFramesWithoutDuplicatingOverlap() throws {
    let stitcher = ScrollStitcher(maxOutputHeightPixels: 1_000, maxFrameCount: 20)
    #expect(try stitcher.append(syntheticFrame(contentOffset: 0)).frameCount == 1)

    let second = try stitcher.append(syntheticFrame(contentOffset: 60))
    #expect(second.direction == .down)
    #expect(second.outputHeightPixels == 156)

    let third = try stitcher.append(syntheticFrame(contentOffset: 120))
    #expect(third.direction == .down)
    #expect(third.outputHeightPixels == 216)

    let image = try ScrollStitchRenderer.render(stitcher.snapshot())
    #expect(image.width == 96)
    #expect(image.height == 216)
}

@Test func scrollStitcherSupportsUpwardFrames() throws {
    let stitcher = ScrollStitcher(maxOutputHeightPixels: 1_000, maxFrameCount: 20)
    #expect(try stitcher.append(syntheticFrame(contentOffset: 60)).frameCount == 1)

    let progress = try stitcher.append(syntheticFrame(contentOffset: 0))
    #expect(progress.direction == .up)
    #expect(progress.outputHeightPixels == 156)
}

@Test func scrollStitcherIgnoresUnchangedFrames() throws {
    let stitcher = ScrollStitcher(maxOutputHeightPixels: 1_000, maxFrameCount: 20)
    _ = try stitcher.append(syntheticFrame(contentOffset: 0))
    let progress = try stitcher.append(syntheticFrame(contentOffset: 0))
    #expect(progress.frameCount == 1)
    #expect(progress.outputHeightPixels == 96)
    #expect(progress.warning == nil)
}

@Test func scrollStitcherAccumulatesSlowIncrementalMovement() throws {
    let stitcher = ScrollStitcher(maxOutputHeightPixels: 1_000, maxFrameCount: 20)
    _ = try stitcher.append(syntheticFrame(contentOffset: 0))
    for offset in 1...60 {
        _ = try stitcher.append(syntheticFrame(contentOffset: offset))
    }

    #expect(stitcher.outputHeightPixels > 96)
}

@Test func scrollStitcherStopsBeforeConfiguredMemoryLimit() throws {
    let initialBytes = 96 * 96 * 4
    let stitcher = ScrollStitcher(
        maxOutputHeightPixels: 1_000,
        maxFrameCount: 20,
        maxOutputBytes: initialBytes + 32
    )
    _ = try stitcher.append(syntheticFrame(contentOffset: 0))
    let progress = try stitcher.append(syntheticFrame(contentOffset: 60))

    guard case .memoryLimitReached = progress.warning else {
        Issue.record("超过输出内存上限时应保留已有内容并提示")
        return
    }
    #expect(progress.outputHeightPixels == 96)
}

@Test func scrollStitcherRejectsDirectionChanges() throws {
    let stitcher = ScrollStitcher(maxOutputHeightPixels: 1_000, maxFrameCount: 20)
    _ = try stitcher.append(syntheticFrame(contentOffset: 0))
    _ = try stitcher.append(syntheticFrame(contentOffset: 60))

    do {
        _ = try stitcher.append(syntheticFrame(contentOffset: 0))
        Issue.record("方向反转应当被拒绝")
    } catch let error as CaptureError {
        if case .scrollCaptureDirectionChanged = error {
            return
        }
        Issue.record("抛出了错误 (error)，但不是方向变化错误")
    }
}

private func syntheticFrame(contentOffset: Int) -> CGImage {
    let width = 96
    let height = 96
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let rawValue = ((contentOffset + y) * 17 + x * 31) % 256
            let value = UInt8(rawValue)
            let index = (y * width + x) * 4
            bytes[index] = value
            bytes[index + 1] = value ^ 0x55
            bytes[index + 2] = value ^ 0xaa
            bytes[index + 3] = 255
        }
    }
    let data = Data(bytes)
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}
