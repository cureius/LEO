# MM5 — AI Assistant & Recurrence Builder

**Goal:** Ask LEO works on Mac with full parity: chat history, streaming responses, tool use (read + propose), AI proposes diffs, user accepts/rejects in a side pane (not modal). The recurrence builder is reachable from the inspector and matches iOS behavior.

**Exit criteria:**
- Chat is functional end-to-end: send → tool calls → streamed response → diff proposed → accept/reject.
- Conversation history persists in `ConversationStore` (existing).
- AI proposals never silently mutate (Anti-divergence rule).
- Recurrence builder edits an item's RRULE and saves correctly.

## Summary checklist
- [ ] MM5-T01 — `MacAssistantChatView` (chat home + session)
- [ ] MM5-T02 — `MacDiffReviewPane` (side-by-side diff, not sheet)
- [ ] MM5-T03 — `MacRecurrenceBuilderSheet`
- [ ] MM5-T04 — Voice input in chat (reuse MM4-T04 service)
- [ ] MM5-T05 — Assistant entry from command palette

---

### MM5-T01 — `MacAssistantChatView`
- **Status:** TODO
- **Depends on:** MM3-T07
- **Estimated effort:** L

**Goal**
Port `AssistantChatView` to a Mac middle-column experience. Chat home lists past conversations; session view streams Claude responses; tool invocation banners appear inline as on iOS.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/AssistantChat/MacAssistantChatView.swift` switches between chat home and session view.
- Chat home: list of past conversations (`ConversationStore`), "New conversation" button.
- Session view: scrollable message list, composer at bottom (multi-line `TextEditor`), send via `⌘Return`.
- Tool call banners (read tools, propose tools) render inline as on iOS.
- Streaming: tokens appended live via the existing `ClaudeClient` SSE.
- `AssistantChatViewModel` (existing) reused unchanged.
- Conversation history persists across launches (via existing `ConversationStore` which uses SwiftData or UserDefaults — verify).

**How to build it**
1. Read existing `Features/AssistantChat/Views/AssistantChatView.swift`, `ChatHomeView.swift`, `ChatSessionView.swift`.
2. Reuse the ViewModel and Services — they're platform-neutral.
3. Build `MacAssistantChatView`:
   ```swift
   import SwiftUI

   struct MacAssistantChatView: View {
       @State private var route: Route = .home
       enum Route: Hashable { case home, session(UUID) }

       var body: some View {
           NavigationStack(path: routePath) {
               MacChatHomeView(onStart: { id in route = .session(id) })
                   .navigationDestination(for: UUID.self) { id in
                       MacChatSessionView(sessionID: id)
                   }
           }
       }
   }
   ```
4. `MacChatSessionView`:
   - Reuses `AssistantChatViewModel`.
   - Composer: `TextEditor` with `.font(.body)`, fixed min height 60.
   - `.onSubmit` / `⌘Return` calls `vm.send`.
   - Tool banners: reuse `ToolCallBannerView` (extract from iOS chat if not already shared; if currently inlined, refactor to a shared component file under `Features/AssistantChat/Views/`).
5. Wire `MacContentPane`'s `.ask → MacAssistantChatView()`.

**Verification**
- [ ] Open Ask LEO from sidebar → chat home appears.
- [ ] New conversation → session view; type "what's on my plate today" → streamed response.
- [ ] Tool call (read items) banner appears.
- [ ] Propose tool (e.g. create a task) shows a "Propose" affordance that opens `MacDiffReviewPane` (MM5-T02).

**Notes / decisions**
_(empty)_

---

### MM5-T02 — `MacDiffReviewPane`
- **Status:** TODO
- **Depends on:** MM5-T01
- **Estimated effort:** L

**Goal**
When the AI proposes a Diff (`ItemChange`s), the user reviews them in the inspector column — not a modal sheet. They can accept/reject each change or the whole bundle. Resembles a PR diff review.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/AssistantChat/MacDiffReviewPane.swift` renders an array of `ItemChange`s.
- For each change: type badge (Add / Update / Delete), title, sub-changes (field-level diffs for Update), per-change Accept/Reject buttons.
- Bottom: "Accept all" + "Reject all".
- The pane replaces the normal `MacItemDetailInspector` when active; close button returns to normal inspector.
- Accept/Reject calls into `Diff.apply(_:via:)` (existing in `Domain/Diff/`).

