import SwiftUI

/// A single sprite frame: 2D array of optional colors (nil = transparent).
/// Row-major: rows[y][x], origin at top-left.
struct SpriteFrame {
    let pixels: [[Color?]]
    var height: Int { pixels.count }
    var width: Int { pixels.first?.count ?? 0 }
}

// MARK: - Convenience aliases

private let M = PetPalette.bodyMain      // main body green
private let D = PetPalette.bodyDark      // dark green (outline/shade)
private let L = PetPalette.bodyLight     // highlight green
private let W = PetPalette.eyeWhite     // eye white
private let P = PetPalette.eyePupil     // pupil
private let B = PetPalette.blush        // blush
private let X = PetPalette.mouth        // mouth
private let n: Color? = nil              // transparent

// MARK: - Sprite Frames (20w x 16h, no feet)

enum SpriteFrames {
    // ── Idle Frame 1 (resting) ──
    // 3x3 eyes: white top-left, pupil bottom-right (kawaii style)
    static let idle1 = SpriteFrame(pixels: [
        //0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19
        [n, n, n, n, n, n, D, D, D, D, D, D, D, D, n, n, n, n, n, n],  // 0
        [n, n, n, n, D, D, L, L, M, M, M, M, L, L, D, D, n, n, n, n],  // 1
        [n, n, n, D, L, L, M, M, M, M, M, M, M, M, L, L, D, n, n, n],  // 2
        [n, n, D, L, M, M, M, M, M, M, M, M, M, M, M, M, L, D, n, n],  // 3
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 4
        [n, n, D, M, M, W, W, W, M, M, M, M, W, W, W, M, M, D, n, n],  // 5  eyes top
        [n, n, D, M, M, W, W, P, M, M, M, M, W, W, P, M, M, D, n, n],  // 6  eyes mid
        [n, n, D, M, M, W, P, P, M, M, M, M, W, P, P, M, M, D, n, n],  // 7  eyes bottom
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 8
        [n, n, D, M, B, M, M, M, M, M, M, M, M, M, M, B, M, D, n, n],  // 9  blush
        [n, n, D, M, M, M, M, M, X, X, X, X, M, M, M, M, M, D, n, n],  // 10 mouth
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 11
        [n, n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n, n],  // 12
        [n, n, n, n, D, D, M, M, M, M, M, M, M, M, D, D, n, n, n, n],  // 13
        [n, n, n, n, n, D, D, D, D, D, D, D, D, D, D, n, n, n, n, n],  // 14
        [n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n],  // 15
    ])

    // ── Idle Frame 2 (bounce — shifted up 1px) ──
    static let idle2 = SpriteFrame(pixels: [
        [n, n, n, n, D, D, L, L, M, M, M, M, L, L, D, D, n, n, n, n],  // 0
        [n, n, n, D, L, L, M, M, M, M, M, M, M, M, L, L, D, n, n, n],  // 1
        [n, n, D, L, M, M, M, M, M, M, M, M, M, M, M, M, L, D, n, n],  // 2
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 3
        [n, n, D, M, M, W, W, W, M, M, M, M, W, W, W, M, M, D, n, n],  // 4  eyes top
        [n, n, D, M, M, W, W, P, M, M, M, M, W, W, P, M, M, D, n, n],  // 5  eyes mid
        [n, n, D, M, M, W, P, P, M, M, M, M, W, P, P, M, M, D, n, n],  // 6  eyes bottom
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 7
        [n, n, D, M, B, M, M, M, M, M, M, M, M, M, M, B, M, D, n, n],  // 8  blush
        [n, n, D, M, M, M, M, M, X, X, X, X, M, M, M, M, M, D, n, n],  // 9  mouth
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 10
        [n, n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n, n],  // 11
        [n, n, n, n, D, D, D, M, M, M, M, M, M, D, D, D, n, n, n, n],  // 12
        [n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n],  // 13
        [n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n],  // 14
        [n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n],  // 15
    ])

    // ── Thinking Frame 1 (eyes look up, one dot above) ──
    static let thinking1 = SpriteFrame(pixels: [
        [n, n, n, n, n, n, n, n, n, X, n, n, n, n, n, n, n, n, n, n],  // 0  dot
        [n, n, n, n, D, D, L, L, M, M, M, M, L, L, D, D, n, n, n, n],  // 1
        [n, n, n, D, L, L, M, M, M, M, M, M, M, M, L, L, D, n, n, n],  // 2
        [n, n, D, L, M, M, M, M, M, M, M, M, M, M, M, M, L, D, n, n],  // 3
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 4
        [n, n, D, M, M, P, P, W, M, M, M, M, P, P, W, M, M, D, n, n],  // 5  pupils up
        [n, n, D, M, M, W, W, W, M, M, M, M, W, W, W, M, M, D, n, n],  // 6
        [n, n, D, M, M, W, W, W, M, M, M, M, W, W, W, M, M, D, n, n],  // 7
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 8
        [n, n, D, M, B, M, M, M, M, M, M, M, M, M, M, B, M, D, n, n],  // 9  blush
        [n, n, D, M, M, M, M, M, X, X, X, X, M, M, M, M, M, D, n, n],  // 10 mouth
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 11
        [n, n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n, n],  // 12
        [n, n, n, n, D, D, M, M, M, M, M, M, M, M, D, D, n, n, n, n],  // 13
        [n, n, n, n, n, D, D, D, D, D, D, D, D, D, D, n, n, n, n, n],  // 14
        [n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n],  // 15
    ])

