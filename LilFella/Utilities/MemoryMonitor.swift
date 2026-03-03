import Foundation

enum MemoryMonitor {
    static func availableMemoryBytes() -> UInt64 {
        let bytes = os_proc_available_memory()
        // os_proc_available_memory() returns 0 on the simulator
        guard bytes > 0 else { return physicalMemoryFallback() }
        return UInt64(bytes)
    }

    static func availableMemoryMB() -> Double {
        Double(availableMemoryBytes()) / (1024 * 1024)
    }

    /// Check if there's enough free memory to load a model of the given size.
    /// Requires at least 1.5x the model size for safety margin (model weights + KV cache + overhead).
    static func canLoad(modelSizeBytes: Int64) -> Bool {
        let available = availableMemoryBytes()
        let required = UInt64(Double(modelSizeBytes) * 1.5)
        return available > required
    }

    /// Fallback when os_proc_available_memory() returns 0.
    /// Uses half of physical RAM as a conservative estimate.
    private static func physicalMemoryFallback() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory / 2
    }
}
