import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "today")

@MainActor
@Observable
final class TodayViewModel {
    // MARK: - Published state
    private(set) var timedItems: [any Item] = []
    private(set) var untimedItems: [any Item] = []
    private(set) var isLoading = false
    private(set) var error: String? = nil

    var selectedDate: Date = Calendar.current.startOfDay(for: .now) {
        didSet { Task { await loadItems() } }
    }

    // MARK: - Dependencies
    private let itemRepository: ItemRepository
    private var debounceTask: Task<Void, Never>? = nil

    init(itemRepository: ItemRepository) {
        self.itemRepository = itemRepository
    }

    // MARK: - Change observation

    /// Call once after init. Listens for data-change notifications and reloads
    /// with a 400 ms debounce so burst writes (e.g. seeding) cause only one reload.
    func startObserving() async {
        for await _ in NotificationCenter.default.notifications(named: .leoDataDidChange) {
            debounceTask?.cancel()
            debounceTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self else { return }
                await self.loadItems()
            }
        }
    }

    // MARK: - Load

    func loadItems() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let interval = dayInterval(for: selectedDate)
            let all = try await itemRepository.fetch(predicate: .inDateInterval(interval))
            let open = all.filter { !$0.isCompleted }
            timedItems = open.filter { !$0.anchor.isUntimed }.sorted {
                ($0.anchor.sortDate ?? .distantFuture) < ($1.anchor.sortDate ?? .distantFuture)
            }
            untimedItems = try await itemRepository.fetch(predicate: .untimed)
                .filter { !$0.isCompleted }
        } catch {
            self.error = error.localizedDescription
            logger.error("TodayViewModel load failed: \(error)")
        }
    }

    func completeItem(_ item: any Item) async {
        var updated = item
        updated.completion = .completed(at: .now)
        updated.updatedAt = .now
        do {
            try await itemRepository.update(updated)
            await loadItems()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteItem(_ item: any Item) async {
        do {
            try await itemRepository.delete(id: item.id)
            await loadItems()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reschedule(item: any Item, to newAnchor: Anchor) async {
        var updated = item
        updated.anchor = newAnchor
        updated.updatedAt = .now
        do {
            try await itemRepository.update(updated)
            await loadItems()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Timeline math helpers

    /// Pixels-per-minute scale for the timeline (60pt per hour = 1pt per min).
    static let pixelsPerMinute: CGFloat = 1.0

    /// Y-offset in the timeline for a given date.
    static func yOffset(for date: Date, startHour: Int = 6) -> CGFloat {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let totalMinutes = CGFloat((hour - startHour) * 60 + minute)
        return totalMinutes * pixelsPerMinute
    }

    static func duration(for item: any Item) -> CGFloat {
        switch item.anchor {
        case .timeBlock(let s, let e):
            return CGFloat(e.timeIntervalSince(s) / 60) * pixelsPerMinute
        default:
            return 44 * pixelsPerMinute  // minimum touch height in minutes
        }
    }

    // MARK: - Private

    private func dayInterval(for date: Date) -> DateInterval {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }
}
