import SwiftUI
import PhotosUI
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "chat-session")

// Wraps a DiffPayload + its originating message ID so .sheet(item:) can bind them atomically.
private struct ProposalPresentation: Identifiable {
    let id = UUID()
    let diff: DiffPayload
    let messageID: UUID
}

// MARK: - Chat session view

struct ChatSessionView: View {
    let session: ChatSession
    let appEnv: AppEnvironment

    @State private var vm: AssistantChatViewModel
    @State private var presentedProposal: ProposalPresentation? = nil
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @FocusState private var inputFocused: Bool
    @State private var scrollProxy: ScrollViewProxy? = nil

    init(session: ChatSession, appEnv: AppEnvironment) {
        self.session = session
        self.appEnv = appEnv
        let context = ToolContext(itemRepository: appEnv.itemRepository, calendar: .current, bodyProfileRepository: appEnv.bodyProfileRepository)
        let runtime = ToolRuntime(context: context)
        _vm = State(wrappedValue: AssistantChatViewModel(
            sessionID: session.id,
            client: appEnv.claudeClient,
            toolRuntime: runtime,
            itemRepository: appEnv.itemRepository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            messageList

            // Error banner
            if let err = vm.errorMessage {
                ErrorBanner(message: err) { vm.errorMessage = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Divider().background(Theme.Color.divider)

            // Input bar
            inputBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear conversation", systemImage: "trash") {
                        Task { await vm.clearHistory() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await vm.loadHistory() }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // Compress to JPEG for display and API use
                    let jpeg = UIImage(data: data).flatMap { $0.jpegData(compressionQuality: 0.7) } ?? data
                    vm.pendingImageData = jpeg
                }
                selectedPhoto = nil
            }
        }
        .sheet(item: $presentedProposal) { proposal in
            DiffReviewSheet(diff: proposal.diff) { acceptedChanges in
                Task {
                    await applyChanges(acceptedChanges)
                    await vm.markProposalApplied(id: proposal.messageID)
                }
            }
            .environment(appEnv)
        }
    }

    // MARK: - Apply confirmed diff changes to the repository

    private func applyChanges(_ changes: [DiffChange]) async {
        for change in changes {
            do {
                switch change.kind {

                case "add":
                    guard let p = change.pendingItem else { continue }
                    let anchor = buildAnchor(start: p.start, end: p.end)
                    switch p.type {
                    case "event":
                        try await appEnv.itemRepository.add(EventItem(title: p.title, notes: p.notes, anchor: anchor))
                    case "workout":
                        try await appEnv.itemRepository.add(WorkoutItem(title: p.title, notes: p.notes, anchor: anchor))
                    case "meal":
                        try await appEnv.itemRepository.add(MealItem(title: p.title, notes: p.notes, anchor: anchor, recipeID: UUID().uuidString))
                    default:
                        try await appEnv.itemRepository.add(TaskItem(title: p.title, notes: p.notes, anchor: anchor))
                    }
                    logger.info("Added item '\(p.title)'")

                case "delete":
                    guard let uuid = UUID(uuidString: change.itemID) else {
                        logger.warning("Delete: invalid UUID '\(change.itemID)'")
                        continue
                    }
                    try await appEnv.itemRepository.delete(id: uuid)
                    logger.info("Deleted item \(change.itemID)")

                case "update" where change.field == "anchor":
                    guard let uuid = UUID(uuidString: change.itemID) else { continue }
                    let fetched = try await appEnv.itemRepository.fetch(predicate: .byID(uuid))
                    guard var item = fetched.first else {
                        logger.warning("Update: item \(change.itemID) not found")
                        continue
                    }
                    item.anchor = parseAnchorString(change.newValue)
                    item.updatedAt = .now
                    try await appEnv.itemRepository.update(item)
                    logger.info("Rescheduled item \(change.itemID)")

                default:
                    logger.warning("Unhandled change kind '\(change.kind)' for field '\(change.field)'")
                }
            } catch {
                logger.error("applyChanges '\(change.kind)' \(change.itemID): \(error)")
            }
        }
    }

    /// Build an Anchor from optional ISO8601 start/end strings.
    private func buildAnchor(start: String?, end: String?) -> Anchor {
        guard let s = start, let startDate = parseISO(s) else { return .untimed }
        if let e = end, let endDate = parseISO(e) {
            return .timeBlock(start: startDate, end: endDate)
        }
        return .point(startDate)
    }

    /// Parse the compact anchor string produced by ProposeRescheduleTool.
    /// Format: "timeBlock:<start>–<end>" or "point:<datetime>"
    private func parseAnchorString(_ s: String) -> Anchor {
        if s.hasPrefix("timeBlock:") {
            let rest = String(s.dropFirst("timeBlock:".count))
            // separator is en-dash (–, U+2013) from ProposeRescheduleTool
            let parts = rest.components(separatedBy: "–")
            if parts.count == 2,
               let start = parseISO(parts[0]),
               let end   = parseISO(parts[1]) {
                return .timeBlock(start: start, end: end)
            }
        } else if s.hasPrefix("point:") {
            let rest = String(s.dropFirst("point:".count))
            if let date = parseISO(rest) { return .point(date) }
        }
        return .untimed
    }

    private func parseISO(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)

        // 1. String includes an explicit timezone offset (e.g. "+05:30" or "Z") — honour it exactly.
        let withTZ = ISO8601DateFormatter()
        withTZ.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                                 .withColonSeparatorInTime, .withTimeZone]
        if let date = withTZ.date(from: trimmed) { return date }

