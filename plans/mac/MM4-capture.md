# MM4 — Capture & Power Tools

**Goal:** Capture-from-anywhere on Mac. Toolbar quick-add inside the app, `MenuBarExtra` for capture without focusing LEO, a global hotkey for a floating capture window, and a command palette for fuzzy search over items and actions.

**Exit criteria:**
- User can capture an item without taking hands off the keyboard, regardless of which app is focused.
- Capture parses the same natural-language strings iOS parses (reuses `QuickAddParser`).
- `⌘K` from anywhere inside the app opens a fuzzy command palette.

## Summary checklist
- [ ] MM4-T01 — Toolbar quick-add field in `MacShellView`
- [ ] MM4-T02 — `MenuBarExtra` capture (status item)
- [ ] MM4-T03 — Global hotkey + floating capture window
- [ ] MM4-T04 — Voice capture (mic button in quick-add)
- [ ] MM4-T05 — Command palette (`⌘K`)
- [ ] MM4-T06 — Keyboard shortcuts audit

---

### MM4-T01 — Toolbar quick-add field
- **Status:** TODO
- **Depends on:** MM3-T01
- **Estimated effort:** M

**Goal**
A single-line text field pinned to the top of `MacTodayView` (and reachable from any pane via the toolbar) that accepts natural-language input and creates an item using the same parser pipeline as iOS.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Capture/MacQuickAddView.swift` — a compact view: text field, "Add" button, type-hint chip ("Task" by default, auto-detected from parse result).
- Submit on `Return` or "Add" button.
- Calls `QuickAddViewModel.submit(_:)` (reused — actor-isolated). On success, clears the field and posts `.leoDataDidChange`.
- Voice button (mic icon) — placeholder for MM4-T04.
- Receives notifications `.leoOpenQuickAdd` (from menu bar `⌘N`) and focuses the field.
- Submits trigger a tiny success animation (the new item flashes into Today's list).

**How to build it**
1. Read existing `LEO/Features/Capture/Views/QuickAddBar.swift` and `LEO/Features/Capture/ViewModels/QuickAddViewModel.swift`.
2. Build `MacQuickAddView` as a thin Mac shell over `QuickAddViewModel`:
   ```swift
   import SwiftUI

   struct MacQuickAddView: View {
       @Environment(AppEnvironment.self) private var appEnv
       @State private var input = ""
       @FocusState private var focused: Bool
       @State private var vm: QuickAddViewModel?

       var body: some View {
           HStack(spacing: 8) {
               Image(systemName: "plus.circle.fill")
                   .foregroundStyle(Theme.Color.accent)
               TextField("Capture a task, event, reminder…", text: $input)
                   .textFieldStyle(.plain)
                   .focused($focused)
                   .onSubmit(submit)
               if let preview = vm?.previewType {
                   LEOChip(text: preview, style: .neutral)
               }
               Button(action: submit) { Image(systemName: "arrow.right.circle.fill") }
                   .buttonStyle(.plain)
                   .disabled(input.isEmpty)
           }
           .padding(8)
           .background(Theme.Color.surface)
           .cornerRadius(8)
           .task { vm = QuickAddViewModel(itemRepository: appEnv.itemRepository) }
           .onReceive(NotificationCenter.default.publisher(for: .leoOpenQuickAdd)) { _ in
               focused = true
           }
       }

       private func submit() {
           guard let vm, !input.isEmpty else { return }
           Task {
               _ = try? await vm.submit(input)
               input = ""
               focused = true
           }
       }
   }
   ```
3. Wire `MacQuickAddView()` into Today/Inbox/Habits toolbars so it's always one tab-stop away.

**Verification**
- [ ] Type "Lunch with Joe tomorrow at 1pm" + Return → creates an EventItem on the right date.
- [ ] `⌘N` focuses the field from any pane.
- [ ] Voice mic shows as disabled placeholder.

**Notes / decisions**
_(empty)_

---

### MM4-T02 — `MenuBarExtra` capture
- **Status:** TODO
- **Depends on:** MM4-T01
- **Estimated effort:** M

**Goal**
A status-bar icon at the top of macOS that, when clicked, drops down a small popover with: next event, quick-capture field, "Open LEO" button.

**What to build (acceptance criteria)**
- `LEOMacApp.body` adds a `MenuBarExtra` scene.
- Status icon: `Image(systemName: "sun.max")` (or custom icon when designed).
- Popover content (≤ 320 wide, ≤ 360 tall) shows: "Next: \(item.title)" or "Nothing scheduled", a `MacQuickAddView`, and "Open LEO" button.
- The popover updates every 60 seconds and on `.leoDataDidChange`.
- The status icon shows a red dot if there's an active alarm.
- `MenuBarStatusProvidingMac` (replaces the stub) drives the popover state.

**How to build it**
1. Create `LEO/PlatformMac/Services/MenuBarStatusController.swift` — an `@Observable` class holding `nextItem`, `activeAlarm`. Driven by a Combine/AsyncStream loop that re-fetches every 60s.
2. Create `LEO/PlatformMac/Capture/MenuBarCaptureView.swift` — the popover body.
3. In `LEOMacApp.body`:
   ```swift
   MenuBarExtra {
       MenuBarCaptureView()
           .environment(menuBarController)
           .environment(appEnvironment!)
   } label: {
       Image(systemName: menuBarController.activeAlarm != nil ? "sun.max.fill" : "sun.max")
   }
   .menuBarExtraStyle(.window)
   ```
4. Create `MenuBarStatusProvidingMac` to satisfy the protocol from MM0-T04 (replace the stub in `AppEnvironment`).
5. Plumb `menuBarController` into `AppEnvironment` so other services can call `appEnv.menuBarStatus.updateNextItem(_:)`.

**Verification**
- [ ] Status icon appears in the menu bar.
- [ ] Clicking opens popover with next event.
- [ ] Capture from popover → item appears in LEO.
- [ ] "Open LEO" focuses the main window.
- [ ] Active alarm → icon dot visible.

**Notes / decisions**
_(empty)_

---

### MM4-T03 — Global hotkey + floating capture window
- **Status:** TODO
- **Depends on:** MM4-T02
- **Estimated effort:** L

**Goal**
A global keyboard shortcut (default `⌃⌥Space`) shows a centered, borderless capture window over any app. User types, hits Return, item is captured, window closes.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Services/GlobalHotkeyManager.swift` registers a global key monitor via `NSEvent.addGlobalMonitor(matching: .keyDown)`.
- Default combo: `⌃⌥Space`. Stored in `AppStorage("leo.globalHotkey")` as a serialized struct.
- On hotkey, present a borderless window (NSWindow level: `.floating`, `.fullScreenAuxiliary`) centered on the active screen.
- Window content: `FloatingCaptureWindow.swift` — same `MacQuickAddView`, bigger font, `Esc` closes, `Return` submits and closes.
- App must remain a regular Dock-icon app (LSUIElement off) — the floating window is separate from the main scene.
- Document collision risk: if `⌃⌥Space` is taken by Spotlight or another app, registration fails silently. Show a toast in Settings → General → Keyboard if so.

