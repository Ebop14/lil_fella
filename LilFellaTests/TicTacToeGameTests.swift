import Testing
@testable import LilFella

@Suite("TicTacToeGame")
struct TicTacToeGameTests {

    @Test("New game is ongoing with X going first")
    func newGame() {
        let game = TicTacToeGame()
        #expect(game.result == .ongoing)
        #expect(game.currentTurn == .x)
        #expect(game.availableMoves.count == 9)
    }

    @Test("Valid move places mark and alternates turn")
    func validMove() {
        var game = TicTacToeGame()
        let placed = game.place(at: 0)
        #expect(placed)
        #expect(game.board[0] == .x)
        #expect(game.currentTurn == .o)
        #expect(game.availableMoves.count == 8)
    }

    @Test("Invalid move on occupied cell returns false")
    func invalidMoveOccupied() {
        var game = TicTacToeGame()
        _ = game.place(at: 4)
        let second = game.place(at: 4)
        #expect(!second)
    }

    @Test("Invalid move out of bounds returns false")
    func invalidMoveOutOfBounds() {
        var game = TicTacToeGame()
        let oob1 = game.place(at: 9)
        let oob2 = game.place(at: -1)
        #expect(!oob1)
        #expect(!oob2)
    }

    @Test("Row win detection")
    func rowWin() {
        var game = TicTacToeGame()
        _ = game.place(at: 0) // X
        _ = game.place(at: 3) // O
        _ = game.place(at: 1) // X
        _ = game.place(at: 4) // O
        _ = game.place(at: 2) // X wins top row
        #expect(game.result == .win(.x, winningIndices: [0, 1, 2]))
    }

    @Test("Column win detection")
    func columnWin() {
        var game = TicTacToeGame()
        _ = game.place(at: 1) // X
        _ = game.place(at: 0) // O
        _ = game.place(at: 4) // X
        _ = game.place(at: 3) // O
        _ = game.place(at: 7) // X wins middle column
        #expect(game.result == .win(.x, winningIndices: [1, 4, 7]))
    }

    @Test("Diagonal win detection")
    func diagonalWin() {
        var game = TicTacToeGame()
        _ = game.place(at: 0) // X
        _ = game.place(at: 1) // O
        _ = game.place(at: 4) // X
        _ = game.place(at: 2) // O
        _ = game.place(at: 8) // X wins diagonal
        #expect(game.result == .win(.x, winningIndices: [0, 4, 8]))
    }

    @Test("Draw detection")
    func draw() {
        var game = TicTacToeGame()
        // X O X
        // X X O
        // O X O
        _ = game.place(at: 0) // X
        _ = game.place(at: 1) // O
        _ = game.place(at: 2) // X
        _ = game.place(at: 5) // O
        _ = game.place(at: 3) // X
        _ = game.place(at: 6) // O
        _ = game.place(at: 4) // X
        _ = game.place(at: 8) // O
        _ = game.place(at: 7) // X - draw
        #expect(game.result == .draw)
    }

    @Test("Cannot move after game over")
    func noMoveAfterGameOver() {
        var game = TicTacToeGame()
        _ = game.place(at: 0) // X
        _ = game.place(at: 3) // O
        _ = game.place(at: 1) // X
        _ = game.place(at: 4) // O
        _ = game.place(at: 2) // X wins
        let afterWin = game.place(at: 5)
        #expect(!afterWin)
    }

    @Test("boardDescription shows marks and available positions")
    func boardDescription() {
        var game = TicTacToeGame()
        _ = game.place(at: 0) // X
        _ = game.place(at: 4) // O
        let desc = game.boardDescription()
        #expect(desc.contains("X"))
        #expect(desc.contains("O"))
        #expect(desc.contains("2"))
        #expect(!desc.contains("1")) // position 1 is taken by X, shown as X not "1"
    }

    @Test("availableMoves decreases after moves")
    func availableMovesDecreases() {
        var game = TicTacToeGame()
        #expect(game.availableMoves.count == 9)
        _ = game.place(at: 0)
        #expect(game.availableMoves.count == 8)
        _ = game.place(at: 1)
        #expect(game.availableMoves.count == 7)
    }

    @Test("O can win too")
    func oWins() {
        var game = TicTacToeGame()
        _ = game.place(at: 0) // X
        _ = game.place(at: 3) // O
        _ = game.place(at: 1) // X
        _ = game.place(at: 4) // O
        _ = game.place(at: 8) // X (not winning)
        _ = game.place(at: 5) // O wins middle row
        #expect(game.result == .win(.o, winningIndices: [3, 4, 5]))
    }
}
