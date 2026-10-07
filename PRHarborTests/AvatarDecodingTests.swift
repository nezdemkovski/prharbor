import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

@Suite("Avatar decoding")
struct AvatarDecodingTests {
    @Test @MainActor func largeImagesAreDecodedAtDisplayResolutionWithTheirAspectRatio() throws {
        let image = try #require(AvatarBitmap.image(from: encodedImage(width: 1_280, height: 640)))
        let rep = try #require(image.representations.first)
        #expect(rep.pixelsWide == 96)
        #expect(rep.pixelsHigh == 48)
    }

    @Test @MainActor func thumbnailRespectsImageOrientation() throws {
        let image = try #require(AvatarBitmap.image(from: encodedImage(width: 1_280, height: 640, orientation: 6)))
        let rep = try #require(image.representations.first)
        #expect(rep.pixelsWide == 48)
        #expect(rep.pixelsHigh == 96)
    }

    @Test @MainActor func smallImagesAreNotUpscaledAndInvalidDataIsRejected() throws {
        let image = try #require(AvatarBitmap.image(from: encodedImage(width: 16, height: 16)))
        #expect(image.representations.first?.pixelsWide == 16)
        #expect(AvatarBitmap.image(from: Data("invalid image".utf8)) == nil)
    }

    private func encodedImage(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let bitmap = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, bitmap, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