**How to build it**
1. Create `LEO/PlatformMac/Services/GlobalHotkeyManager.swift`:
   ```swift
   import AppKit
   import Combine

   @MainActor
   final class GlobalHotkeyManager: ObservableObject {
       private var monitor: Any?
       func start(handler: @escaping () -> Void) {
           // Note: NSEvent global monitor doesn't deliver key events unless Accessibility is granted.
           // For a true global hotkey, we use Carbon RegisterEventHotKey via a small Swift wrapper.
           // See implementation notes below.
           monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
               // Match ⌃⌥Space (keyCode 49 = space; modifierFlags contains .control + .option)
               if event.modifierFlags.contains([.control, .option]) && event.keyCode == 49 {
                   handler()
               }
           }
       }
       func stop() {
           if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
       }
   }
   ```
   **Implementation note:** the simplest `NSEvent` global monitor requires Accessibility permission. Two options:
   - **A.** Use `NSEvent.addGlobalMonitorForEvents` and prompt the user to grant Accessibility access. Document this prominently in onboarding (MM8) and Settings.
   - **B.** Use the Carbon `RegisterEventHotKey` API, which doesn't require Accessibility but is more work. Wrapper code is well-documented (search "Swift global hotkey Carbon").
   - Recommendation: ship A in v1 with a clear permission prompt; revisit B in v1.1 if friction is high. **Decision: A** unless user objects.
