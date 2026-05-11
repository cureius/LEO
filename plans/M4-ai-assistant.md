# M4 — AI Assistant

**Goal of this milestone:** "Ask LEO" — a chat surface and tool-use harness where the AI proposes Diffs the user reviews. This is the marketing centerpiece.

**Target ship:** 2026-08-06 (3 weeks).

**Read before starting:** [`PRD.md`](../PRD.md) §7.6 and §8, Anthropic API docs (`docs.claude.com`), Apple FoundationModels docs.

**Prerequisites:** M3 complete. CloudKit Production deployed. Repositories stable.

---

## Task summary

- [x] M4-T01 — Claude API client + prompt caching
- [x] M4-T02 — Tool definitions + tool runtime
- [x] M4-T03 — Diff review sheet
- [x] M4-T04 — Chat UI ("Ask LEO")
- [x] M4-T05 — Model routing (on-device vs cloud)
- [x] M4-T06 — Token budget meter + privacy controls
- [ ] M4-T07 — Eval harness (deferred: requires API key + live data to be meaningful)

---

### M4-T01 — Claude API client + prompt caching
- **Status:** DONE
- **Depends on:** M3 complete
- **Estimated effort:** L

**Goal**
A typed Claude API client with prompt caching for the user's standing context.

**What to build (acceptance criteria)**
- `AI/Cloud/ClaudeClient.swift` actor:
  - Init takes `apiKey`, `model: ClaudeModel` (`.opus47`, `.sonnet46`, `.haiku45`), and an `URLSession`.
  - `func send(messages: [Message], tools: [Tool]?, system: String?) async throws -> Response`.
  - Streams via SSE; exposes both a one-shot `await response` and an `AsyncStream<StreamEvent>`.
- API key handling: stored in Keychain at runtime; loaded from `.env.local` (gitignored) for development; `nil` if absent (cloud features disabled).
- Prompt caching:
  - System prompt block tagged `cache_control: ephemeral`.
  - The user's "standing context" (preferences, energy blocks, recent recurring summary) is a second cached block.
  - Cache TTL is 5 minutes per provider docs; client warms on session open.
- Errors: `ClaudeError.unauthorized`, `.rateLimited(retryAfter:)`, `.timeout`, `.serverError(status:)`, `.malformedResponse`.
- Telemetry hook: every request emits a `(model, inputTokens, outputTokens, cacheHits, cost)` record to a local store.

**How to build it**
1. Don't use a third-party SDK. Hand-roll the HTTP — it's < 300 lines and avoids supply-chain risk. Use `URLSession.shared` with `URLRequest` and a custom SSE parser.
2. Streaming format: `text/event-stream`, lines like `data: {...}\n\n`. Parser yields `StreamEvent` cases (`messageStart`, `contentBlockDelta`, `toolUse`, `messageStop`, `error`).
3. Prompt cache: include `cache_control` on the system message's `text` content blocks per Anthropic API spec.
4. Test mode: a `MockClaudeClient` returning canned responses, used by all view-model tests so we never call the real API in CI.

**Verification**
- [ ] Real API call returns expected response with a sample prompt.
- [ ] Telemetry record shows cache hits on second call within 5min.
- [ ] Streaming yields events incrementally (test with a long output).
- [ ] CI runs entirely against `MockClaudeClient`.

**Notes / decisions**
- API key never logged. Confirm via grep before release.
- Critical fix (2026-05-11): Claude SSE sends tool `id` and `name` in `content_block_start`, not `content_block_delta`. Added `toolBlockMeta: [String: (id: String, name: String)]` dictionary keyed by block index; values are read at `content_block_stop` to emit the `.toolUse` event. Without this, tool names were empty strings and the agentic loop broke silently.
- Custom alarm sound: `leo_alarm.caf` bundled in Resources (880/1100 Hz, 22050 Hz, AAC, ~20 KB). Applied via `UNNotificationSound(named:)` on all timed notifications.

---

### M4-T02 — Tool definitions + tool runtime
- **Status:** DONE
- **Depends on:** M4-T01
- **Estimated effort:** L

**Goal**
A typed catalog of tools the AI can call, with a runtime that executes them safely against repositories. Tools never mutate; they read or return proposed Diffs.