        // 2. No timezone in the string (AI sent bare local time, e.g. "2026-05-12T09:00:00").
        //    Treat it as the device's local timezone — NOT UTC, which is the formatter default.
        let noTZ = ISO8601DateFormatter()
        noTZ.formatOptions = [.withFullDate, .withTime,
                               .withDashSeparatorInDate, .withColonSeparatorInTime]
        noTZ.timeZone = .current   // ← critical: avoids the UTC-offset bug
        if let date = noTZ.date(from: trimmed) { return date }

        return nil
    }

    private func parseLocalISO(_ s: String) -> Date? { parseISO(s) }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if vm.messages.isEmpty && !vm.isSending {
                        suggestionsView
                            .padding(.top, 32)
                    } else {
                        messageFeed
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollProxy = proxy }
            .onChange(of: vm.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: vm.messages.last?.text) { _, _ in scrollToBottom(proxy) }
        }
    }

    private var messageFeed: some View {
        ForEach(Array(vm.messages.enumerated()), id: \.element.id) { idx, msg in
            // Date separator
            if idx == 0 || !Calendar.current.isDate(msg.timestamp, inSameDayAs: vm.messages[idx - 1].timestamp) {
                DateSeparator(date: msg.timestamp)
            }
            MessageRow(message: msg) { proposalMessage in
                if let diff = proposalMessage.diff {
                    presentedProposal = ProposalPresentation(
                        diff: diff,
                        messageID: proposalMessage.id
                    )
                }
            }
            .id(msg.id)
        }
    }

    // MARK: - Suggestions (empty state)

    private var suggestionsView: some View {
        VStack(spacing: 28) {
            // LEO avatar
            VStack(spacing: 12) {
                LEOAvatar(size: 56)
                Text("How can I help?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Ask me about your schedule, tasks, or anything you need to plan.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Suggestion chips
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(vm.suggestions, id: \.self) { suggestion in
                    Button { Task { await vm.send(suggestion) } } label: {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Color.accent)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.Color.accent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Theme.Color.accent.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Input bar

    private var canSend: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.pendingImageData != nil
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Pending image preview strip
            if let jpeg = vm.pendingImageData, let uiImage = UIImage(data: jpeg) {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button { vm.pendingImageData = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, Color.black.opacity(0.55))
                        }
                        .offset(x: 6, y: -6)
                    }
                    .padding(.leading, 14)
                    .padding(.top, 10)
                    Spacer()
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Camera / photo picker button
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(width: 36, height: 36)
                }

                // Text field
                TextField("Message LEO…", text: $vm.inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                inputFocused ? Theme.Color.accent.opacity(0.5) : Theme.Color.divider,
                                lineWidth: 1
                            )
                    )

                // Send button
                Button {
                    Task { await vm.send() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(canSend && !vm.isSending ? Theme.Color.accent : Theme.Color.textSecondary.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: vm.isSending ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(canSend && !vm.isSending ? .white : Theme.Color.textSecondary)
                    }
                }
                .disabled(!canSend && !vm.isSending)
                .animation(.easeInOut(duration: 0.15), value: canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Helpers

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = vm.messages.last else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Error banner

    private struct ErrorBanner: View {
        let message: String
        let dismiss: () -> Void
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                Text(message).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(2)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary) }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.06), radius: 4)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - LEO Avatar

struct LEOAvatar: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.4, green: 0.2, blue: 0.9), Color(red: 0.2, green: 0.5, blue: 1.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Message row

private struct MessageRow: View {
    let message: ChatMessage
    let onDiffTap: (ChatMessage) -> Void

    var body: some View {
        Group {
            switch message.role {
            case .user:
                UserMessageRow(message: message)
            case .assistant:
                AssistantMessageRow(text: message.text, isStreaming: message.isStreaming)
            case .toolCall:
                ToolCallRow(text: message.text)
            case .diffProposal:
                if let diff = message.diff {
                    DiffProposalRow(diff: diff, isApplied: message.isApplied,
                                    onTap: { onDiffTap(message) })
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }
}

// MARK: - User message bubble

private struct UserMessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 6) {

                // Image thumbnail
                if let jpeg = message.imageData, let uiImage = UIImage(data: jpeg) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 180)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: 18, bottomLeadingRadius: 18,
                            bottomTrailingRadius: 4, topTrailingRadius: 18
                        ))

                    // OCR result card shown below the thumbnail
                    if let ocr = message.ocrText {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Read from photo", systemImage: "text.viewfinder")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))

                            Text(ocr)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(6)
                                .truncationMode(.tail)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: 220, alignment: .leading)
                        .background(.white.opacity(0.15))
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: 10, bottomLeadingRadius: 10,
                            bottomTrailingRadius: 4, topTrailingRadius: 10
                        ))
                    }
                }

                // User prompt text bubble
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Theme.Color.accent, Theme.Color.accent.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: 18, bottomLeadingRadius: 18,
                            bottomTrailingRadius: 4, topTrailingRadius: 18
                        ))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Assistant message bubble