2. Create `LEO/PlatformMac/Capture/FloatingCaptureWindow.swift`:
   ```swift
   import SwiftUI
   import AppKit

   @MainActor
   final class FloatingCaptureWindowController {
       private var window: NSWindow?

       func toggle(with appEnv: AppEnvironment) {
           if window?.isVisible == true { window?.close(); window = nil; return }
           let view = FloatingCaptureContent()
               .environment(appEnv)
               .frame(width: 600, height: 80)
           let host = NSHostingController(rootView: view)
           let w = NSWindow(contentViewController: host)
           w.styleMask = [.borderless]
           w.level = .floating
           w.backgroundColor = .clear
           w.isOpaque = false
           w.center()
           w.makeKeyAndOrderFront(nil)
           NSApp.activate(ignoringOtherApps: true)
           window = w
       }
   }

   struct FloatingCaptureContent: View { /* fancy big TextField, escape closes */ }
   ```
3. In `LEOMacApp.body.task`, after `appEnvironment` is set, instantiate `GlobalHotkeyManager` and `FloatingCaptureWindowController`. Start the monitor; on fire, call `controller.toggle(with: env)`.
4. On first launch, after onboarding (MM8), show a sheet "Enable Quick Capture from anywhere" with a button that opens System Settings → Privacy & Security → Accessibility. Track via `UserDefaults.standard.bool(forKey: "leo.accessibilityPromptShown")`.

**Verification**
- [ ] After granting Accessibility, `⌃⌥Space` shows the floating capture from any app.
- [ ] Esc dismisses.
- [ ] Return submits + dismisses.
- [ ] Hotkey conflict toast appears if collision detected (best-effort).

**Notes / decisions**
_(empty)_

---

### MM4-T04 — Voice capture
- **Status:** TODO
- **Depends on:** MM4-T01
- **Estimated effort:** M

**Goal**
A mic button in `MacQuickAddView` records speech and transcribes via the macOS Speech framework, populating the text field.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Capture/MacVoiceCaptureService.swift` wraps `SFSpeechRecognizer` + `AVAudioEngine`.
- Mic button in quick-add starts recording; press again to stop or auto-stops on 1.5s of silence.
- Transcription populates the text field; user can edit before submit.
- Requires `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` (already in `Info-mac.plist` MM0-T02).
- Sandbox: microphone entitlement (`com.apple.security.device.microphone` = true) — add to entitlements if missing.

**How to build it**
1. Add microphone entitlement to `LEO-mac.entitlements`:
   ```xml
   <key>com.apple.security.device.microphone</key><true/>
   ```
2. Create `MacVoiceCaptureService.swift`:
   ```swift
   import Foundation
   import Speech
   import AVFoundation

   @MainActor
   final class MacVoiceCaptureService: NSObject, ObservableObject {
       @Published var transcript = ""
       private let speech = SFSpeechRecognizer(locale: .init(identifier: "en-US"))
       private let audio = AVAudioEngine()
       private var request: SFSpeechAudioBufferRecognitionRequest?
       private var task: SFSpeechRecognitionTask?

       func requestAuth() async -> Bool { /* SFSpeechRecognizer.requestAuthorization async wrapper */ }
       func start() async throws { /* hook audio.inputNode tap, feed request */ }
       func stop() { task?.cancel(); audio.stop() }
   }
   ```
3. Wire the mic button into `MacQuickAddView`. Tap to start; tap again or auto-stop after silence; populate `input` from `transcript`.

**Verification**
- [ ] First click prompts for mic + speech recognition permission.
- [ ] Voice → transcript appears in field within ~1s of speaking.
- [ ] Submit creates item with the parsed text.

**Notes / decisions**
_(empty)_

---

### MM4-T05 — Command palette (`⌘K`)
- **Status:** TODO
- **Depends on:** MM4-T04
- **Estimated effort:** L

**Goal**
A fuzzy command palette accessible from anywhere in the app, listing: items (by title), navigation targets (sidebar sections), and quick actions (toggle inspector, switch to timeline mode, etc.).

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Commands/CommandPaletteView.swift` — a sheet over the main window, ⌘K opens, Esc closes.
- Top: search field; below: scrollable result list with sections "Actions", "Items", "Navigate".
- Fuzzy search uses a simple subsequence match scorer (no external dep).
- Selected result fires the action: navigate to section, open item in inspector, run action.
- The sheet has a max width of 700 and grows up to 60% of main window height.

