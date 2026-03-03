import Foundation

struct InferenceConfig: Sendable {
    var contextLength: UInt32 = 2048
    var batchSize: Int32 = 512
    var threadCount: Int32 = {
        Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
    }()
    var gpuLayerCount: Int32 = {
        #if targetEnvironment(simulator)
        return 0
        #else
        return -1 // all layers on GPU
        #endif
    }()
    var flashAttention: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }()
}
