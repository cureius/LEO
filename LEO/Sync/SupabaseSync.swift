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
import CryptoKit

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

// MARK: - Sync policy (pure decisions)

/// The rules that decide *what* syncing does, separated from the Supabase I/O that
/// carries it out. Keeping them pure means they can be tested against a live
/// project's worth of edge cases without a network, a login, or a real database.
enum SyncPolicy {
    /// Which cloud rows this device should tombstone.
    ///
    /// A row qualifies only when it is active in the cloud, absent locally, *and*
    /// previously held by this device. The last condition is what distinguishes a
    /// real deletion from a row we merely failed to decode or insert — without it,
    /// one transient local write error erases the row for every device.
    static func idsToTombstone(activeRemoteIDs: [String],
                               localIDs: Set<String>,
                               knownIDs: Set<String>) -> [String] {
        activeRemoteIDs.filter { !localIDs.contains($0) && knownIDs.contains($0) }
    }

    /// Last-writer-wins, compared on the payloads' own `updatedAt`.
    ///
    /// Both sides must come from the same clock and mean the same thing. The row's
    /// `updated_at` column is stamped by the server's `set_updated_at` trigger, so
    /// comparing it against a local timestamp makes every row we just pushed look
    /// remote-newer and re-apply on every sync.
    static func shouldApplyRemote(remoteUpdatedAt: Date, localUpdatedAt: Date?) -> Bool {
        guard let localUpdatedAt else { return true }   // nothing local → take it
        return remoteUpdatedAt > localUpdatedAt
    }

