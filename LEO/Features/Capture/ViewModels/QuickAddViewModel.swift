import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "capture")

@MainActor
@Observable
final class QuickAddViewModel {
    var text: String = "" {
        didSet { scheduleParseDebounce() }
    }
    private(set) var parseState: ParseState = .idle
    private(set) var lastSavedID: UUID? = nil

    private let parser: any QuickAddParser
    private let repository: ItemRepository
    private var debounceTask: Task<Void, Never>? = nil

    init(parser: any QuickAddParser = CompositeParser(), repository: ItemRepository) {
        self.parser = parser
        self.repository = repository
    }

    // MARK: - Parse debounce

    private func scheduleParseDebounce() {
        debounceTask?.cancel()
        guard !text.isEmpty else {
            parseState = .idle
            return
        }
        parseState = .parsing
        debounceTask = Task { [weak self, text] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let result = await self.parser.parse(text)
            self.parseState = .parsed(result)
        }
    }

    // MARK: - Submit

    var parsedSummary: String? {
        if case .parsed(let r) = parseState, !text.isEmpty { return r.rationale }
        return nil
    }

    var parsedDraft: (any Item)? {
        if case .parsed(let r) = parseState { return r.draft }
        return nil
    }

    func submit() async -> Bool {
        let captureText = text
        guard !captureText.isEmpty else { return false }

        let draft: any Item
        if case .parsed(let r) = parseState, let d = r.draft {
            draft = d
        } else {
            draft = TaskItem(title: captureText, anchor: .untimed)
        }

        do {
            try await repository.add(draft)
            lastSavedID = draft.id
            text = ""
            parseState = .idle
            logger.info("Captured: '\(captureText)'")
            return true
        } catch {
            logger.error("Capture failed: \(error)")
            return false
        }
    }

    /// Undo the last capture (10-second window).
    func undo() async {
        guard let id = lastSavedID else { return }
        try? await repository.delete(id: id)
        lastSavedID = nil
    }
}
