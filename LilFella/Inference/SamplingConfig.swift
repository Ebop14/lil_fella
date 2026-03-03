import Foundation

struct SamplingConfig: Sendable {
    var temperature: Float = 0.6
    var topK: Int32 = 20
    var topP: Float = 0.95
    var repeatPenalty: Float = 1.1
    var maxTokens: Int32 = 1024
    var seed: UInt32 = 1234
}