**What to build (acceptance criteria)**
- `AI/Cloud/Tools/Tool.swift` — protocol:
  ```swift
  protocol Tool: Sendable {
    static var name: String { get }
    static var description: String { get }
    static var inputSchema: JSONSchema { get }
    associatedtype Input: Decodable & Sendable
    associatedtype Output: Encodable & Sendable
    func run(_ input: Input, context: ToolContext) async throws -> Output
  }
  ```
- Tools (read):
  - `GetTodayTool` — returns today's items.
  - `GetWeekTool` — returns 7-day items.
  - `FindFreeSlotsTool` — given duration + constraints, returns candidate `DateInterval`s.
  - `GetPreferencesTool` — returns standing prefs (energy blocks, focus times).
  - `GetItemTool` — returns one item by id.
- Tools (proposing):
  - `ProposeRescheduleTool` — input: list of (id, newAnchor); output: a `Diff` of `.update` changes.
  - `ProposeAddTool` — input: list of new items; output: `Diff` of `.add`.
  - `ProposeCancelTool` — input: list of ids; output: `Diff` of `.delete`.
- Runtime: `AI/Cloud/ToolRuntime.swift` — actor that registers tools, decodes Claude's tool-use payload, validates with the schema, executes, returns the output as a tool-result message.
- Tools never call repositories' write methods. Reading is fine; writing is the user's job after Diff approval.

**How to build it**
1. Hand-build `JSONSchema` Swift type with the subset we need (object/array/string/integer/enum/required). Or use Apple's `JSONSchema` if available in iOS 18 SDK; check first.
2. Each tool has a tiny test asserting the schema is well-formed and a sample input runs.
3. Error from a tool returns to the model as a tool_result with `is_error: true`. The model can recover or apologize.

**Verification**
- [ ] Each tool unit-tested with at least one happy and one edge case.
- [ ] Round-trip: model → tool call → tool result → model continues, on a canned conversation.

**Notes / decisions**
- Agentic loop added (2026-05-11): `AssistantChatViewModel.send()` runs `while loopCount < 6`. Each iteration streams one response, collects all `pendingCalls`, executes them in `ToolRuntime`, then appends a user message with `toolResult` blocks and loops. Exits when no tool calls remain or after 6 rounds.
- `ProposeAddTool` schema extended with richer item fields; populates a `PendingNewItem` struct (title, notes, anchor, tags). `PendingNewItem` is `Codable + Hashable + Sendable`.
- Tool result carrying a `DiffPayload` is decoded from the tool result string via `JSONDecoder().decode(WrappedDiff.self, from:)` and immediately shown as a proposal bubble + persisted to the conversation store.

---

### M4-T03 — Diff review sheet
- **Status:** DONE
- **Depends on:** M4-T02
- **Estimated effort:** M

**Goal**
When the AI proposes a `Diff`, the user sees it in a structured sheet and accepts/rejects.

**What to build (acceptance criteria)**
- `Features/AssistantChat/Views/DiffReviewSheet.swift`:
  - Header: short rationale (from `Diff.rationale`).
  - Each `ItemChange` rendered with before/after for `.update`, "+ new" for `.add`, "× removed" for `.delete`.
  - Per-change toggles to accept/reject individual changes.
  - "Apply selected" button at the bottom.
