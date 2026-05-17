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
    private(set) var completedTodayItems: [any Item] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String? = nil

    // Week strip & month grid data
    var weekOffset: Int = 0 {
        didSet {
            guard weekOffset != oldValue else { return }
            Task { await loadWeekCounts() }
        }
    }
    private(set) var weekItemCounts: [Date: Int] = [:]
    private(set) var monthItemDates: Set<Date> = []

    var selectedDate: Date = Calendar.current.startOfDay(for: .now) {
        didSet {
            syncWeekOffset()
            Task { await loadItems() }
        }
    }

    // MARK: - Computed helpers for the calendar strip

    var weekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let wd = cal.component(.weekday, from: today)
        let monday = cal.date(byAdding: .day, value: -((wd + 5) % 7), to: today)!
        let weekStart = cal.date(byAdding: .weekOfYear, value: weekOffset, to: monday)!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: weekStart)! }
    }

    var weekItemTotal: Int { weekItemCounts.values.reduce(0, +) }

    var visibleMonthLabel: String { weekDays[3].formatted(.dateTime.month(.wide).year()) }

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
        if !hasLoaded { isLoading = true }
        error = nil
        defer { isLoading = false }
        do {
            let interval = dayInterval(for: selectedDate)
            let all = try await itemRepository.fetch(predicate: .inDateInterval(interval))
            let open = all.filter { !$0.isCompleted }
            timedItems = open.filter { !$0.anchor.isUntimed }.sorted { a, b in
                let da = a.anchor.sortDate ?? .distantFuture
                let db = b.anchor.sortDate ?? .distantFuture
                if da != db { return da < db }
                // Tiebreaker: point-in-time items before time blocks at the same moment
                return a.anchor.sortPriority < b.anchor.sortPriority
            }
            // Untimed tasks belong to today's backlog only
            if Calendar.current.isDateInToday(selectedDate) {
                untimedItems = try await itemRepository.fetch(predicate: .untimed)
                    .filter { !$0.isCompleted }
            } else {
                untimedItems = []
            }
            completedTodayItems = all.filter { $0.isCompleted }.sorted {
                ($0.anchor.sortDate ?? .distantPast) < ($1.anchor.sortDate ?? .distantPast)
            }
            await loadWeekCounts()
            hasLoaded = true
        } catch {
            self.error = error.localizedDescription
            logger.error("TodayViewModel load failed: \(error)")
        }
    }

    // MARK: - Week / month data loading

    func loadWeekCounts() async {
        let cal = Calendar.current
        let days = weekDays
        guard let first = days.first, let last = days.last else { return }
        let interval = DateInterval(
            start: cal.startOfDay(for: first),
            end: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last))!
        )
        let items = (try? await itemRepository.fetch(predicate: .inDateInterval(interval))) ?? []
        var counts: [Date: Int] = [:]
        for item in items {
            guard let d = item.anchor.sortDate else { continue }
            counts[cal.startOfDay(for: d), default: 0] += 1
        }
        weekItemCounts = counts
    }

    func loadMonthDates(for month: Date) async {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return }
        let items = (try? await itemRepository.fetch(predicate: .inDateInterval(DateInterval(start: start, end: end)))) ?? []
        monthItemDates = Set(items.compactMap { item -> Date? in
            guard let d = item.anchor.sortDate else { return nil }
            return cal.startOfDay(for: d)
        })
    }

    private func syncWeekOffset() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let thisMonday = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: today) + 5) % 7), to: today)!
        let selMonday = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: selectedDate) + 5) % 7), to: selectedDate)!
        weekOffset = cal.dateComponents([.weekOfYear], from: thisMonday, to: selMonday).weekOfYear ?? 0
    }

    func completeItem(_ item: any Item) async {
        var updated = item
        updated.completion = item.isCompleted ? .open : .completed(at: .now)
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
