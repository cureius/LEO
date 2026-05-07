import Foundation

/// Fast, zero-LLM parser covering ~80% of common quick-add phrases.
/// Uses NSDataDetector for dates + a custom recognizer for recurrence, type hints, and modifiers.
/// Confidence returned is deterministic (weighted rule scoring), not probabilistic.
public struct DeterministicParser: QuickAddParser, Sendable {
    public init() {}

    public func parse(_ text: String) async -> ParseResult {
        let input = text.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else {
            return ParseResult(draft: nil, confidence: 0, rationale: "Empty input")
        }

        let lower = input.lowercased()
        var score: Double = 0.0
        var residual = input

        // MARK: - Type detection
        let itemType = detectType(lower: lower)
        score += itemType.confidence

        // MARK: - Date / time detection
        let dateResult = detectDateTime(in: input)
        score += dateResult.score

        // MARK: - Recurrence detection
        let recurrence = detectRecurrence(lower: lower)
        score += recurrence.score

        // MARK: - Location detection
        var location: String? = nil
        if let atRange = lower.range(of: #"(?:@|at )([\w\s]+(?:st|ave|blvd|rd|dr|ln|pl)?)"#, options: .regularExpression) {
            location = String(input[atRange]).replacingOccurrences(of: "at ", with: "").replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespaces)
            score += 0.05
        }

        // MARK: - Importance detection
        let importance = detectImportance(lower: lower)

        // MARK: - Build title (strip recognized tokens from residual)
        let title = cleanTitle(residual, dateString: dateResult.rawString, recurrenceString: recurrence.rawString)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = title.isEmpty ? input : title

        // MARK: - Build anchor
        let anchor = buildAnchor(type: itemType, dateResult: dateResult)

        // MARK: - Build draft
        let draft = buildDraft(
            type: itemType,
            title: finalTitle,
            anchor: anchor,
            importance: importance,
            location: location,
            recurrence: recurrence.rule
        )