private struct AssistantMessageRow: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            LEOAvatar(size: 28)

            VStack(alignment: .leading, spacing: 4) {
                if isStreaming && text.isEmpty {
                    TypingIndicator()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(Color(.systemBackground))
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 4, bottomLeadingRadius: 18,
                                bottomTrailingRadius: 18, topTrailingRadius: 18
                            )
                        )
                } else {
                    Group {
                        if text.isEmpty {
                            Text("…")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.Color.textPrimary)
                        } else {
                            MarkdownBubble(text: text)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 4, bottomLeadingRadius: 18,
                            bottomTrailingRadius: 18, topTrailingRadius: 18
                        )
                    )
                    .textSelection(.enabled)
                }
            }

            Spacer(minLength: 48)
        }
    }
}

// MARK: - Markdown renderer for assistant bubbles

private struct MarkdownBubble: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    private var blocks: [MDBlock] { MDBlock.parse(text) }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let s):
            Text(inline(s))
                .font(.system(size: level == 1 ? 18 : 16, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(inline(s))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(n).")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.accent)
                    .frame(minWidth: 22, alignment: .trailing)
                Text(inline(s))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .code(let s):
            Text(s)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.Color.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))

        case .para(let s):
            Text(inline(s))
                .font(.system(size: 15))
                .foregroundStyle(Theme.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

        case .divider:
            Divider().padding(.vertical, 2)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }
}

