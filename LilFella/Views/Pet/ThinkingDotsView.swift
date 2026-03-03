import SwiftUI

/// Pixel-art style thinking dots (•  ••  •••) that cycle above the character's head.
struct ThinkingDotsView: View {
    let pixelSize: CGFloat

    @State private var dotCount: Int = 1

    var body: some View {
        Canvas { context, size in
            let dotSize = pixelSize * 2
            let gap = pixelSize * 1.5
            let totalWidth = dotSize * 3 + gap * 2
            let startX = (size.width - totalWidth) / 2
            let y = (size.height - dotSize) / 2

            for i in 0..<dotCount {
                let rect = CGRect(
                    x: startX + CGFloat(i) * (dotSize + gap),
                    y: y,
                    width: dotSize,
                    height: dotSize
                )
                context.fill(Path(rect), with: .color(PetPalette.eyePupil))
            }
        }
        .frame(
            width: pixelSize * 14,
            height: pixelSize * 4
        )
        .onReceive(
            Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()
        ) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}