- Applying: routes through repositories on the main actor; transactional (best-effort — SwiftData doesn't expose true transactions, but we batch).
- After apply: dismiss sheet, show toast "Applied N changes" with Undo (10s).
- Each row in the diff is tappable → opens the relevant item's detail sheet for context.

**How to build it**
1. Don't build a full text diff visualizer for `notes`/`title`; show old → new as two lines.
2. For `.add` changes, render as `ItemRow` previews.
3. Undo: snapshot prior state of touched items; restore on Undo. Don't engineer a full undo stack.

**Verification**
- [ ] A canned Diff renders with accept/reject toggles.
- [ ] Partial accept works (some changes applied, others ignored).
- [ ] Undo restores within 10s.

**Notes / decisions**
- Proposals persist across session reloads (2026-05-11): `PersistedMessage` gained `diff: DiffPayload?`, `isApplied: Bool`, and `PersistedRole` gained `.diffProposal`. `AssistantChatViewModel.send()` writes the proposal immediately after the tool call.
- `sheet(isPresented:)` replaced with `sheet(item: $presentedProposal)` using a `ProposalPresentation: Identifiable` wrapper. The previous approach opened the sheet before the diff was set, resulting in a blank/black screen.
- `DiffPayload`, `DiffChange`, `PendingNewItem` all made `Hashable` (required for `Set` operations in the review sheet's per-change toggle logic).
- `onApply` closure changed from `(Set<String>)` to `([DiffChange])` to carry full change payloads through to the repository write.
- `markProposalApplied(id:)` writes `isApplied = true` to both the in-memory array and the `ConversationStore` so the "Changes applied" state survives session reloads.

---

### M4-T04 — Chat UI ("Ask LEO")
- **Status:** DONE
- **Depends on:** M4-T01, M4-T02, M4-T03
- **Estimated effort:** L

**Goal**
A chat surface for free-form planning conversations. Tool calls run transparently; Diffs surface in the review sheet.

**What to build (acceptance criteria)**
- `Features/AssistantChat/Views/AssistantChatView.swift` — chat scrollback, input bar, send button, mic icon.
- Messages: user, assistant (text), tool-call (collapsed by default, expandable), tool-result (collapsed), diff-proposal (CTA opening review sheet).
- Streaming: assistant text streams in token-by-token.
- Suggestions row when chat is empty: "Plan my week", "What's my Friday like?", "Find me 90 min for deep work this week", "I'm sick today — what should I push?".
- Conversation history persisted per-day in SwiftData (`StoredAssistantMessage`); accessible in a "Recent" sidebar.
- Settings entry to clear history.

**How to build it**
1. View model `AssistantChatViewModel` orchestrates the loop:
   - Append user message.
   - Send to Claude with tools.
   - Stream events: append text, render tool-use, await tool-result, continue.
   - When model stops with no further tool use, settle.
2. **Don't** auto-apply Diffs — always require sheet confirmation.
3. Keep the system prompt small and stable. Standing context is its own cached block.
4. Inputs longer than 1000 chars: warn the user; the assistant is for planning prompts, not paste-an-essay.

**Verification**
- [ ] Five canonical prompts (PRD §7.6) work end-to-end on a real account.
- [ ] Tool calls render and complete within reasonable time.
- [ ] History persists and reloads.

**Notes / decisions**
- Markdown rendering (2026-05-11): assistant messages render via `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))` so bold/italic/code spans display correctly. Plain text fallback if parsing fails.
- Photo-to-tasks (2026-05-11): Added `PhotosPicker` camera button in the input bar. Pending image shown as a preview strip with ✕ dismiss. `ChatMessage` gains `imageData: Data?` (JPEG thumbnail for display) and `ocrText: String?` (Vision extraction result shown as "Read from photo" card in the bubble).
- Hybrid OCR flow: `VisionOCRService.shared.recognizeText(from:)` runs first. On success, only the extracted text string goes to Claude (no image tokens). On failure, the JPEG is sent via `ImageBlock` (Claude Vision). Display bubble always shows the OCR outcome.
- Tab navigation fix (2026-05-11): `AssistantChatView`'s `hasAPIKey` is now read synchronously from Keychain at `@State` init — not asynchronously — preventing a `false→true` flip that swapped the `NavigationStack` and reset tab selection to Today.
- `ChatHomeView` renamed to `ChatHomeBody` and its own `NavigationStack` removed; it uses the parent stack from `AssistantChatView`, eliminating double-stack nesting.
- `clearHistory()` made `async`; writes `session.messages = []` and `session.title = "New chat"` to `ConversationStore` so the clear survives app relaunch.

---

### M4-T05 — Model routing (on-device vs cloud)
- **Status:** DONE
- **Depends on:** M4-T01, M1-T05
- **Estimated effort:** M

**Goal**
Pick the cheapest model that can do the job.

**What to build (acceptance criteria)**
- `AI/Routing/Router.swift` deciding per-request: on-device FoundationModels, Claude Haiku, Sonnet, Opus.
- Heuristics:
  - Pure parsing/summarizing → on-device.
  - Single-step tool use, < 4 tool calls expected → Sonnet.
  - Multi-step planning, ≥ 4 expected tool calls or > 30 items in scope → Opus.
  - User explicitly said "quick" or response is for daily brief → Haiku.
- Manual override in settings: "Always use Opus" / "Prefer on-device".
- Route reasons logged (debug) so users (and we) understand why a request cost what it cost.

**How to build it**
1. Don't try to be cute. A simple decision tree based on `prompt.length`, `toolsAvailable`, and a quick heuristic on the prompt's intent.
2. Cap downgrades: if Haiku fails to settle a tool conversation in 4 rounds, escalate to Sonnet automatically; record the escalation.

**Verification**
- [ ] Five canonical prompts route to the expected model in 90% of trials.
- [ ] Settings override forces routing.
- [ ] Log shows the reason for each route.

---

### M4-T06 — Token budget meter + privacy controls
- **Status:** DONE
- **Depends on:** M4-T01
- **Estimated effort:** S

**Goal**
The user always knows what AI is costing them and what's leaving the device.

**What to build (acceptance criteria)**
- Settings → AI:
  - Monthly token budget (Pro tiered; default 1M input + 200k output / month).
  - Bar chart of usage by day.
  - Per-request payload inspector: tap a recent request → see the exact JSON sent (with API key redacted).
  - Toggle "Send only items relevant to my prompt" (default ON; OFF expands context window with full week).
  - Toggle "Allow cloud AI" (default ON for Pro; OFF disables Claude entirely).
- An in-chat indicator on each request: chip with model name + tokens used.

**How to build it**
1. Persist usage in a `StoredAIRequest` model with `(model, inputTokens, outputTokens, cacheHits, timestamp, payloadHash)`.
2. Payload inspector reads from a per-request JSON snapshot stored in App Group temp folder; rotated every 100 requests.
3. Redact: regex-replace `sk-ant-…` patterns and the user's email if present.

**Verification**
- [ ] Usage bar reflects actual usage.
- [ ] Disabling cloud AI degrades the assistant gracefully (on-device only).
- [ ] Payload inspector never shows the raw API key.

---

### M4-T07 — Eval harness
- **Status:** TODO
- **Depends on:** M4-T01, M4-T02, M4-T05
- **Estimated effort:** L

**Goal**
A test harness that scores the assistant against a curated prompt suite. Without this, "AI quality" is vibes.

**What to build (acceptance criteria)**
- `LEOTests/AI/Eval/` directory:
  - `prompt_suite.json` — 30+ prompts grouped by category (parse, summarize, plan, conflict resolve).
  - For each prompt: a fixture user state (items, calendars, prefs) and a rubric of `expected_behaviors` (e.g., "proposes at least 1 reschedule", "respects gym Mon/Wed/Fri block").
- A test runner `AIEvalRunner.swift` that loads each prompt, runs it through the real assistant against a controlled fixture (in-memory persistence), and scores with rubric checks.
- A judge: small Claude call (Haiku) given the conversation + rubric → returns pass/fail per item with rationale. Cached.
- Aggregate report: per-category pass rate, regressions vs last run.
- Runs on demand (`xcodebuild test -only-testing:LEOTests/AIEvalSuite`); not on every CI push (cost). Nightly run on `main`.

**How to build it**
1. Use the same in-memory PersistenceController. Inject fixture data per prompt.
2. The judge is itself an LLM call; cache by `(promptID, conversationHash, rubricHash)` so re-runs are cheap if nothing changed.
3. Snapshot regressions: store last run's per-prompt pass; compare; flag downgrades.

**Verification**
- [ ] Suite runs end-to-end against a real API.
- [ ] Aggregate pass rate ≥ 80% before exit.
- [ ] A deliberately-broken prompt (e.g., model told to ignore the rubric) fails as expected.

---

## Exit criteria for M4

- [ ] All seven tasks `DONE`.
- [ ] Eval rubric pass rate ≥ 80%.
- [ ] Five canonical prompts working end-to-end.
- [ ] L2 median response time < 4s.
- [ ] Privacy: payload inspector confirms only relevant slices sent.
- [ ] User signs off in chat.