        let finalScore = min(1.0, score)
        let rationale = buildRationale(type: itemType, anchor: anchor, recurrence: recurrence, confidence: finalScore)
        return ParseResult(draft: draft, confidence: finalScore, rationale: rationale)
    }

    // MARK: - Type detection

    private struct TypeResult {
        let type: ParsedType
        let confidence: Double
    }

    private enum ParsedType { case task, event, reminder, alarm }

    private func detectType(lower: String) -> TypeResult {
        let alarmPhrases = ["wake me", "alarm", "wake up"]
        let reminderPhrases = ["remind me", "reminder", "don't forget", "call ", "email ", "message "]
        let eventPhrases = ["meeting", "dentist", "doctor", "lunch", "dinner", "breakfast", "gym", "yoga", "class", "appointment"]

        if alarmPhrases.contains(where: { lower.contains($0) }) {
            return TypeResult(type: .alarm, confidence: 0.35)
        }
        if reminderPhrases.contains(where: { lower.contains($0) }) {
            return TypeResult(type: .reminder, confidence: 0.3)
        }
        if eventPhrases.contains(where: { lower.contains($0) }) {
            return TypeResult(type: .event, confidence: 0.25)
        }
        return TypeResult(type: .task, confidence: 0.15)
    }

    // MARK: - DateTime detection

    private struct DateTimeResult {
        let date: Date?
        let endDate: Date?  // for duration-based events
        let score: Double
        let rawString: String
    }

    private func detectDateTime(in text: String) -> DateTimeResult {
        let lower = text.lowercased()

        // Manual pattern matching for common phrases
        let cal = Calendar.current
        let now = Date.now

        // "tomorrow" / "today" / "tonight"
        if lower.contains("tomorrow") {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
            let base = cal.startOfDay(for: tomorrow)
            let withTime = extractTime(from: lower, baseDate: base)
            return DateTimeResult(date: withTime ?? cal.date(bySettingHour: 9, minute: 0, second: 0, of: base), endDate: nil, score: 0.35, rawString: "tomorrow")
        }
        if lower.contains("tonight") {
            let base = cal.startOfDay(for: now)
            let evening = cal.date(bySettingHour: 20, minute: 0, second: 0, of: base)!
            return DateTimeResult(date: evening, endDate: nil, score: 0.35, rawString: "tonight")
        }
        if lower.contains("today") {
            let withTime = extractTime(from: lower, baseDate: cal.startOfDay(for: now))
            return DateTimeResult(date: withTime, endDate: nil, score: withTime != nil ? 0.35 : 0.2, rawString: "today")
        }

        // "next Monday/Tuesday/…" or "this Monday"
        let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
        // Common abbreviation forms
        let weekdayAbbrevs = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
        // Check MWF pattern
        if lower.contains("mwf") || lower.contains("m/w/f") {
            let nextMonday = nextWeekday(2, from: now, cal: cal)
            let withTime = extractTime(from: lower, baseDate: nextMonday)
            return DateTimeResult(date: withTime ?? cal.date(bySettingHour: 7, minute: 0, second: 0, of: nextMonday), endDate: nil, score: 0.3, rawString: "MWF")
        }

        for (name, weekdayNum) in weekdays {
            if lower.contains(name) {
                let target = nextWeekday(weekdayNum, from: now, cal: cal)
                let withTime = extractTime(from: lower, baseDate: target)
                return DateTimeResult(date: withTime ?? cal.date(bySettingHour: 9, minute: 0, second: 0, of: target), endDate: nil, score: 0.35, rawString: name)
            }
        }

        for (name, weekdayNum) in weekdayAbbrevs {
            if lower.contains(" \(name) ") || lower.hasPrefix("\(name) ") {
                let target = nextWeekday(weekdayNum, from: now, cal: cal)
                let withTime = extractTime(from: lower, baseDate: target)
                return DateTimeResult(date: withTime, endDate: nil, score: 0.3, rawString: name)
            }
        }

        // "in X min/hours"
        if let match = lower.range(of: #"in (\d+) (min|hour|hr)"#, options: .regularExpression) {
            let matched = String(lower[match])
            let numbers = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if let n = numbers.first {
                let isHour = matched.contains("hour") || matched.contains("hr")
                let offset = TimeInterval(n) * (isHour ? 3600 : 60)
                return DateTimeResult(date: now.addingTimeInterval(offset), endDate: nil, score: 0.4, rawString: matched)
            }
        }

        // "by Friday/tomorrow/…" → deadline on task
        if lower.contains("by ") {
            if let afterBy = lower.range(of: "by ") {
                let phrase = String(lower[afterBy.upperBound...])
                for (name, weekdayNum) in weekdays where phrase.hasPrefix(name) {
                    let target = nextWeekday(weekdayNum, from: now, cal: cal)
                    return DateTimeResult(date: target, endDate: nil, score: 0.3, rawString: "by \(name)")
                }
                if phrase.hasPrefix("tomorrow") {
                    let t = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
                    return DateTimeResult(date: t, endDate: nil, score: 0.3, rawString: "by tomorrow")
                }
            }
        }

        // Fall back to NSDataDetector
        if let detected = nsDataDetectorDate(in: text) {
            return DateTimeResult(date: detected, endDate: nil, score: 0.3, rawString: "")
        }

        // Just a time with no date → today
        if let tod = extractTime(from: lower, baseDate: cal.startOfDay(for: now)) {
            return DateTimeResult(date: tod, endDate: nil, score: 0.25, rawString: "")
        }

        return DateTimeResult(date: nil, endDate: nil, score: 0.0, rawString: "")
    }

    private func extractTime(from text: String, baseDate: Date) -> Date? {
        // Patterns: "6pm", "6:30pm", "6:30 pm", "6 pm", "noon", "midnight"
        let cal = Calendar.current
        if text.contains("noon") {
            return cal.date(bySettingHour: 12, minute: 0, second: 0, of: baseDate)
        }
        if text.contains("midnight") {
            return cal.date(bySettingHour: 0, minute: 0, second: 0, of: baseDate)
        }
        if text.contains("morning") {
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate)
        }
        if text.contains("afternoon") {
            return cal.date(bySettingHour: 14, minute: 0, second: 0, of: baseDate)
        }
        if text.contains("evening") {
            return cal.date(bySettingHour: 19, minute: 0, second: 0, of: baseDate)
        }

        // Regex: (\d{1,2})(?::(\d{2}))?\s*(am|pm)
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            let matched = String(text[range])
            let parts = matched.components(separatedBy: CharacterSet(charactersIn: ":amp ")).filter { !$0.isEmpty }
            var hour = Int(parts[0]) ?? 0
            let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            let isPM = matched.lowercased().contains("pm")
            if isPM && hour < 12 { hour += 12 }
            if !isPM && hour == 12 { hour = 0 }
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate)
        }

        // 24h: "14:30"
        if let range = text.range(of: #"\b(\d{1,2}):(\d{2})\b"#, options: .regularExpression) {
            let matched = String(text[range])
            let nums = matched.split(separator: ":").compactMap { Int($0) }
            if nums.count == 2 {
                return cal.date(bySettingHour: nums[0], minute: nums[1], second: 0, of: baseDate)
            }
        }
        return nil
    }

    private func nextWeekday(_ weekday: Int, from date: Date, cal: Calendar) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        return cal.nextDate(after: date, matching: components, matchingPolicy: .nextTime) ?? date
    }

    private func nsDataDetectorDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let matches = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        return matches.first?.date
    }

    // MARK: - Recurrence detection

    private struct RecurrenceResult {
        let rule: RecurrenceRule?
        let score: Double
        let rawString: String
    }

    private func detectRecurrence(lower: String) -> RecurrenceResult {
        if lower.contains("every day") || lower.contains("daily") {
            return RecurrenceResult(rule: .daily(), score: 0.2, rawString: "every day")
        }
        if lower.contains("every week") || lower.contains("weekly") {
            return RecurrenceResult(rule: .weekly(on: [.monday]), score: 0.2, rawString: "every week")
        }
        if lower.contains("every sunday") { return RecurrenceResult(rule: .weekly(on: [.sunday]), score: 0.25, rawString: "every sunday") }
        if lower.contains("every monday") { return RecurrenceResult(rule: .weekly(on: [.monday]), score: 0.25, rawString: "every monday") }
        if lower.contains("every tuesday") { return RecurrenceResult(rule: .weekly(on: [.tuesday]), score: 0.25, rawString: "every tuesday") }
        if lower.contains("every wednesday") { return RecurrenceResult(rule: .weekly(on: [.wednesday]), score: 0.25, rawString: "every wednesday") }
        if lower.contains("every thursday") { return RecurrenceResult(rule: .weekly(on: [.thursday]), score: 0.25, rawString: "every thursday") }
        if lower.contains("every friday") { return RecurrenceResult(rule: .weekly(on: [.friday]), score: 0.25, rawString: "every friday") }
        if lower.contains("every saturday") { return RecurrenceResult(rule: .weekly(on: [.saturday]), score: 0.25, rawString: "every saturday") }
        if lower.contains("weekdays") || lower.contains("every workday") {
            return RecurrenceResult(rule: RecurrenceRule(raw: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", extensions: [.workdaysOnly]), score: 0.2, rawString: "weekdays")
        }
        if lower.contains("mwf") || lower.contains("m/w/f") {
            return RecurrenceResult(rule: .weekly(on: [.monday, .wednesday, .friday]), score: 0.25, rawString: "MWF")
        }
        return RecurrenceResult(rule: nil, score: 0.0, rawString: "")
    }

    // MARK: - Importance

    private func detectImportance(lower: String) -> Importance {
        if lower.contains("urgent") || lower.contains("asap") || lower.contains("!!!!") { return .urgent }
        if lower.contains("important") || lower.contains("high priority") || lower.contains("!!!") { return .high }
        return .normal
    }

    // MARK: - Title cleaning

    private func cleanTitle(_ text: String, dateString: String, recurrenceString: String) -> String {
        var result = text
        // Remove common prefixes
        let prefixes = ["remind me to ", "wake me at ", "wake me up at ", "call ", "don't forget to "]
        for prefix in prefixes where result.lowercased().hasPrefix(prefix) {
            result = String(result.dropFirst(prefix.count))
            break
        }
        // Remove "by <date>" suffix
        if let byRange = result.lowercased().range(of: #"\s+by\s+\w+"#, options: .regularExpression) {
            result = String(result[..<byRange.lowerBound])
        }
        // Remove recurrence phrases
        for phrase in ["every day", "every week", "daily", "weekly", "weekdays", "every workday",
                       "every sunday", "every monday", "every tuesday", "every wednesday",
                       "every thursday", "every friday", "every saturday", "mwf", "m/w/f"] {
            result = result.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
        }
        // Remove time phrases
        let timePatterns = [#"\d{1,2}:\d{2}\s*(am|pm)"#, #"\d{1,2}\s*(am|pm)"#,
                            "tomorrow", "tonight", "today", "noon", "midnight",
                            "morning", "afternoon", "evening"]
        for pattern in timePatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Build anchor

    private func buildAnchor(type: TypeResult, dateResult: DateTimeResult) -> Anchor {
        guard let date = dateResult.date else { return .untimed }
        switch type.type {
        case .alarm, .reminder: return .point(date)
        case .task:             return .dueAt(date)
        case .event:
            let end = date.addingTimeInterval(3600) // default 1h
            return .timeBlock(start: date, end: end)
        }
    }

    // MARK: - Build draft

    private func buildDraft(
        type: TypeResult,
        title: String,
        anchor: Anchor,
        importance: Importance,
        location: String?,
        recurrence: RecurrenceRule?
    ) -> any Item {
        switch type.type {
        case .task:
            return TaskItem(title: title, importance: importance, anchor: anchor)
        case .event:
            return EventItem(title: title, importance: importance, anchor: anchor, location: location)
        case .reminder:
            return ReminderItem(title: title, importance: importance, anchor: anchor)
        case .alarm:
            return AlarmItem(title: title, importance: .urgent, anchor: anchor)
        }
    }

    // MARK: - Rationale

    private func buildRationale(type: TypeResult, anchor: Anchor, recurrence: RecurrenceResult, confidence: Double) -> String {
        var parts: [String] = []
        switch type.type {
        case .task:     parts.append("Task")
        case .event:    parts.append("Event")
        case .reminder: parts.append("Reminder")
        case .alarm:    parts.append("Alarm")
        }
        switch anchor {
        case .dueAt(let d):       parts.append("due \(d.formatted(.relative(presentation: .named)))")
        case .timeBlock(let s, _): parts.append("at \(s.formatted(.dateTime.hour().minute()))")
        case .point(let d):       parts.append("at \(d.formatted(.dateTime.hour().minute()))")
        case .untimed:            parts.append("→ Inbox")
        default: break
        }
        if let r = recurrence.rule { parts.append("repeating (\(r.raw.prefix(20)))") }
        return parts.joined(separator: " · ")
    }
}
