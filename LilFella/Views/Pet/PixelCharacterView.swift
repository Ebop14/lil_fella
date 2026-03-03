import SwiftUI

struct PixelCharacterView: View {
    let frame: SpriteFrame
    let pixelSize: CGFloat

    var body: some View {
        Canvas { context, _ in
            for (y, row) in frame.pixels.enumerated() {
                for (x, color) in row.enumerated() {
                    guard let color else { continue }
                    let rect = CGRect(
                        x: CGFloat(x) * pixelSize,
                        y: CGFloat(y) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(
            width: CGFloat(frame.width) * pixelSize,
            height: CGFloat(frame.height) * pixelSize
        )
    }
}
