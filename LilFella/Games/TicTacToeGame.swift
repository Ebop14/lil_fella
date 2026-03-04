import Foundation

struct TicTacToeGame: Sendable {
    enum Mark: String, Sendable {
        case x = "X"
        case o = "O"
    }

    enum GameResult: Sendable, Equatable {
        case ongoing
        case win(Mark, winningIndices: [Int])
        case draw
    }

    private(set) var board: [Mark?]
    private(set) var currentTurn: Mark
    private(set) var result: GameResult

    init() {
        board = Array(repeating: nil, count: 9)
        currentTurn = .x // User (X) always goes first
        result = .ongoing
    }

    var availableMoves: [Int] {
        board.indices.filter { board[$0] == nil }
    }

    mutating func place(at index: Int) -> Bool {
        guard case .ongoing = result,
              board.indices.contains(index),
              board[index] == nil else {
            return false
        }

        let mark = currentTurn
        board[index] = mark

        // Check for win
        if let winIndices = checkWin(for: mark) {
            result = .win(mark, winningIndices: winIndices)
            return true
        }

        // Check for draw
        if availableMoves.isEmpty {
            result = .draw
            return true
        }

        // Alternate turn
        currentTurn = (currentTurn == .x) ? .o : .x
        return true
    }

    /// Text board for LLM prompt, positions numbered 1-9
    func boardDescription() -> String {
        var lines: [String] = []
        for row in 0..<3 {
            var cells: [String] = []
            for col in 0..<3 {
                let idx = row * 3 + col
                if let mark = board[idx] {
                    cells.append(mark.rawValue)
                } else {
                    cells.append("\(idx + 1)")
                }
            }
            lines.append(cells.joined(separator: " | "))
        }
        return lines.joined(separator: "\n---------\n")
    }

    // MARK: - Win detection

    private static let winPatterns: [[Int]] = [
        [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
        [0, 3, 6], [1, 4, 7], [2, 5, 8], // columns
        [0, 4, 8], [2, 4, 6],            // diagonals
    ]

    private func checkWin(for mark: Mark) -> [Int]? {
        for pattern in Self.winPatterns {
            if pattern.allSatisfy({ board[$0] == mark }) {
                return pattern
            }
        }
        return nil
    }
}
