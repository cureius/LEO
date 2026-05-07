import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.leo.app", category: "tags")

actor TagRepository {
    private let controller: PersistenceController

    init(controller: PersistenceController) {
        self.controller = controller
    }

    func fetchAll() async throws -> [Tag] {
        let context = controller.newBackgroundContext()
        let stored = try context.fetch(FetchDescriptor<StoredTag>())
        return stored.map { Tag.from($0) }
    }

    /// Returns the existing tag with that name (case-insensitive) or creates a new one.
    func findOrCreate(name: String, color: TagColor = .blue) async throws -> Tag {
        let context = controller.newBackgroundContext()
        let stored = try context.fetch(FetchDescriptor<StoredTag>())
        if let existing = stored.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return Tag.from(existing)
        }
        let tag = Tag(name: name, color: color)
        context.insert(StoredTag(id: tag.id, name: tag.name, colorRaw: tag.color.rawValue))
        try context.save()
        logger.info("Created tag '\(name)'")
        return tag
    }

    func delete(id: UUID) async throws {
        let context = controller.newBackgroundContext()
        let stored = try context.fetch(FetchDescriptor<StoredTag>())
        stored.filter { $0.id == id }.forEach { context.delete($0) }
        try context.save()
    }
}
