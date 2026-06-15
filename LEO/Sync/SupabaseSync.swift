//  SupabaseSync.swift
//  LEO — live cross-device sync + cloud backup via Supabase (supabase-swift 2.x).
//
//  Wrapped in `#if canImport(Supabase)` so the app still builds if the package
//  is ever removed. The wire format reuses LEO's existing `Snapshot*` DTOs (the
//  same encoders the Backup & Restore feature uses) so item state round-trips
//  losslessly without bespoke per-field mapping.

import Foundation

#if canImport(Supabase)
import Supabase
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "supabase-sync")

// MARK: - Config

enum SupabaseConfig {
    static var url: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)
            .flatMap(URL.init(string:))
    }
    static var anonKey: String? {
        let k = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        return (k?.isEmpty == false) ? k : nil
    }
    static var isConfigured: Bool { url != nil && anonKey != nil }
}

// MARK: - ISO8601 helpers (timestamps travel as strings to dodge date-strategy issues)

private let isoOut: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()
private func isoString(_ d: Date) -> String { isoOut.string(from: d) }
private func parseISO(_ s: String?) -> Date? {
    guard let s else { return nil }
    let withFrac = ISO8601DateFormatter(); withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = withFrac.date(from: s) { return d }
    let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: s)
}

// MARK: - Wire row (maps 1:1 to public.items; full state lives in `data`)

private struct SyncItemRow: Codable {
    var id: String
    var user_id: String
    var kind: String
    var title: String
    var data: String          // JSON text of the matching Snapshot DTO
    var updated_at: String
    var deleted_at: String?
}

private struct HabitRow: Codable {
    var id: String
    var user_id: String
    var name: String
    var data: String?         // JSON text of SnapshotHabit
    var updated_at: String
    var deleted_at: String?
}

private struct MeasurementRow: Codable {
    var id: String
    var user_id: String
    var data: String?         // JSON text of BodyMeasurement
    var updated_at: String
    var deleted_at: String?
}

private struct BodyProfileRow: Codable {
    var user_id: String
    var data: String?         // JSON text of UserBodyProfile
    var updated_at: String
}

// MARK: - Auth manager

@MainActor
@Observable
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient?
    private(set) var currentUserID: UUID?
    var isSignedIn: Bool { currentUserID != nil }
    var isConfigured: Bool { client != nil }

    private init() {
        if let url = SupabaseConfig.url, let key = SupabaseConfig.anonKey {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        } else {
            client = nil
            logger.warning("Supabase not configured (missing SUPABASE_URL / SUPABASE_ANON_KEY)")
        }
    }

    func restoreSession() async {
        guard let client else { return }
        currentUserID = try? await client.auth.session.user.id
    }

    /// Returns `true` if a session was established immediately (email confirmation
    /// is off). Returns `false` when the project requires confirmation — the account
    /// exists but the user must click the emailed link before signing in.
    @discardableResult
    func signUp(email: String, password: String) async throws -> Bool {
        guard let client else { throw SyncError.notConfigured }
        let res = try await client.auth.signUp(email: email, password: password)
        if let session = res.session {
            currentUserID = session.user.id
            return true
        }
        return false   // confirmation required
    }

    func signIn(email: String, password: String) async throws {
        guard let client else { throw SyncError.notConfigured }
        let session = try await client.auth.signIn(email: email, password: password)
        currentUserID = session.user.id
    }

    /// Re-sends the sign-up confirmation email.
    func resendConfirmation(email: String) async throws {
        guard let client else { throw SyncError.notConfigured }
        try await client.auth.resend(email: email, type: .signup)
    }

    func signOut() async {
        try? await client?.auth.signOut()
        currentUserID = nil
    }
}

enum SyncError: LocalizedError {
    case notConfigured, notSignedIn
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Cloud sync isn't configured (missing Supabase credentials)."
        case .notSignedIn:   "Sign in to sync."
        }
    }
}

// MARK: - Sync service (items: tasks/events/reminders/alarms/workouts/meals)

@MainActor
final class CloudSyncService {
    private let manager: SupabaseManager
    private let itemRepository: ItemRepository
    private let habitRepository: HabitRepository
    private let bodyProfileRepository: BodyProfileRepository
    private let lastSyncKey = "leo.sync.items.lastSync"

    private var realtimeTask: Task<Void, Never>?
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init(itemRepository: ItemRepository,
         habitRepository: HabitRepository,
         bodyProfileRepository: BodyProfileRepository,
         manager: SupabaseManager = .shared) {
        self.itemRepository = itemRepository
        self.habitRepository = habitRepository
        self.bodyProfileRepository = bodyProfileRepository
        self.manager = manager
    }

