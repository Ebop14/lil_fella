import SwiftUI

struct PixelEnvironmentView: View {
    let screenHeight: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            // Sky gradient
            LinearGradient(
                colors: [PetPalette.skyTop, PetPalette.skyBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            // Pixelated grass strip (~4% of screen height)
            GrassView(screenWidth: screenHeight)
                .frame(height: screenHeight * 0.04)
        }
    }
}

private struct GrassView: View {
    let screenWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let tileSize = max(size.height / 4, 4)
            let cols = Int(ceil(size.width / tileSize))
            let rows = Int(ceil(size.height / tileSize))

            for row in 0..<rows {
                for col in 0..<cols {
                    let color = (row + col).isMultiple(of: 2)
                        ? PetPalette.grassLight
                        : PetPalette.grassDark
                    let rect = CGRect(
                        x: CGFloat(col) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}
