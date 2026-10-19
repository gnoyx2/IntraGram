import AppKit

// App Store 아이콘은 불투명 RGB여야 함. JPEG 손실 없이 PNG 픽셀을 보존함.
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = NSBitmapImageRep(data: try Data(contentsOf: url)),
          let target = NSBitmapImageRep(
              bitmapDataPlanes: nil,
              pixelsWide: source.pixelsWide,
              pixelsHigh: source.pixelsHigh,
              bitsPerSample: 8,
              samplesPerPixel: 3,
              hasAlpha: false,
              isPlanar: false,
              colorSpaceName: .deviceRGB,
              bytesPerRow: 0,
              bitsPerPixel: 0
          ) else {
        fatalError("Cannot decode icon: \(path)")
    }
    var pixel = [Int](repeating: 0, count: 4)
    for y in 0..<source.pixelsHigh {
        for x in 0..<source.pixelsWide {
            source.getPixel(&pixel, atX: x, y: y)
            if source.hasAlpha && pixel[3] != 255 {
                fatalError("Transparent App Store icon pixel: \(path)")
            }
            target.setPixel(&pixel, atX: x, y: y)
        }
    }
    // 픽셀은 gen_icons.sh가 이미 sRGB로 맞춰 둠. Generic RGB 태그로 나가면 Xcode가 sRGB로
    // 다시 변환해서 남색 배경이 밝아지므로 변환 없이 sRGB 태그만 붙임
    guard let tagged = target.retagging(with: .sRGB),
          let png = tagged.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode icon: \(path)")
    }
    try png.write(to: url)
}