**How to build it**
1. Read existing `Features/AssistantChat/Views/DiffReviewSheet.swift` for the visual reference and accept/reject logic.
2. Build `MacDiffReviewPane` as a non-modal view sharing the inspector slot.
3. Add a `diffInReview: Diff?` field to `MacNavigationModel`. When non-nil, the inspector renders `MacDiffReviewPane(diff:)`. When nil, renders `MacItemDetailInspector`.
4. From a chat tool-call, fire `nav.diffInReview = diff`. The pane is now in view.
5. Per-change Accept fires `Diff.apply(.init(changes: [change]), via: appEnv.itemRepository)`.
6. Accept all / Reject all clear `nav.diffInReview`.

**Verification**
- [ ] AI proposes 2 changes (one Add, one Update); diff pane shows both with field-level deltas.
- [ ] Accepting individual changes works; the underlying items reflect the change.
- [ ] Rejecting cancels without mutation.
- [ ] Close → inspector returns to normal mode.

**Notes / decisions**
_(empty)_

---

### MM5-T03 — `MacRecurrenceBuilderSheet`
- **Status:** TODO
- **Depends on:** MM3-T04
- **Estimated effort:** M

**Goal**
The recurrence builder UI from iOS works on Mac, opened from the inspector's "Edit recurrence" button.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/Recurrence/MacRecurrenceBuilderSheet.swift` is the Mac-styled sheet.
- Reuses `RecurrenceBuilderViewModel` unchanged.
- Layout: tabbed or segmented at top (Daily / Weekly / Monthly / Yearly / Custom), body adapts.
- Visual: same controls as iOS (interval stepper, weekday picker, end-condition picker).
- Preview text: "Every week on Mon, Tue…" via `RecurrenceFormatter`.
- Save: writes back `recurrenceRule` to the inspector's ViewModel; closes sheet.
- Cancel: discards.

**How to build it**
1. Read existing `Features/Recurrence/Views/RecurrenceBuilderView.swift` and ViewModel.
2. Port the layout. iOS uses `Form { Section { } }` which renders well on Mac.
3. Mount as a `.sheet` from `MacItemDetailInspector` on "Edit recurrence" tap.
4. Save behavior: on dismiss, if `vm.committed`, update inspector's item.

**Verification**
- [ ] Inspector "Edit recurrence" → sheet appears with current rule pre-selected.
- [ ] Change to "Every 2 weeks on Mon, Fri" → preview text updates.
- [ ] Save → inspector shows "↩ Every 2 weeks on Mon, Fri".
- [ ] Item's `rruleRaw` persists across relaunch (via SwiftData; verified by quitting + relaunching).

**Notes / decisions**
_(empty)_

---

### MM5-T04 — Voice input in chat
- **Status:** TODO
- **Depends on:** MM5-T01, MM4-T04
- **Estimated effort:** S

**Goal**
A mic button in the chat composer (same as MM4-T04 service) for voice prompts.

**What to build (acceptance criteria)**
- `MacChatSessionView` composer has a mic button.
- Behavior identical to MM4-T04: tap to record, auto-stop on silence, transcript fills composer.

**How to build it**
1. Reuse `MacVoiceCaptureService`.
2. Mount mic button in composer toolbar.

**Verification**
- [ ] Mic in chat works.
- [ ] Transcript fills composer; user can edit then send.

**Notes / decisions**
_(empty)_

---

### MM5-T05 — Assistant entry from command palette
- **Status:** TODO
- **Depends on:** MM5-T01, MM4-T05
- **Estimated effort:** S

**Goal**
Typing in the command palette and submitting a free-form sentence sends it directly to Ask LEO as a new conversation.

**What to build (acceptance criteria)**
- Command palette gets a synthetic top result "Ask LEO: \(query)" when query is ≥ 4 characters and no exact action matches.
- Selecting it: creates a new conversation, navigates to Ask LEO, sends the message.

**How to build it**
1. In `CommandPaletteViewModel.search(_:)`, prepend the synthetic command when the query is long enough and no exact match exists.
2. The command's `perform` closure: switch `nav.selection = .ask`, then post `.leoOpenAskWithMessage` carrying the query. The Mac chat view observes this notification and seeds a new session.

**Verification**
- [ ] `⌘K`, type "Plan my week" → palette shows "Ask LEO: Plan my week" as top result.
- [ ] Submit → switches to Ask LEO, conversation starts with that message.

**Notes / decisions**
_(empty)_
