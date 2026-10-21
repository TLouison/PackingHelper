//
//  BlurHash.swift
//  PackingHelper
//
//  Minimal BlurHash decoder (https://blurha.sh) for Unsplash placeholders.
//  Decodes to a tiny bitmap that is scaled up behind the real photo.
//

import UIKit

enum BlurHash {
    private static let cache = NSCache<NSString, UIImage>()

    private static let digits: [Character: Int] = {
        let alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
        return Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
    }()

    /// Returns nil for malformed hashes.
    static func image(from hash: String, width: Int = 32, height: Int = 32, punch: Float = 1) -> UIImage? {
        let cacheKey = "\(hash)_\(width)x\(height)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        let chars = Array(hash)
        guard chars.count >= 6, let sizeFlag = decode83(chars[0...0]) else { return nil }

        let numY = sizeFlag / 9 + 1
        let numX = sizeFlag % 9 + 1
        guard chars.count == 4 + 2 * numX * numY,
              let quantisedMaximum = decode83(chars[1...1]),
              let dc = decode83(chars[2..<6]) else { return nil }

        let maximumValue = Float(quantisedMaximum + 1) / 166 * punch

        var colors: [(Float, Float, Float)] = [decodeDC(dc)]
        for i in 1..<(numX * numY) {
            guard let value = decode83(chars[(4 + i * 2)..<(6 + i * 2)]) else { return nil }
            colors.append(decodeAC(value, maximumValue: maximumValue))
        }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var r: Float = 0, g: Float = 0, b: Float = 0
                for j in 0..<numY {
                    let basisY = cos(Float.pi * Float(y) * Float(j) / Float(height))
                    for i in 0..<numX {
                        let basis = cos(Float.pi * Float(x) * Float(i) / Float(width)) * basisY
                        let color = colors[i + j * numX]
                        r += color.0 * basis
                        g += color.1 * basis
                        b += color.2 * basis
                    }
                }
                let offset = (y * width + x) * 4
                pixels[offset] = linearToSRGB(r)
                pixels[offset + 1] = linearToSRGB(g)
                pixels[offset + 2] = linearToSRGB(b)
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else { return nil }

        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func decode83<S: Sequence>(_ chars: S) -> Int? where S.Element == Character {
        var value = 0
        for char in chars {
            guard let digit = digits[char] else { return nil }
            value = value * 83 + digit
        }
        return value
    }

    private static func decodeDC(_ value: Int) -> (Float, Float, Float) {
        (sRGBToLinear(value >> 16), sRGBToLinear((value >> 8) & 255), sRGBToLinear(value & 255))
    }

    private static func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
        let quantR = value / (19 * 19)
        let quantG = (value / 19) % 19
        let quantB = value % 19
        return (
            signPow((Float(quantR) - 9) / 9, 2) * maximumValue,
            signPow((Float(quantG) - 9) / 9, 2) * maximumValue,
            signPow((Float(quantB) - 9) / 9, 2) * maximumValue
        )
    }

    private static func signPow(_ value: Float, _ exp: Float) -> Float {
        copysign(pow(abs(value), exp), value)
    }

    private static func sRGBToLinear(_ value: Int) -> Float {
        let v = Float(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Float) -> UInt8 {
        let v = max(0, min(1, value))
        let srgb = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
        return UInt8(srgb * 255 + 0.5)
    }
}