// MARK: - Markdown block model

private enum MDBlock {
    case heading(Int, String)
    case bullet(String)
    case numbered(Int, String)
    case code(String)
    case para(String)
    case divider

    static func parse(_ raw: String) -> [MDBlock] {
        var result: [MDBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var i = 0
        var codeBuf: [String] = []
        var inCode = false
        var paraBuf: [String] = []

        func flushPara() {
            let s = paraBuf.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { result.append(.para(s)) }
            paraBuf.removeAll()
        }

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // Code fence
            if raw.hasPrefix("```") {
                if inCode {
                    result.append(.code(codeBuf.joined(separator: "\n")))
                    codeBuf.removeAll(); inCode = false
                } else {
                    flushPara(); inCode = true
                }
                i += 1; continue
            }
            if inCode { codeBuf.append(raw); i += 1; continue }

            // Headings
            if trimmed.hasPrefix("### ") {
                flushPara(); result.append(.heading(3, String(trimmed.dropFirst(4)))); i += 1; continue
            }
            if trimmed.hasPrefix("## ")  {
                flushPara(); result.append(.heading(2, String(trimmed.dropFirst(3)))); i += 1; continue
            }
            if trimmed.hasPrefix("# ")   {
                flushPara(); result.append(.heading(1, String(trimmed.dropFirst(2)))); i += 1; continue
            }

            // Divider
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushPara(); result.append(.divider); i += 1; continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                flushPara()
                result.append(.bullet(String(trimmed.dropFirst(2))))
                i += 1; continue
            }

            // Numbered list  (e.g. "1. " "12. ")
            if let dotIdx = trimmed.firstIndex(of: ".") {
                let prefix = trimmed[trimmed.startIndex..<dotIdx]
                let afterDot = trimmed.index(after: dotIdx)
                if !prefix.isEmpty,
                   prefix.allSatisfy(\.isNumber),
                   afterDot < trimmed.endIndex,
                   trimmed[afterDot] == " " {
                    let num = Int(prefix) ?? 1
                    let content = String(trimmed[trimmed.index(afterDot, offsetBy: 1)...])
                    flushPara()
                    result.append(.numbered(num, content))
                    i += 1; continue
                }
            }

            // Empty line = paragraph break
            if trimmed.isEmpty { flushPara(); i += 1; continue }

            paraBuf.append(trimmed)
            i += 1
        }
        flushPara()
        // If an unclosed code fence, emit whatever we collected
        if inCode && !codeBuf.isEmpty { result.append(.code(codeBuf.joined(separator: "\n"))) }
        return result
    }
}

// MARK: - Tool call row

private struct ToolCallRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.textSecondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(.leading, 36)
    }
}

// MARK: - Diff proposal row

private struct DiffProposalRow: View {
    let diff: DiffPayload
    let isApplied: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isApplied ? "checkmark.circle.fill" : "list.bullet.clipboard.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isApplied ? Theme.Color.success : Theme.Color.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isApplied ? "Changes applied" : "Proposed changes")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text(diff.rationale)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if isApplied {
                    Text("\(diff.changes.count) item\(diff.changes.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Color.success)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .padding(14)
            .background(isApplied ? Theme.Color.success.opacity(0.06) : Theme.Color.accent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isApplied ? Theme.Color.success.opacity(0.3) : Theme.Color.accent.opacity(0.25),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.leading, 36)
        // Applied proposals still tappable (so user can review what was added)
        // but visually show they're done
    }
}

// MARK: - Date separator

private struct DateSeparator: View {
    let date: Date
    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
    var body: some View {
        HStack {
            line; Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.Color.textSecondary); line
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
    }
    private var line: some View {
        Rectangle().fill(Theme.Color.divider).frame(height: 0.5)
    }
}

// MARK: - Typing indicator

private struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.Color.textSecondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(i) * 0.15), value: phase)
            }
        }
        .onAppear {
            withAnimation { phase = 0 }
        }
    }
}
