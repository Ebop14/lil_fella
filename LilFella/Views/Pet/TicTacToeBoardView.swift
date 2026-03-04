import SwiftUI

struct TicTacToeBoardView: View {
    let game: TicTacToeGame
    let onCellTap: (Int) -> Void
    let size: CGFloat

    private var cellSize: CGFloat { size / 3 }
    private var lineWidth: CGFloat { max(size * 0.02, 2) }
    private var markPadding: CGFloat { cellSize * 0.2 }

    var body: some View {
        ZStack {
            // Grid + marks drawn with Canvas
            Canvas { context, canvasSize in
                drawGrid(context: context)
                drawMarks(context: context)
                drawWinHighlight(context: context)
            }
            .frame(width: size, height: size)

            // Invisible tap targets
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { col in
                            let index = row * 3 + col
                            Color.clear
                                .frame(width: cellSize, height: cellSize)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onCellTap(index)
                                }
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Drawing

    private func drawGrid(context: GraphicsContext) {
        let gridColor = PetPalette.gameGrid

        // Vertical lines
        for i in 1..<3 {
            let x = cellSize * CGFloat(i)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size))
            context.stroke(path, with: .color(gridColor), lineWidth: lineWidth)
        }

        // Horizontal lines
        for i in 1..<3 {
            let y = cellSize * CGFloat(i)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: lineWidth)
        }
    }

    private func drawMarks(context: GraphicsContext) {
        for (index, mark) in game.board.enumerated() {
            guard let mark else { continue }
            let row = index / 3
            let col = index % 3
            let origin = CGPoint(
                x: CGFloat(col) * cellSize + markPadding,
                y: CGFloat(row) * cellSize + markPadding
            )
            let markSize = cellSize - markPadding * 2

            switch mark {
            case .x:
                drawX(context: context, origin: origin, size: markSize)
            case .o:
                drawO(context: context, origin: origin, size: markSize)
            }
        }
    }

    private func drawX(context: GraphicsContext, origin: CGPoint, size: CGFloat) {
        let lw = max(self.lineWidth * 1.5, 3)

        var path1 = Path()
        path1.move(to: origin)
        path1.addLine(to: CGPoint(x: origin.x + size, y: origin.y + size))
        context.stroke(path1, with: .color(PetPalette.gameX), lineWidth: lw)

        var path2 = Path()
        path2.move(to: CGPoint(x: origin.x + size, y: origin.y))
        path2.addLine(to: CGPoint(x: origin.x, y: origin.y + size))
        context.stroke(path2, with: .color(PetPalette.gameX), lineWidth: lw)
    }

    private func drawO(context: GraphicsContext, origin: CGPoint, size: CGFloat) {
        let lw = max(self.lineWidth * 1.5, 3)
        let center = CGPoint(x: origin.x + size / 2, y: origin.y + size / 2)
        let radius = size / 2

        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        context.stroke(path, with: .color(PetPalette.gameO), lineWidth: lw)
    }

    private func drawWinHighlight(context: GraphicsContext) {
        guard case .win(_, let indices) = game.result else { return }

        for index in indices {
            let row = index / 3
            let col = index % 3
            let rect = CGRect(
                x: CGFloat(col) * cellSize,
                y: CGFloat(row) * cellSize,
                width: cellSize,
                height: cellSize
            )
            context.fill(Path(rect), with: .color(PetPalette.winHighlight))
        }
    }
}