**How to build it**
1. Create `CommandPaletteCommand` model:
   ```swift
   struct CommandPaletteCommand: Identifiable, Hashable {
       enum Kind { case action, item, navigate }
       let id: String
       let kind: Kind
       let title: String
       let subtitle: String?
       let icon: String
       let perform: () -> Void
   }
   ```
2. `CommandPaletteSource.swift` — assembles the command list:
   - Static actions (Toggle Inspector, Switch to List view, Switch to Timeline view, Open Settings, etc.)
   - Dynamic items: `appEnv.itemRepository.fetch(.all).prefix(200).map { ... }`
   - Dynamic navigates: `SidebarSection.allCases.map { ... }`
3. `CommandPaletteViewModel` — search + filter.
4. `CommandPaletteView` — UI:
   ```swift
   struct CommandPaletteView: View {
       @Binding var isPresented: Bool
       @State private var query = ""
       @State private var selected: CommandPaletteCommand.ID?
       @State private var results: [CommandPaletteCommand] = []
       /* TextField + List + .onSubmit + arrow-key navigation */
   }
   ```
5. Mount the sheet on `MacShellView`. Listen for `.leoOpenCommandPalette` to set `isPresented = true`. Also `⌘K` directly on the shell via `.keyboardShortcut`.

**Verification**
- [ ] `⌘K` opens palette from any pane.
- [ ] Typing "tom" filters to titles containing "tom".
- [ ] Arrow keys navigate, Return fires the selected command.
- [ ] Esc dismisses.

**Notes / decisions**
_(empty)_

---

### MM4-T06 — Keyboard shortcuts audit
- **Status:** TODO
- **Depends on:** MM4-T05
- **Estimated effort:** S

**Goal**
Sweep through every primary interaction in the Mac app and confirm there's a keyboard shortcut. Documented in Settings → General → Keyboard.

**What to build (acceptance criteria)**
- A `MacKeyboardShortcuts.swift` reference file enumerates every shortcut.
- Settings → General → Keyboard tab shows the same list (read-only in v1; customization is v1.1).
- No conflicts within the app (two shortcuts mapping to the same combo).
- Every shortcut is reachable by mouse path too (menu bar item, button, context menu).

**How to build it**
1. Create `LEO/PlatformMac/Commands/MacKeyboardShortcuts.swift`:
   ```swift
   struct MacKeyboardShortcut: Hashable {
       let label: String
       let combo: String  // human-readable, e.g. "⌘N"
       let menuPath: String  // e.g. "File ▸ New Item…"
   }

   enum MacKeyboardShortcuts {
       static let all: [MacKeyboardShortcut] = [
           .init(label: "New item",      combo: "⌘N",   menuPath: "File ▸ New Item…"),
           .init(label: "Quick Capture (global)", combo: "⌃⌥Space", menuPath: "—"),
           .init(label: "Command palette", combo: "⌘K", menuPath: "Edit ▸ Find"),
           // …
       ]
   }
   ```
2. Build a `MacKeyboardSettingsPane` view (deferred presentation to MM8 Settings).
3. Run an audit: open every menu, list every shortcut, cross-check against the array.

**Verification**
- [ ] Every menu-bar shortcut is in `MacKeyboardShortcuts.all`.
- [ ] No duplicate shortcuts.
- [ ] Settings → Keyboard tab (MM8) reads the list.

**Notes / decisions**
_(empty)_
