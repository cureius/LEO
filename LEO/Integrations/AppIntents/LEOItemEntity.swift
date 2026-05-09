import AppIntents
import Foundation

/// AppIntents entity representing a single LEO item for Siri/Shortcuts pickers.
struct LEOItemEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "LEO Item")
    static let defaultQuery = LEOItemQuery()

    var id: UUID
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    let title: String
    let itemType: String

    init(id: UUID, title: String, itemType: String) {
        self.id = id
        self.title = title
        self.itemType = itemType
    }
}

// MARK: - Query

struct LEOItemQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [LEOItemEntity] {
        let items = try await SharedRepository.shared.fetch(predicate: .all)
        return items
            .filter { identifiers.contains($0.id) }
            .prefix(50)
            .map { LEOItemEntity(id: $0.id, title: $0.title, itemType: String(describing: type(of: $0))) }
    }

    func suggestedEntities() async throws -> [LEOItemEntity] {
        let items = try await SharedRepository.shared.fetch(predicate: .all)
        return items
            .filter { !$0.isCompleted }
            .prefix(50)
            .map { LEOItemEntity(id: $0.id, title: $0.title, itemType: String(describing: type(of: $0))) }
    }
}

// MARK: - Shared singleton for App Intents (executed out of process)

/// App Intents run in their own process context — they can't use AppEnvironment.
/// This provides a minimal repository backed by the same SwiftData container.
@MainActor
final class SharedRepository {
    static let shared = SharedRepository()
    private let repo: ItemRepository

    private init() {
        let controller = PersistenceController(useInMemory: false)
        repo = ItemRepository(controller: controller)
    }

    func fetch(predicate: ItemPredicate) async throws -> [any Item] {
        try await repo.fetch(predicate: predicate)
    }

    func add(_ item: any Item) async throws {
        try await repo.add(item)
    }

    func update(_ item: any Item) async throws {
        try await repo.update(item)
    }
}
