import Foundation

enum MemoryMonitor {
    static func availableMemoryBytes() -> UInt64 {
        UInt64(os_proc_available_memory())
    }

    static func availableMemoryMB() -> Double {
        Double(availableMemoryBytes()) / (1024 * 1024)
    }

    /// Check if there's enough free memory to load a model of the given size.
    /// Requires at least 1.5x the model size for safety margin (model weights + KV cache + overhead).
    static func canLoad(modelSizeBytes: Int64) -> Bool {
        let required = UInt64(Double(modelSizeBytes) * 1.5)
        return availableMemoryBytes() > required
    }
}