    private var lastSync: Date {
        get { (UserDefaults.standard.object(forKey: lastSyncKey) as? Date) ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }

    // MARK: Public actions

    /// Two-way reconcile across all entities — run on sign-in & foreground.
    func sync() async throws {
        guard let client = manager.client, let uid = manager.currentUserID else { throw SyncError.notSignedIn }
        // Items are the core path (throwing). The other entities are best-effort
        // so a hiccup (e.g. migration 0002 not yet applied) never blocks items.
        try await pull(client: client, since: lastSync)
        try? await pullHabits(client: client, since: lastSync)
        try? await pullMeasurements(client: client)
        try? await pullBodyProfile(client: client)
        try await push(client: client, uid: uid, since: lastSync)
        try? await pushHabits(client: client, uid: uid)
        try? await pushMeasurements(client: client, uid: uid)
        try? await pushBodyProfile(client: client, uid: uid)
        // Propagate local deletions as cloud tombstones.
        try? await propagateDeletes(client: client, table: "items", localIDs: localItemIDs())
        try? await propagateDeletes(client: client, table: "habits", localIDs: localHabitIDs())
        lastSync = .now
        logger.info("Full sync complete")
    }

    /// Force-push everything (the "Back up to cloud now" action).
    func backupNow() async throws {
        guard let client = manager.client, let uid = manager.currentUserID else { throw SyncError.notSignedIn }
        try await push(client: client, uid: uid, since: .distantPast)
        try? await pushHabits(client: client, uid: uid)
        try? await pushMeasurements(client: client, uid: uid)
        try? await pushBodyProfile(client: client, uid: uid)
        lastSync = .now
    }

    /// Pull the entire cloud dataset into the local store (the "Restore" action).
    func restoreFromCloud() async throws {
        guard let client = manager.client, manager.currentUserID != nil else { throw SyncError.notSignedIn }
        try await pull(client: client, since: .distantPast)
        try? await pullHabits(client: client, since: .distantPast)
        try? await pullMeasurements(client: client)
        try? await pullBodyProfile(client: client)
        lastSync = .now
    }

    // MARK: Push

    private func push(client: SupabaseClient, uid: UUID, since: Date) async throws {
        let items = try await itemRepository.fetch()
        let rows: [SyncItemRow] = items.compactMap { item in
            guard item.updatedAt > since else { return nil }
            guard let (kind, json) = encodePayload(item) else { return nil }
            return SyncItemRow(id: item.id.uuidString.lowercased(),
                           user_id: uid.uuidString.lowercased(),
                           kind: kind,
                           title: item.title,
                           data: json,
                           updated_at: isoString(item.updatedAt),
                           deleted_at: nil)
        }
        guard !rows.isEmpty else { return }
        try await client.from("items").upsert(rows, onConflict: "id", returning: .minimal).execute()
        logger.info("Pushed \(rows.count) items")
    }

    // MARK: Pull

    private func pull(client: SupabaseClient, since: Date) async throws {
        let query = client.from("items").select()
        let rows: [SyncItemRow]
        if since == .distantPast {
            rows = try await query.execute().value
        } else {
            rows = try await query.gt("updated_at", value: isoString(since)).execute().value
        }
        guard !rows.isEmpty else { return }

        let existing = try await itemRepository.fetch()
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var applied = 0
        for row in rows {
            guard let id = UUID(uuidString: row.id) else { continue }

            // Soft-deleted remotely → remove locally.
            if row.deleted_at != nil {
                if existingByID[id] != nil { try? await itemRepository.delete(id: id); applied += 1 }
                continue
            }

            guard let remoteItem = decodePayload(kind: row.kind, json: row.data) else { continue }
            let remoteUpdated = parseISO(row.updated_at) ?? .distantPast

            if let local = existingByID[id] {
                // Last-writer-wins.
                if remoteUpdated > local.updatedAt {
                    try? await itemRepository.update(remoteItem)
                    applied += 1
                }
            } else {
                try? await itemRepository.add(remoteItem)
                applied += 1
            }
        }
        logger.info("Pulled \(rows.count) rows, applied \(applied)")
    }

    // MARK: Habits

    private func pushHabits(client: SupabaseClient, uid: UUID) async throws {
        let habits = try await habitRepository.fetchAll()
        let rows: [HabitRow] = habits.compactMap { habit in
            guard let json = (try? jsonEncoder.encode(SnapshotHabit(from: habit))).flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
            return HabitRow(id: habit.id.uuidString.lowercased(),
                            user_id: uid.uuidString.lowercased(),
                            name: habit.name,
                            data: json,
                            updated_at: isoString(.now),
                            deleted_at: nil)
        }
        guard !rows.isEmpty else { return }
        try await client.from("habits").upsert(rows, onConflict: "id", returning: .minimal).execute()
        logger.info("Pushed \(rows.count) habits")
    }

    private func pullHabits(client: SupabaseClient, since: Date) async throws {
        let q = client.from("habits").select()
        let rows: [HabitRow] = since == .distantPast
            ? try await q.execute().value
            : try await q.gt("updated_at", value: isoString(since)).execute().value
        guard !rows.isEmpty else { return }
        let existingIDs = Set(try await habitRepository.fetchAll().map(\.id))
        for row in rows {
            guard let id = UUID(uuidString: row.id) else { continue }
            if row.deleted_at != nil {
                if existingIDs.contains(id) { try? await habitRepository.delete(id: id) }
                continue
            }
            guard let data = row.data?.data(using: .utf8),
                  let dto = try? jsonDecoder.decode(SnapshotHabit.self, from: data) else { continue }
            let habit = dto.toHabit()
            if existingIDs.contains(id) { try? await habitRepository.update(habit) }
            else                        { try? await habitRepository.add(habit) }
        }
    }

    // MARK: Measurements (append-only log)

    private func pushMeasurements(client: SupabaseClient, uid: UUID) async throws {
        let measurements = await bodyProfileRepository.allMeasurements()
        let rows: [MeasurementRow] = measurements.compactMap { m in
            guard let json = (try? jsonEncoder.encode(m)).flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
            return MeasurementRow(id: m.id.uuidString.lowercased(),
                                  user_id: uid.uuidString.lowercased(),
                                  data: json,
                                  updated_at: isoString(m.date),
                                  deleted_at: nil)
        }
        guard !rows.isEmpty else { return }
        try await client.from("measurements").upsert(rows, onConflict: "id", returning: .minimal).execute()
    }

    private func pullMeasurements(client: SupabaseClient) async throws {
        let rows: [MeasurementRow] = try await client.from("measurements").select().execute().value
        guard !rows.isEmpty else { return }
        let existingIDs = Set(await bodyProfileRepository.allMeasurements().map(\.id))
        let newOnes: [BodyMeasurement] = rows.compactMap { row in
            guard let id = UUID(uuidString: row.id), !existingIDs.contains(id), row.deleted_at == nil,
                  let data = row.data?.data(using: .utf8) else { return nil }
            return try? jsonDecoder.decode(BodyMeasurement.self, from: data)
        }
        if !newOnes.isEmpty { try? await bodyProfileRepository.appendMeasurementBatch(newOnes) }
    }

    // MARK: Body profile (one row per user)

    private func pushBodyProfile(client: SupabaseClient, uid: UUID) async throws {
        guard let profile = await bodyProfileRepository.load(),
              let json = (try? jsonEncoder.encode(profile)).flatMap({ String(data: $0, encoding: .utf8) }) else { return }
        let row = BodyProfileRow(user_id: uid.uuidString.lowercased(), data: json, updated_at: isoString(.now))
        try await client.from("body_profiles").upsert(row, onConflict: "user_id", returning: .minimal).execute()
    }

    private func pullBodyProfile(client: SupabaseClient) async throws {
        let rows: [BodyProfileRow] = try await client.from("body_profiles").select().execute().value
        guard let row = rows.first, let data = row.data?.data(using: .utf8),
              let profile = try? jsonDecoder.decode(UserBodyProfile.self, from: data) else { return }
        // Body profile is a singleton — adopt remote when present (it changes rarely).
        if await bodyProfileRepository.load() == nil {
            try? await bodyProfileRepository.save(profile)
        }
    }

    // MARK: Delete propagation (local hard-delete → cloud tombstone)

    private func localItemIDs() async -> Set<String> {
        let items = (try? await itemRepository.fetch()) ?? []
        return Set(items.map { $0.id.uuidString.lowercased() })
    }
    private func localHabitIDs() async -> Set<String> {
        let habits = (try? await habitRepository.fetchAll()) ?? []
        return Set(habits.map { $0.id.uuidString.lowercased() })
    }

    private struct IDRow: Decodable { let id: String }

    /// After pull, any cloud row that's active but no longer present locally was
    /// deleted on this device → tombstone it so other devices remove it too.
    private func propagateDeletes(client: SupabaseClient, table: String, localIDs: Set<String>) async throws {
        let active: [IDRow] = try await client.from(table).select("id").is("deleted_at", value: nil).execute().value
        let toTombstone = active.map(\.id).filter { !localIDs.contains($0) }
        guard !toTombstone.isEmpty else { return }
        struct Tomb: Encodable { let deleted_at: String }
        for id in toTombstone {
            try? await client.from(table).update(Tomb(deleted_at: isoString(.now))).eq("id", value: id).execute()
        }
        logger.info("Tombstoned \(toTombstone.count) deleted \(table)")
    }

    // MARK: Realtime

    /// Subscribe to my rows across the synced tables; any remote change triggers a pull.
    func startRealtime() {
        guard realtimeTask == nil, let client = manager.client, manager.currentUserID != nil else { return }
        realtimeTask = Task { [weak self] in
            let channel = client.channel("leo-sync")
            let itemChanges = channel.postgresChange(AnyAction.self, table: "items")
            let habitChanges = channel.postgresChange(AnyAction.self, table: "habits")
            await channel.subscribe()
            logger.info("Realtime subscribed")
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in itemChanges { await self?.refreshFromRealtime() } }
                group.addTask { for await _ in habitChanges { await self?.refreshFromRealtime() } }
            }
        }
    }

    private func refreshFromRealtime() async {
        guard let client = manager.client else { return }
        try? await pull(client: client, since: lastSync)
        try? await pullHabits(client: client, since: lastSync)
        try? await pullMeasurements(client: client)
        lastSync = .now
    }

    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    // MARK: Payload (kind ↔ Snapshot DTO)

    private func encodePayload(_ item: any Item) -> (kind: String, json: String)? {
        func enc<T: Encodable>(_ dto: T) -> String? {
            (try? jsonEncoder.encode(dto)).flatMap { String(data: $0, encoding: .utf8) }
        }
        if let t = item as? TaskItem,      let dto = try? SnapshotTask(from: t),     let j = enc(dto) { return ("task", j) }
        if let e = item as? EventItem,     let dto = try? SnapshotEvent(from: e),    let j = enc(dto) { return ("event", j) }
        if let r = item as? ReminderItem,  let dto = try? SnapshotReminder(from: r), let j = enc(dto) { return ("reminder", j) }
        if let a = item as? AlarmItem,     let dto = try? SnapshotAlarm(from: a),    let j = enc(dto) { return ("alarm", j) }
        if let w = item as? WorkoutItem,   let dto = try? SnapshotWorkout(from: w),  let j = enc(dto) { return ("workout", j) }
        if let m = item as? MealItem,      let dto = try? SnapshotMeal(from: m),     let j = enc(dto) { return ("meal", j) }
        return nil
    }

    private func decodePayload(kind: String, json: String) -> (any Item)? {
        guard let data = json.data(using: .utf8) else { return nil }
        switch kind {
        case "task":     return (try? jsonDecoder.decode(SnapshotTask.self, from: data))?.toItemOrNil()
        case "event":    return (try? jsonDecoder.decode(SnapshotEvent.self, from: data))?.toItemOrNil()
        case "reminder": return (try? jsonDecoder.decode(SnapshotReminder.self, from: data))?.toItemOrNil()
        case "alarm":    return (try? jsonDecoder.decode(SnapshotAlarm.self, from: data))?.toItemOrNil()
        case "workout":  return (try? jsonDecoder.decode(SnapshotWorkout.self, from: data))?.toItemOrNil()
        case "meal":     return (try? jsonDecoder.decode(SnapshotMeal.self, from: data))?.toItemOrNil()
        default:         return nil
        }
    }
}

// Small throwing→optional bridges so the switch above stays terse.
private extension SnapshotTask     { func toItemOrNil() -> (any Item)? { try? toItem() } }
private extension SnapshotEvent    { func toItemOrNil() -> (any Item)? { try? toItem() } }
private extension SnapshotReminder { func toItemOrNil() -> (any Item)? { try? toItem() } }
private extension SnapshotAlarm    { func toItemOrNil() -> (any Item)? { try? toItem() } }
private extension SnapshotWorkout  { func toItemOrNil() -> (any Item)? { try? toItem() } }
private extension SnapshotMeal     { func toItemOrNil() -> (any Item)? { try? toItem() } }

#endif