    // ── Thinking Frame 2 (eyes look up, two dots above) ──
    static let thinking2 = SpriteFrame(pixels: [
        [n, n, n, n, n, n, n, n, X, n, X, n, n, n, n, n, n, n, n, n],  // 0  two dots
        [n, n, n, n, D, D, L, L, M, M, M, M, L, L, D, D, n, n, n, n],  // 1
        [n, n, n, D, L, L, M, M, M, M, M, M, M, M, L, L, D, n, n, n],  // 2
        [n, n, D, L, M, M, M, M, M, M, M, M, M, M, M, M, L, D, n, n],  // 3
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 4
        [n, n, D, M, M, P, P, W, M, M, M, M, P, P, W, M, M, D, n, n],  // 5  pupils up
        [n, n, D, M, M, W, W, W, M, M, M, M, W, W, W, M, M, D, n, n],  // 6
        [n, n, D, M, M, W, W, W, M, M, M, M, W, W, W, M, M, D, n, n],  // 7
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 8
        [n, n, D, M, B, M, M, M, M, M, M, M, M, M, M, B, M, D, n, n],  // 9  blush
        [n, n, D, M, M, M, M, M, X, X, X, X, M, M, M, M, M, D, n, n],  // 10 mouth
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 11
        [n, n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n, n],  // 12
        [n, n, n, n, D, D, M, M, M, M, M, M, M, M, D, D, n, n, n, n],  // 13
        [n, n, n, n, n, D, D, D, D, D, D, D, D, D, D, n, n, n, n, n],  // 14
        [n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n],  // 15
    ])

    // ── Talking Frame 1 (mouth open) ──
    static let talking1 = SpriteFrame(pixels: [
        [n, n, n, n, n, n, D, D, D, D, D, D, D, D, n, n, n, n, n, n],  // 0
        [n, n, n, n, D, D, L, L, M, M, M, M, L, L, D, D, n, n, n, n],  // 1
        [n, n, n, D, L, L, M, M, M, M, M, M, M, M, L, L, D, n, n, n],  // 2
        [n, n, D, L, M, M, M, M, M, M, M, M, M, M, M, M, L, D, n, n],  // 3
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 4
        [n, n, D, M, M, W, W, W, M, M, M, M, W, W, W, M, M, D, n, n],  // 5  eyes top
        [n, n, D, M, M, W, W, P, M, M, M, M, W, W, P, M, M, D, n, n],  // 6  eyes mid
        [n, n, D, M, M, W, P, P, M, M, M, M, W, P, P, M, M, D, n, n],  // 7  eyes bottom
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 8
        [n, n, D, M, B, M, M, X, X, X, X, X, X, M, M, B, M, D, n, n],  // 9  mouth open top
        [n, n, D, M, M, M, M, X, M, M, M, M, X, M, M, M, M, D, n, n],  // 10 mouth sides
        [n, n, D, M, M, M, M, M, X, X, X, X, M, M, M, M, M, D, n, n],  // 11 mouth bottom
        [n, n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n, n],  // 12
        [n, n, n, n, D, D, M, M, M, M, M, M, M, M, D, D, n, n, n, n],  // 13
        [n, n, n, n, n, D, D, D, D, D, D, D, D, D, D, n, n, n, n, n],  // 14
        [n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n],  // 15
    ])

    // ── Talking Frame 2 (mouth closed) ──
    static let talking2 = SpriteFrame(pixels: [
        [n, n, n, n, n, n, D, D, D, D, D, D, D, D, n, n, n, n, n, n],  // 0
        [n, n, n, n, D, D, L, L, M, M, M, M, L, L, D, D, n, n, n, n],  // 1
        [n, n, n, D, L, L, M, M, M, M, M, M, M, M, L, L, D, n, n, n],  // 2
        [n, n, D, L, M, M, M, M, M, M, M, M, M, M, M, M, L, D, n, n],  // 3
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 4
        [n, n, D, M, M, W, W, W, M, M, M, M, W, W, W, M, M, D, n, n],  // 5  eyes top
        [n, n, D, M, M, W, W, P, M, M, M, M, W, W, P, M, M, D, n, n],  // 6  eyes mid
        [n, n, D, M, M, W, P, P, M, M, M, M, W, P, P, M, M, D, n, n],  // 7  eyes bottom
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 8
        [n, n, D, M, B, M, M, M, M, M, M, M, M, M, M, B, M, D, n, n],  // 9  blush
        [n, n, D, M, M, M, M, M, X, X, X, X, M, M, M, M, M, D, n, n],  // 10 mouth
        [n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n],  // 11
        [n, n, n, D, M, M, M, M, M, M, M, M, M, M, M, M, D, n, n, n],  // 12
        [n, n, n, n, D, D, M, M, M, M, M, M, M, M, D, D, n, n, n, n],  // 13
        [n, n, n, n, n, D, D, D, D, D, D, D, D, D, D, n, n, n, n, n],  // 14
        [n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n],  // 15
    ])

    static func frames(for state: PetAnimationState.State) -> [SpriteFrame] {
        switch state {
        case .idle: [idle1, idle2]
        case .thinking: [thinking1, thinking2]
        case .talking: [talking1, talking2]
        }
    }
}

// MARK: - Animation State

@Observable
@MainActor
final class PetAnimationState {
    enum State {
        case idle, thinking, talking

        var interval: TimeInterval {
            switch self {
            case .idle: 0.6
            case .thinking: 0.4
            case .talking: 0.15
            }
        }
    }

    var state: State = .idle
    var frameIndex: Int = 0

    func advance() {
        let frameCount = SpriteFrames.frames(for: state).count
        frameIndex = (frameIndex + 1) % frameCount
    }

    var currentFrame: SpriteFrame {
        let frames = SpriteFrames.frames(for: state)
        return frames[frameIndex % frames.count]
    }
}
