import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GemmaKit

struct ContextWindowTests {
    /// Cost = total characters, so tests are independent of a tokenizer.
    private func cost(_ messages: [ChatMessage]) -> Int { messages.reduce(0) { $0 + $1.text.count } }

    private func conversation(turns: Int) -> [ChatMessage] {
        var messages: [ChatMessage] = [.system("SSSSSSSSSS")] // 10
        for i in 0..<turns {
            messages.append(.user("U\(i)--------")) // 10
            messages.append(.assistant("A\(i)--------")) // 10
        }
        messages.append(.user("last------")) // 10
        return messages
    }

    @Test func untouchedWhenItFits() {
        let messages = conversation(turns: 2)
        #expect(ContextWindow.fit(messages, budget: 1000, cost: cost) == messages)
    }

    @Test func keepsSystemAndLastMessage() {
        let fitted = ContextWindow.fit(conversation(turns: 5), budget: 15, cost: cost)
        #expect(fitted.first?.role == .system)
        #expect(fitted.last?.text == "last------")
        #expect(fitted.count == 2)
    }

    @Test func trimsBelowTargetAndStartsWithUser() {
        // 10 system + 10 turns * 20 + 10 last = 220
        let fitted = ContextWindow.fit(conversation(turns: 10), budget: 200, targetRatio: 0.5, cost: cost)
        #expect(cost(fitted) <= 100)
        #expect(fitted[1].role == .user)
        #expect(fitted.last?.text == "last------")
        // Newest turns are the ones kept.
        #expect(fitted.dropLast().last?.text == "A9--------")
    }

    @Test func worksWithoutSystemMessage() {
        let messages = Array(conversation(turns: 4).dropFirst())
        let fitted = ContextWindow.fit(messages, budget: 30, cost: cost)
        #expect(fitted.first?.role == .user)
        #expect(cost(fitted) <= 30)
    }
}

struct ImageDecoderTests {
    @Test func decodesAndDownscalesPNG() throws {
        let png = try #require(TestImages.solid(width: 2000, height: 1000, red: 255, green: 0, blue: 0))
        let rgb = try #require(ImageDecoder.rgb(from: png, maxDimension: 1024))
        #expect(rgb.width == 1024)
        #expect(rgb.height == 512)
        #expect(rgb.pixels.count == 1024 * 512 * 3)
        #expect(Array(rgb.pixels.prefix(3)) == [255, 0, 0])
    }

    @Test func jpegThumbnailDownscales() throws {
        let png = try #require(TestImages.solid(width: 4000, height: 3000, red: 0, green: 128, blue: 255))
        let jpeg = try #require(ImageDecoder.jpegThumbnail(from: png, maxDimension: 1536))
        #expect(jpeg.starts(with: [0xFF, 0xD8])) // JPEG SOI marker
        let rgb = try #require(ImageDecoder.rgb(from: jpeg, maxDimension: 4096))
        #expect(rgb.width == 1536 && rgb.height == 1152)
        #expect(ImageDecoder.jpegThumbnail(from: Data("x".utf8)) == nil)
    }

    @Test func rejectsGarbage() {
        #expect(ImageDecoder.rgb(from: Data("not an image".utf8)) == nil)
    }
}

enum TestImages {
    /// Solid-colour PNG.
    static func solid(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> Data? {
        draw(width: width, height: height) { ctx in
            let components = [CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, 1]
            ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: components)!)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> Data? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        body(ctx)
        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
