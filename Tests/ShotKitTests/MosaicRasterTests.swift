import CoreGraphics
import Foundation
import Testing

private final class SourceImageLifetime {
    var released = false
}

@Test func mosaicCacheRetainsItsSourceIdentityUntilEviction() throws {
    let lifetime = SourceImageLifetime()
    var cache: MosaicRasterCache? = MosaicRasterCache()
    try autoreleasepool {
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: 16 * 16 * 4, alignment: 4)
        bytes.initializeMemory(as: UInt8.self, repeating: 255, count: 16 * 16 * 4)
        let info = Unmanaged.passRetained(lifetime).toOpaque()
        let provider = try #require(CGDataProvider(dataInfo: info, data: bytes, size: 16 * 16 * 4) { info, data, _ in
            let probe = Unmanaged<SourceImageLifetime>.fromOpaque(info!).takeRetainedValue()
            probe.released = true
            UnsafeMutableRawPointer(mutating: data).deallocate()
        })
        let image = try #require(CGImage(width: 16, height: 16, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        _ = try #require(cache?.image(for: image, effect: .pixelate, blockSizePoints: 4,
                                     imagePointSize: CGSize(width: 16, height: 16)))
    }
    #expect(!lifetime.released, "A live cache key must keep the original image's address from being reused")
    cache = nil
    #expect(lifetime.released, "The bounded cache must release its source when the entry is removed")
}
@testable import ShotKit

@Test func mosaicPixelateKeepsIntegerBlocksOnNonDivisibleEdges() {
    let width = 105
    let height = 20
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 10, height: height))
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: 10, y: 0, width: 10, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 100, y: 0, width: 5, height: height))
    let source = context.makeImage()!

    let pixelated = MosaicRaster.pixelated(source, pixelBlock: 10)!
    #expect(pixelated.width == width)
    #expect(pixelated.height == height)

    let first = sample(pixelated, x: 0)
    let firstEdge = sample(pixelated, x: 9)
    let second = sample(pixelated, x: 10)
    let leftover = sample(pixelated, x: 100)
    let leftoverEdge = sample(pixelated, x: 104)

    #expect(first == firstEdge)
    #expect(leftover == leftoverEdge)
    #expect(isRed(first))
    #expect(isGreen(second))
    #expect(isBlue(leftover))
}

@Test func mosaicPixelateGridIsLockedToImageOrigin() {
    let width = 40
    let height = 20
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 10, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 10, y: 0, width: 30, height: height))
    let source = context.makeImage()!
    let pixelated = MosaicRaster.pixelated(source, pixelBlock: 10)!

    #expect(sample(pixelated, x: 5) == sample(pixelated, x: 9))
    #expect(sample(pixelated, x: 10) == sample(pixelated, x: 18))
    #expect(isRed(sample(pixelated, x: 5)))
    #expect(isBlue(sample(pixelated, x: 18)))
}

@Test func mosaicRasterCacheReusesTheSameImage() {
    let context = CGContext(
        data: nil,
        width: 32,
        height: 32,
        bitsPerComponent: 8,
        bytesPerRow: 32 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    let source = context.makeImage()!
    let cache = MosaicRasterCache()
    let pointSize = CGSize(width: 32, height: 32)
    let first = cache.image(
        for: source,
        effect: .pixelate,
        blockSizePoints: 8,
        imagePointSize: pointSize
    )
    let second = cache.image(
        for: source,
        effect: .pixelate,
        blockSizePoints: 8,
        imagePointSize: pointSize
    )
    #expect(first != nil)
    #expect(first === second)
}

@Test func mosaicBlurSoftensAHardEdge() {
    let context = CGContext(
        data: nil,
        width: 40,
        height: 20,
        bitsPerComponent: 8,
        bytesPerRow: 40 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
    let source = context.makeImage()!
    let blurred = MosaicRaster.blurred(source, radius: 8)!
    let edge = sample(blurred, x: 20)
    #expect(edge.0 > 20 && edge.2 > 20)
    #expect(!(isRed(edge) || isBlue(edge)))
}

private func sample(_ image: CGImage, x: Int) -> (UInt8, UInt8, UInt8) {
    PixelSampling.samplePixel(image, x: x, y: image.height / 2)!
}

private func isRed(_ color: (UInt8, UInt8, UInt8)) -> Bool {
    color.0 > 180 && color.1 < 50 && color.2 < 50
}

private func isGreen(_ color: (UInt8, UInt8, UInt8)) -> Bool {
    color.1 > 180 && color.0 < 50 && color.2 < 50
}

private func isBlue(_ color: (UInt8, UInt8, UInt8)) -> Bool {
    color.2 > 180 && color.0 < 50 && color.1 < 80
}