    /// Which just-pushed/pulled item ids are eligible to enter the "known to the
    /// cloud" ledger (`noteKnown`) that `idsToTombstone` above draws from.
    ///
    /// Externally-managed (EventKit-mirrored) items are deliberately always
    /// excluded, never entered into that ledger at all. `EventKitBridge`'s local
    /// cleanup deletes its mirror of an item whenever it falls outside the
    /// current EventKit fetch — which happens not only on a genuine deletion but
    /// also when an event ages out of the rolling import window, a calendar/list
    /// is unsubscribed, or Calendar permission is temporarily lost. If these ids
    /// were ledger-eligible, the first time any single device's window or
    /// permission state "loses" a still-real calendar event, `idsToTombstone`
    /// would read that as "the user deleted it here" and tombstone it out of the
    /// cloud for every device — silently destroying a still-real event. Excluding
    /// them trades that (a wrongful, hard-to-notice deletion of real data) for a
    /// genuinely-deleted calendar event becoming a stale-but-harmless leftover
    /// cloud row instead — deliberately the safer failure mode.
    static func ledgerEligibleIDs(_ items: [(id: String, isExternallyManaged: Bool)]) -> [String] {
        items.filter { !$0.isExternallyManaged }.map(\.id)
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

    private var realtimeTask: Task<Void, Never>?
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private let defaults: UserDefaults

    init(itemRepository: ItemRepository,
         habitRepository: HabitRepository,
         bodyProfileRepository: BodyProfileRepository,
         manager: SupabaseManager = .shared,
         defaults: UserDefaults = .standard) {
        self.itemRepository = itemRepository
        self.habitRepository = habitRepository
        self.bodyProfileRepository = bodyProfileRepository
        self.manager = manager
        self.defaults = defaults
    }

    // MARK: Sync state
    //
    // All sync state is keyed by user id. A single global key would let one
    // account's cursor govern another's pull after a sign-out/sign-in, which
    // silently skips rows that changed while the other account was active.

    private func stateKey(_ suffix: String) -> String {
        let uid = manager.currentUserID?.uuidString.lowercased() ?? "anonymous"
        return "leo.sync.\(uid).\(suffix)"
    }

    private var lastSync: Date {
        get { (defaults.object(forKey: stateKey("lastSync")) as? Date) ?? .distantPast }
        set { defaults.set(newValue, forKey: stateKey("lastSync")) }
    }

    /// IDs this device has successfully round-tripped with the cloud for a table.
    ///
    /// Delete propagation infers "deleted here" from "absent locally", but local
    /// applies are best-effort — a row we never managed to decode or insert is
    /// also absent. Without this ledger those rows look deleted and get
    /// tombstoned for every device. Only an ID we once genuinely held locally is
    /// eligible to become a tombstone.
    private func knownIDs(_ table: String) -> Set<String> {
        Set(defaults.stringArray(forKey: stateKey("known.\(table)")) ?? [])
    }
    private func setKnownIDs(_ ids: Set<String>, _ table: String) {
        defaults.set(Array(ids), forKey: stateKey("known.\(table)"))
    }
    private func noteKnown(_ ids: some Sequence<String>, _ table: String) {
        setKnownIDs(knownIDs(table).union(ids), table)
    }
    private func forgetKnown(_ ids: some Sequence<String>, _ table: String) {
        setKnownIDs(knownIDs(table).subtracting(ids), table)
    }

    /// Content hashes of what we last exchanged, per table, keyed by row id.
    ///
    /// `Habit` and `UserBodyProfile` carry no `updatedAt`, so there is no
    /// timestamp to run last-writer-wins on. Hashing the encoded payload lets us
    /// answer the only question that matters — did this actually change? — and
    /// skip both no-op pushes and no-op applies. That is what stops two devices
    /// from re-stamping and re-applying the same habit at each other forever.
    private func contentHashes(_ table: String) -> [String: String] {
        defaults.dictionary(forKey: stateKey("hash.\(table)")) as? [String: String] ?? [:]
    }
    private func setContentHashes(_ map: [String: String], _ table: String) {
        defaults.set(map, forKey: stateKey("hash.\(table)"))
    }
    private func contentHash(_ json: String) -> String {
        SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Drop every cursor/ledger for the signed-in user.
    ///
    /// Call before `signOut()` — the keys are derived from `currentUserID`, which is
    /// nil afterwards. Used by "Back up to cloud now" so a forced backup re-pushes
    /// from a clean slate rather than trusting a ledger that may describe a cloud
    /// that no longer exists.
    func clearSyncState() {
        for suffix in ["lastSync", "known.items", "known.habits", "known.measurements",
                       "hash.habits", "hash.body_profile", "bodyProfilePushedAt"] {
            defaults.removeObject(forKey: stateKey(suffix))
        }
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
    ///
    /// Clears the ledgers first: the incremental paths skip anything whose hash or
    /// known-ID entry says "already exchanged", which is exactly the wrong answer
    /// when the user is asking for a full backup — the cloud copy may be gone.
    func backupNow() async throws {
        guard let client = manager.client, let uid = manager.currentUserID else { throw SyncError.notSignedIn }
        clearSyncState()
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

    // MARK: External ownership

    /// Is this item a mirror of a row owned by EventKit (a calendar event or a
    /// Reminders entry)?
    ///
    /// Such items are still never *written* here (see `pushItem`/write-path
    /// callers) and are still never *pulled* back down (see `pull()`'s own
    /// skip below). They ARE pushed to the cloud (`push()`), one-directionally,
    /// so read-only consumers with no EventKit cleanup pass of their own (the
    /// web app) can display them.
    ///
    /// Pushing them safely depends entirely on `id` being deterministic — see
    /// `ExternalRef.deterministicItemID` (EventItem.swift) and
    /// `EventKitBridge`'s re-keying of pre-migration items. Before that existed,
    /// each device minted its own random `id` for the same mirrored event, and
    /// pushing by `id` made one calendar event come back as a second, distinct
    /// item on the very device it came from — permanently, because EventKit
    /// reconciliation only removes items whose external event is gone. That's
    /// still exactly why `pull()` keeps skipping these rows unconditionally:
    /// deterministic ids fix push-side duplication, not the separate problem of
    /// a device applying a mirror that isn't from any calendar/list it actually
    /// subscribes to (see `pull()`'s comment for the full reasoning).
    nonisolated static func isExternallyManagedItem(_ item: any Item) -> Bool {
        if let event = item as? EventItem, event.externalRef?.source == .eventKit { return true }
        if let reminder = item as? ReminderItem, reminder.externalRef?.source == .eventKit { return true }
        return false
    }

    private func isExternallyManaged(_ item: any Item) -> Bool { Self.isExternallyManagedItem(item) }

    // MARK: Push

    private func push(client: SupabaseClient, uid: UUID, since: Date) async throws {
        let items = try await itemRepository.fetch()
        // Externally-managed (EventKit-mirrored) items ARE pushed now — each device
        // computes the same id for the same real calendar event/reminder via
        // ExternalRef.deterministicItemID, so multiple devices pushing the same
        // mirror converges to one cloud row instead of duplicating (see
        // EventKitBridge's re-keying). They must still never enter the "known to
        // the cloud" ledger below — see SyncPolicy.ledgerEligibleIDs.
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
        let managedByID = Dictionary(items.map { ($0.id.uuidString.lowercased(), isExternallyManaged($0)) }, uniquingKeysWith: { a, _ in a })
        let eligible = SyncPolicy.ledgerEligibleIDs(rows.map { (id: $0.id, isExternallyManaged: managedByID[$0.id] ?? false) })
        noteKnown(eligible, "items")
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
        var confirmed: Set<String> = []   // rows this device now genuinely holds
        var dropped: Set<String> = []     // rows tombstoned remotely

        for row in rows {
            guard let id = UUID(uuidString: row.id) else { continue }

            // Soft-deleted remotely → remove locally.
            if row.deleted_at != nil {
                if existingByID[id] != nil { try? await itemRepository.delete(id: id); applied += 1 }
                dropped.insert(row.id)
                continue
            }

            // An undecodable payload (unknown//newer `kind`, corrupt blob) must not
            // count as "seen" — otherwise delete propagation would tombstone a row
            // this build simply doesn't understand yet.
            guard let remoteItem = decodePayload(kind: row.kind, json: row.data) else {
                logger.warning("Skipping undecodable item row kind=\(row.kind, privacy: .public)")
                continue
            }

            // Deliberately still skipped here, even though push() now uploads these
            // (see push() above) — this is a scope boundary, not a leftover guard.
            // EventKitBridge's own local cleanup only knows about ITS device's
            // subscribed calendars/lists; a device with some (but not the
            // originating) calendar subscribed would apply a pulled mirror here,
            // then have its very next EventKitBridge sync delete it again as "not
            // in my calendars" — a local flicker that defeats the point. Safe
            // consumers of these pushed rows today are read-only clients with no
            // EventKit cleanup pass of their own (the web app). True native-to-
            // native convergence for a device without the originating calendar
            // needs real per-item calendar/list-origin tracking added to the
            // schema first — not attempted here.
            if isExternallyManaged(remoteItem) { continue }

            // Compare the payload's own `updatedAt` on both sides. `row.updated_at`
            // is server-stamped by the set_updated_at trigger, so pitting it against
            // a local clock makes every freshly-pushed row look remote-newer and
            // re-apply on each sync.
            if SyncPolicy.shouldApplyRemote(remoteUpdatedAt: remoteItem.updatedAt,
                                            localUpdatedAt: existingByID[id]?.updatedAt) {
                if existingByID[id] != nil { try? await itemRepository.update(remoteItem, preservingTimestamp: true) }
                else                       { try? await itemRepository.add(remoteItem) }
                applied += 1
            }
            confirmed.insert(row.id)
        }

        // Only record IDs that really landed — verify against the store rather than
        // trusting the best-effort writes above.
        let nowLocal = Set(((try? await itemRepository.fetch()) ?? []).map { $0.id.uuidString.lowercased() })
        noteKnown(confirmed.intersection(nowLocal), "items")
        forgetKnown(dropped, "items")
        logger.info("Pulled \(rows.count) rows, applied \(applied)")
    }

    // MARK: Habits

    private func encodeHabit(_ habit: Habit) -> String? {
        (try? jsonEncoder.encode(SnapshotHabit(from: habit))).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Push only habits whose content actually changed since our last exchange.
    ///
    /// Pushing every habit with `updated_at = now` on every sync made each sync
    /// look like a fresh edit to every other device, which pulled it, wrote it,
    /// posted a change notification, and synced back — a loop with no fixed point.
    private func pushHabits(client: SupabaseClient, uid: UUID) async throws {
        let habits = try await habitRepository.fetchAll()
        var hashes = contentHashes("habits")
        var rows: [HabitRow] = []
        for habit in habits {
            guard let json = encodeHabit(habit) else { continue }
            let id = habit.id.uuidString.lowercased()
            let h = contentHash(json)
            guard hashes[id] != h else { continue }   // unchanged → nothing to say
            hashes[id] = h
            rows.append(HabitRow(id: id,
                                 user_id: uid.uuidString.lowercased(),
                                 name: habit.name,
                                 data: json,
                                 updated_at: isoString(.now),
                                 deleted_at: nil))
        }
        guard !rows.isEmpty else { return }
        try await client.from("habits").upsert(rows, onConflict: "id", returning: .minimal).execute()
        setContentHashes(hashes, "habits")
        noteKnown(rows.map(\.id), "habits")
        logger.info("Pushed \(rows.count) habits")
    }

    private func pullHabits(client: SupabaseClient, since: Date) async throws {
        let q = client.from("habits").select()
        let rows: [HabitRow] = since == .distantPast
            ? try await q.execute().value
            : try await q.gt("updated_at", value: isoString(since)).execute().value
        guard !rows.isEmpty else { return }

        let existing = try await habitRepository.fetchAll()
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var hashes = contentHashes("habits")
        var confirmed: Set<String> = []
        var dropped: Set<String> = []

        for row in rows {
            guard let id = UUID(uuidString: row.id) else { continue }
            if row.deleted_at != nil {
                if existingByID[id] != nil { try? await habitRepository.delete(id: id) }
                hashes[row.id] = nil
                dropped.insert(row.id)
                continue
            }
            guard let json = row.data,
                  let data = json.data(using: .utf8),
                  let dto = try? jsonDecoder.decode(SnapshotHabit.self, from: data) else { continue }

            let habit = dto.toHabit()
            if let local = existingByID[id] {
                // Identical content → applying it would only emit a spurious change
                // notification and bounce straight back at the sender.
                if encodeHabit(local) == json { confirmed.insert(row.id); hashes[row.id] = contentHash(json); continue }
                try? await habitRepository.update(habit)
            } else {
                try? await habitRepository.add(habit)
            }
            // Record what we just took so pushHabits doesn't echo it back.
            hashes[row.id] = contentHash(json)
            confirmed.insert(row.id)
        }

        let nowLocal = Set(((try? await habitRepository.fetchAll()) ?? []).map { $0.id.uuidString.lowercased() })
        setContentHashes(hashes, "habits")
        noteKnown(confirmed.intersection(nowLocal), "habits")
        forgetKnown(dropped, "habits")
    }

    // MARK: Measurements (append-only log)

    /// Measurements are an append-only log, so anything already exchanged needs no
    /// re-upsert — and re-upserting would re-stamp `updated_at` server-side and
    /// broadcast a pointless realtime change to every device.
    private func pushMeasurements(client: SupabaseClient, uid: UUID) async throws {
        let measurements = await bodyProfileRepository.allMeasurements()
        let known = knownIDs("measurements")
        let rows: [MeasurementRow] = measurements.compactMap { m in
            let id = m.id.uuidString.lowercased()
            guard !known.contains(id),
                  let json = (try? jsonEncoder.encode(m)).flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
            return MeasurementRow(id: id,
                                  user_id: uid.uuidString.lowercased(),
                                  data: json,
                                  updated_at: isoString(m.date),
                                  deleted_at: nil)
        }
        guard !rows.isEmpty else { return }
        try await client.from("measurements").upsert(rows, onConflict: "id", returning: .minimal).execute()
        noteKnown(rows.map(\.id), "measurements")
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

        // Anything the cloud confirms we hold is already exchanged; recording it
        // keeps pushMeasurements from re-sending rows that arrived via pull.
        let held = Set(await bodyProfileRepository.allMeasurements().map { $0.id.uuidString.lowercased() })
        noteKnown(rows.filter { $0.deleted_at == nil }.map(\.id).filter { held.contains($0) }, "measurements")
    }

    // MARK: Body profile (one row per user)

    private func pushBodyProfile(client: SupabaseClient, uid: UUID) async throws {
        guard let profile = await bodyProfileRepository.load(),
              let json = (try? jsonEncoder.encode(profile)).flatMap({ String(data: $0, encoding: .utf8) }) else { return }
        var hashes = contentHashes("body_profile")
        let h = contentHash(json)
        guard hashes["self"] != h else { return }   // unchanged since our last exchange
        let row = BodyProfileRow(user_id: uid.uuidString.lowercased(), data: json, updated_at: isoString(.now))
        try await client.from("body_profiles").upsert(row, onConflict: "user_id", returning: .minimal).execute()
        hashes["self"] = h
        setContentHashes(hashes, "body_profile")
        defaults.set(Date.now, forKey: stateKey("bodyProfilePushedAt"))
    }

    /// The profile is a singleton with no `updatedAt` of its own, so last-writer-wins
    /// runs at device granularity: adopt the remote row when another device wrote it
    /// after our last push. Previously this only ever populated an empty local
    /// profile, so an edit made on one device never reached any other.
    private func pullBodyProfile(client: SupabaseClient) async throws {
        let rows: [BodyProfileRow] = try await client.from("body_profiles").select().execute().value
        guard let row = rows.first, let json = row.data, let data = json.data(using: .utf8),
              let profile = try? jsonDecoder.decode(UserBodyProfile.self, from: data) else { return }

        let local = await bodyProfileRepository.load()
        guard local != nil else {
            try? await bodyProfileRepository.save(profile)
            var hashes = contentHashes("body_profile"); hashes["self"] = contentHash(json)
            setContentHashes(hashes, "body_profile")
            return
        }

        // Identical content → nothing to do.
        var hashes = contentHashes("body_profile")
        let remoteHash = contentHash(json)
        guard hashes["self"] != remoteHash else { return }

        let ourLastPush = (defaults.object(forKey: stateKey("bodyProfilePushedAt")) as? Date) ?? .distantPast
        let remoteWritten = parseISO(row.updated_at) ?? .distantPast
        guard remoteWritten > ourLastPush else { return }   // our local edit is newer — let push win

        try? await bodyProfileRepository.save(profile)
        hashes["self"] = remoteHash
        setContentHashes(hashes, "body_profile")
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

    /// After pull, tombstone the rows this device actually deleted.
    ///
    /// "Active in cloud but absent locally" alone is not evidence of deletion —
    /// it is equally the signature of a row we failed to decode or insert, or one
    /// written by a device running a newer build. Requiring the ID to be in the
    /// known-synced ledger narrows this to rows we demonstrably held and no longer
    /// do, which is the only case that means "the user deleted it here".
    private func propagateDeletes(client: SupabaseClient, table: String, localIDs: Set<String>) async throws {
        let active: [IDRow] = try await client.from(table).select("id").is("deleted_at", value: nil).execute().value
        let toTombstone = SyncPolicy.idsToTombstone(activeRemoteIDs: active.map(\.id),
                                                    localIDs: localIDs,
                                                    knownIDs: knownIDs(table))
        guard !toTombstone.isEmpty else { return }
        struct Tomb: Encodable { let deleted_at: String }
        var tombstoned: Set<String> = []
        for id in toTombstone {
            do {
                try await client.from(table).update(Tomb(deleted_at: isoString(.now))).eq("id", value: id).execute()
                tombstoned.insert(id)
            } catch {
                logger.error("Tombstone failed for \(table) \(id, privacy: .public): \(error.localizedDescription)")
            }
        }
        forgetKnown(tombstoned, table)
        logger.info("Tombstoned \(tombstoned.count) deleted \(table)")
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
        if let h = item as? HabitInstanceItem, let dto = try? SnapshotHabitInstance(from: h), let j = enc(dto) { return ("habitInstance", j) }
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
        case "habitInstance": return (try? jsonDecoder.decode(SnapshotHabitInstance.self, from: data))?.toItemOrNil()
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
private extension SnapshotHabitInstance { func toItemOrNil() -> (any Item)? { try? toItem() } }

// MARK: - App-level live sync controller

/// Owns sync for the whole app lifetime (not tied to any screen):
///   • initial sync + realtime on launch/sign-in
///   • debounced push whenever local data changes (`leoDataDidChange`)
///   • a foreground sync hook
/// This is what makes edits made anywhere in the app (add/complete events, etc.)
/// actually reach the cloud — previously sync only ran while the Cloud Sync
/// screen was open.
@MainActor
final class LiveSyncController {
    static let shared = LiveSyncController()

    private var service: CloudSyncService?
    private var changeObserver: Task<Void, Never>?
    private var pushDebounce: Task<Void, Never>?

    private init() {}

    func configure(itemRepository: ItemRepository,
                   habitRepository: HabitRepository,
                   bodyProfileRepository: BodyProfileRepository) {
        if service == nil {
            service = CloudSyncService(itemRepository: itemRepository,
                                       habitRepository: habitRepository,
                                       bodyProfileRepository: bodyProfileRepository)
        }
    }

    /// Restore a saved session, then (if signed in) sync + go live. Idempotent.
    func startIfSignedIn() async {
        await SupabaseManager.shared.restoreSession()
        await activate()
    }

    /// Begin live sync — call after a fresh sign-in too.
    func activate() async {
        guard SupabaseManager.shared.isSignedIn, let service else { return }
        try? await service.sync()
        goLive()
    }

    /// Start realtime + local-change observation without an extra initial sync
    /// (used when the caller already ran a sync for its UI).
    func goLive() {
        guard SupabaseManager.shared.isSignedIn, let service else { return }
        service.startRealtime()
        observeLocalChanges()
    }

    func deactivate() {
        changeObserver?.cancel(); changeObserver = nil
        pushDebounce?.cancel(); pushDebounce = nil
        service?.stopRealtime()
    }

    func syncOnForeground() async {
        guard SupabaseManager.shared.isSignedIn, let service else { return }
        try? await service.sync()
    }

    // Manual actions surfaced by the Cloud Sync screen.
    func syncNow() async throws { guard let s = service else { throw SyncError.notConfigured }; try await s.sync() }
    func backupNow() async throws { guard let s = service else { throw SyncError.notConfigured }; try await s.backupNow() }
    func restoreFromCloud() async throws { guard let s = service else { throw SyncError.notConfigured }; try await s.restoreFromCloud() }

    private func observeLocalChanges() {
        guard changeObserver == nil else { return }
        changeObserver = Task { [weak self] in
            let stream = NotificationCenter.default.notifications(named: .leoDataDidChange)
            for await _ in stream { self?.schedulePush() }
        }
    }

    private func schedulePush() {
        pushDebounce?.cancel()
        pushDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.syncOnForeground()
        }
    }
}

#endif
