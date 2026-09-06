import Foundation
import CryptoKit

/// A time-blocked calendar event with optional location and attendees.
public struct EventItem: Item {
    public let id: UUID
    public var title: String
    public var notes: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var importance: Importance
    public var anchor: Anchor
    public var completion: Completion
    public var tags: [Tag]

    /// Human-readable address or venue name.
    public var location: String?
    /// Names or email addresses; no Contacts integration in v1.
    public var attendees: [String]
    /// External calendar/event reference for EventKit-sourced items.
    public var externalRef: ExternalRef?
    public var rruleRaw: String?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        importance: Importance = .normal,
        anchor: Anchor,
        completion: Completion = .open,
        tags: [Tag] = [],
        location: String? = nil,
        attendees: [String] = [],
        externalRef: ExternalRef? = nil,
        rruleRaw: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.importance = importance
        self.anchor = anchor
        self.completion = completion
        self.tags = tags
        self.location = location
        self.attendees = attendees
        self.externalRef = externalRef
        self.rruleRaw = rruleRaw
    }
}

// MARK: - Meeting link detection

/// Finds a video-meeting join link (Zoom, Google Meet, Teams, …) inside an
/// event's location / notes / title, so the UI can offer a one-tap "Join" button.
public enum MeetingLinkDetector {
    /// Recognized conferencing hosts (substring match against URL host).
    private static let hosts: [String] = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "gotomeeting.com", "whereby.com", "meet.jit.si",
        "bluejeans.com", "chime.aws", "around.co", "8x8.vc"
    ]

    /// Returns a recognized meeting URL, or nil. Only matches known conferencing
    /// hosts so we never show "Join" for an unrelated link.
    public static func detect(notes: String?, location: String?, title: String?) -> URL? {
        let blob = [location, notes, title].compactMap { $0 }.joined(separator: "\n")
        guard !blob.isEmpty else { return nil }
        for url in urls(in: blob) {
            let host = url.host?.lowercased() ?? ""
            if hosts.contains(where: { host.contains($0) }) { return url }
        }
        return nil
    }

    /// A friendly provider name for the button label.
    public static func provider(for url: URL) -> String {
        let h = url.host?.lowercased() ?? ""
        if h.contains("zoom") { return "Zoom" }
        if h.contains("meet.google") { return "Google Meet" }
        if h.contains("teams") { return "Teams" }
        if h.contains("webex") { return "Webex" }
        if h.contains("jit.si") { return "Jitsi" }
        if h.contains("whereby") { return "Whereby" }
        if h.contains("gotomeeting") { return "GoTo" }
        if h.contains("bluejeans") { return "BlueJeans" }
        return "Meeting"
    }

    private static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }
}

public extension EventItem {
    /// The video-meeting join link for this event, if any.
    var meetingLink: URL? { MeetingLinkDetector.detect(notes: notes, location: location, title: title) }

    /// Notes with provider boilerplate removed (the meeting link is surfaced as a
    /// Join button instead, so the raw invite footer isn't needed here).
    var cleanedNotes: String { EventNotes.cleaned(notes ?? "") }
}

/// Cleans noisy calendar-invite notes (e.g. Google's `-::~:~::~:…` separator
/// lines and the Meet/Zoom dial-in footer) for a tidy, Apple-Calendar-like read.
public enum EventNotes {
    public static func cleaned(_ raw: String) -> String {
        let decorative = Set("-:~_=*·—–")
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        // Drop lines made up entirely of decorative separator characters.
        let kept = lines.filter { line in
            let stripped = line.filter { !$0.isWhitespace }
            if stripped.isEmpty { return true }                 // keep blanks (collapsed below)
            return !stripped.allSatisfy { decorative.contains($0) }
        }

        // Collapse runs of blank lines and trim.
        var out: [String] = []
        var blanks = 0
        for line in kept {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blanks += 1
                if blanks == 1 { out.append("") }
            } else {
                blanks = 0
                out.append(line)
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reference to an item sourced from an external system (EventKit, etc.).
public struct ExternalRef: Hashable, Sendable, Codable {
    public enum Source: String, Hashable, Sendable, Codable { case eventKit }
    public let source: Source
    public let identifier: String
    public let lastSeen: Date

    public init(source: Source, identifier: String, lastSeen: Date = .now) {
        self.source = source
        self.identifier = identifier
        self.lastSeen = lastSeen
    }

    /// A stable id derived purely from `source` + `identifier`, so every device that
    /// independently mirrors the *same* external event/reminder computes the *same*
    /// local item id — the prerequisite for pushing EventKit mirrors to the cloud
    /// (SupabaseSync.push) without each device's random per-mirror id creating a
    /// duplicate row for the same real event.
    ///
    /// Deliberately hashes ONLY `source`+`identifier`, never the whole struct —
    /// `lastSeen` defaults to `.now` at construction, so hashing it in would make
    /// every device (and every re-mirror) compute a different id, silently
    /// reintroducing the exact duplication this exists to prevent.
    ///
    /// Not a spec-pure UUIDv5 (that mandates SHA-1); this only needs to be
    /// internally stable and collision-resistant, not interoperable with an
    /// external UUIDv5 generator.
    public var deterministicItemID: UUID {
        let digest = SHA256.hash(data: Data("\(source.rawValue):\(identifier)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5 (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return NSUUID(uuidBytes: bytes) as UUID
    }
}
