import Foundation

struct LocalModel: Identifiable, Sendable {
    let definition: ModelDefinition
    let fileURL: URL
    let downloadDate: Date

    var id: String { definition.id }
}
