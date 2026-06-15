import SwiftUI
import UIKit

@MainActor
struct ItemDetailSheet: View {
    let item: (any Item)?
    let onSave: (any Item) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: ItemDetailViewModel? = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                ItemDetailFormView(vm: vm, onSave: onSave, onDelete: onDelete)
            } else {
                ProgressView()
                    .onAppear { viewModel = ItemDetailViewModel(item: item, repository: appEnv.itemRepository) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Form using @Bindable

@MainActor
private struct ItemDetailFormView: View {
    @Bindable var vm: ItemDetailViewModel
    let onSave: (any Item) -> Void
    var onDelete: (() -> Void)?

    @State private var showDeleteConfirm = false
    @State private var showRecurrenceBuilder = false
    @State private var recurrenceBuilderVM: RecurrenceBuilderViewModel = RecurrenceBuilderViewModel()
    @State private var notesEditorHeight: CGFloat = MarkdownTextEditor.minHeight
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $vm.title)
                        .font(Theme.Typography.headline)
                }

                if let url = MeetingLinkDetector.detect(notes: vm.notes, location: vm.location, title: vm.title) {
                    Section {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Join \(MeetingLinkDetector.provider(for: url))", systemImage: "video.fill")
                                .frame(maxWidth: .infinity)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .listRowBackground(Theme.Color.accent)
                        .foregroundStyle(.white)
                    }
                }

                if vm.originalItem is EventItem {
                    // Synced invite notes — cleaned, read-only (Apple Calendar style).
                    let clean = EventNotes.cleaned(vm.notes)
                    if !clean.isEmpty {
                        Section("Notes") {
                            Text(clean)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.Color.textPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Section("Description") {
                        MarkdownTextEditor(
                            text: $vm.notes,
                            placeholder: "Notes, links, or formatting…",
                            dynamicHeight: $notesEditorHeight
                        )
                        .frame(height: notesEditorHeight)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section("Time") {
                    AnchorPicker(anchor: $vm.anchor)
                }

                Section("Priority") {
                    Picker("Importance", selection: $vm.importance) {
                        ForEach(Importance.allCases, id: \.self) { imp in
                            Label(imp.displayName, systemImage: imp.systemImage).tag(imp)
                        }
                    }
                    .pickerStyle(.menu)
                }

                recurrenceSection

                typeSpecificSection

                if vm.originalItem != nil {
                    Section {
                        Button("Delete", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(vm.originalItem == nil ? "New Item" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await vm.save() {
                                if let item = vm.originalItem { onSave(item) }
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSaving)
                }
            }
            .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await vm.delete() {
                            onDelete?()
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showRecurrenceBuilder) {
                RecurrenceBuilderView(vm: recurrenceBuilderVM) { rule in
                    vm.recurrenceRule = rule
                }
            }
        }
    }

    @ViewBuilder
    private var recurrenceSection: some View {
        Section("Repeat") {
            Button {
                recurrenceBuilderVM.anchorStart = (vm.anchor.sortDate ?? .now)
                if let rule = vm.recurrenceRule, let parsed = try? rule.parsed() {
                    recurrenceBuilderVM.apply(parsed)
                }
                showRecurrenceBuilder = true
            } label: {
                HStack {
                    Text(vm.recurrenceRule.map { RecurrenceFormatter.summary(for: (try? $0.parsed()) ?? RRule(frequency: .daily)) } ?? "Never")
                        .foregroundStyle(vm.recurrenceRule != nil ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if vm.recurrenceRule != nil {
                Button("Remove repeat", role: .destructive) {
                    vm.recurrenceRule = nil
                }
            }
        }
    }

    @ViewBuilder
    private var typeSpecificSection: some View {
        if vm.originalItem is AlarmItem {
            Section("Alarm") {
                Picker("Sound", selection: $vm.soundProfile) {
                    ForEach(AlarmSound.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Escalate volume", isOn: $vm.escalates)
            }
        } else if vm.originalItem is ReminderItem {
            Section("Reminder") {
                Stepper("Lead time: \(vm.leadTimeMinutes) min",
                        value: $vm.leadTimeMinutes, in: 0...120, step: 5)
            }
        } else if vm.originalItem is EventItem {
            Section("Event") {
                TextField("Location", text: $vm.location)
            }
        } else {
            Section("Task") {
                Toggle("Has deadline", isOn: Binding(
                    get: { vm.deadline != nil },
                    set: { vm.deadline = $0 ? Date.now.addingTimeInterval(86400) : nil }
                ))
                if vm.deadline != nil {
                    DatePicker("Deadline", selection: Binding(
                        get: { vm.deadline ?? Date.now.addingTimeInterval(86400) },
                        set: { vm.deadline = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                }
            }
        }
    }
}

// MARK: - Anchor picker

private struct AnchorPicker: View {
    @Binding var anchor: Anchor

    @State private var startDate: Date = .now
    @State private var endDate: Date = .now.addingTimeInterval(3600)
    @State private var pointDate: Date = .now
    @State private var dueDate: Date = .now.addingTimeInterval(86400)
    @State private var allDayDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var allDayEndDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var isMultiDay: Bool = false
    // Toggles All-day mode when "Time block" is selected
    @State private var isAllDay: Bool = false

    enum AnchorMode: String, CaseIterable { case untimed, dueAt, timeBlock, point }
    @State private var mode: AnchorMode = .untimed

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Mode selector — icon chips
            HStack(spacing: 6) {
                ForEach(AnchorMode.allCases, id: \.self) { m in
                    modeChip(m)
                }
            }
            .sensoryFeedback(.selection, trigger: mode)

            // Contextual pickers
            Group {
                switch mode {
                case .untimed:
                    Label("Stays in your Inbox until you give it a time.", systemImage: "tray")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .padding(.vertical, 2)

                case .dueAt:
                    pickerRow("Due", icon: "flag.fill") {
                        DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .onChange(of: dueDate) { _, v in anchor = .dueAt(v) }
                    }

                case .timeBlock:
                    toggleRow("All day", icon: "sun.max.fill", isOn: $isAllDay)
                        .onChange(of: isAllDay) { _, _ in applyMode() }

                    if isAllDay {
                        pickerRow("Date", icon: "calendar") {
                            DatePicker("", selection: $allDayDate, displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: allDayDate) { _, _ in applyMode() }
                        }
                        toggleRow("Multi-day", icon: "calendar.badge.plus", isOn: $isMultiDay)
                            .onChange(of: isMultiDay) { _, _ in applyMode() }
                        if isMultiDay {
                            pickerRow("End", icon: "calendar") {
                                DatePicker("", selection: $allDayEndDate, in: allDayDate..., displayedComponents: .date)
                                    .labelsHidden()
                                    .onChange(of: allDayEndDate) { _, _ in applyMode() }
                            }
                        }
                    } else {
                        pickerRow("Starts", icon: "play.fill") {
                            DatePicker("", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .onChange(of: startDate) { _, _ in applyMode() }
                        }
                        pickerRow("Ends", icon: "stop.fill") {
                            DatePicker("", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .onChange(of: endDate) { _, _ in applyMode() }
                        }
                    }

                case .point:
                    pickerRow("Remind at", icon: "bell.fill") {
                        DatePicker("", selection: $pointDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .onChange(of: pointDate) { _, v in anchor = .point(v) }
                    }
                }
            }
            .tint(Theme.Color.accent)
        }
        .onAppear { syncFromAnchor() }
    }

    // MARK: - Modern picker building blocks

    private func modeChip(_ m: AnchorMode) -> some View {
        let selected = mode == m
        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) { mode = m }
            applyMode()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon(for: m))
                    .font(.system(size: 15, weight: .semibold))
                Text(title(for: m))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? Color.white : Theme.Color.textSecondary)
            .background {
                if selected {
                    LinearGradient(
                        colors: [Theme.Color.accent, Theme.Color.accent.opacity(0.8)],
                        startPoint: .top, endPoint: .bottom
                    )
                } else {
                    Theme.Color.surface
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Theme.Color.divider, lineWidth: 1)
            )
            .shadow(color: selected ? Theme.Color.accent.opacity(0.3) : .clear, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func pickerRow<Content: View>(
        _ label: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toggleRow(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .tint(Theme.Color.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func title(for m: AnchorMode) -> String {
        switch m {
        case .untimed:   return "Inbox"
        case .dueAt:     return "Due by"
        case .timeBlock: return "Event"
        case .point:     return "Reminder"
        }
    }

    private func icon(for m: AnchorMode) -> String {
        switch m {
        case .untimed:   return "tray"
        case .dueAt:     return "flag.fill"
        case .timeBlock: return "calendar"
        case .point:     return "bell.fill"
        }
    }

    private func syncFromAnchor() {
        switch anchor {
        case .untimed:
            mode = .untimed
        case .dueAt(let d):
            mode = .dueAt; dueDate = d
        case .timeBlock(let s, let e):
            mode = .timeBlock
            if anchor.isAllDayBlock {
                isAllDay = true
                allDayDate = s
                let cal = Calendar.current
                let endH = cal.component(.hour,   from: e)
                let endM = cal.component(.minute, from: e)
                // Determine the last calendar day of the event:
                //   - midnight end (00:00) → last day is the day BEFORE end
                //   - 23:59 end           → last day is the day CONTAINING end
                let lastDay: Date = (endH == 0 && endM == 0)
                    ? (cal.date(byAdding: .day, value: -1, to: e) ?? e)
                    : cal.startOfDay(for: e)
                if !cal.isDate(s, inSameDayAs: lastDay) {
                    isMultiDay = true
                    allDayEndDate = lastDay
                } else {
                    isMultiDay = false
                    allDayEndDate = s
                }
            } else {
                isAllDay = false
                startDate = s; endDate = e
            }
        case .point(let d):
            mode = .point; pointDate = d
        default:
            mode = .untimed
        }
    }

    private func applyMode() {
        let cal = Calendar.current
        switch mode {
        case .untimed:
            anchor = .untimed
        case .dueAt:
            anchor = .dueAt(dueDate)
        case .timeBlock:
            if isAllDay {
                let start = cal.startOfDay(for: allDayDate)
                let endDay = isMultiDay ? allDayEndDate : allDayDate
                let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endDay)) ?? start.addingTimeInterval(86400)
                anchor = .timeBlock(start: start, end: end)
            } else {
                anchor = .timeBlock(start: startDate, end: max(endDate, startDate.addingTimeInterval(900)))
            }
        case .point:
            anchor = .point(pointDate)
        }
    }
}

// MARK: - Markdown text editor

/// Multiline UITextView-backed editor with a markdown formatting toolbar.
/// Grows dynamically with content. Stores text as a plain markdown string.
struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Add notes…"
    @Binding var dynamicHeight: CGFloat

    static let minHeight: CGFloat = 80

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $dynamicHeight,
                    placeholder: placeholder, minHeight: Self.minHeight)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.font = .systemFont(ofSize: 15)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.inputAccessoryView = context.coordinator.makeToolbar()
        context.coordinator.textView = tv

        if text.isEmpty {
            tv.text = placeholder
            tv.textColor = .placeholderText
        } else {
            tv.text = text
            tv.textColor = .label
        }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // Sync text when changed externally (not by the user typing)
        if tv.textColor != .placeholderText, tv.text != text {
            tv.text = text
        }
        // Always schedule a height recalc after the current layout pass.
        // This handles initial load with existing notes (makeUIView sets text
        // before frame.width is known, so we must defer until layout is done).
        DispatchQueue.main.async {
            context.coordinator.recalcHeight(tv)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var height: CGFloat
        let placeholder: String
        let minHeight: CGFloat
        weak var textView: UITextView?

        init(text: Binding<String>, height: Binding<CGFloat>,
             placeholder: String, minHeight: CGFloat) {
            _text = text
            _height = height
            self.placeholder = placeholder
            self.minHeight = minHeight
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            if tv.textColor == .placeholderText {
                tv.text = nil
                tv.textColor = .label
            }
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if tv.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tv.text = placeholder
                tv.textColor = .placeholderText
                text = ""
            }
        }

        func textViewDidChange(_ tv: UITextView) {
            guard tv.textColor != .placeholderText else { return }
            text = tv.text
            recalcHeight(tv)
        }

        func recalcHeight(_ tv: UITextView) {
            // Use actual width once laid out; fall back to screen-minus-padding estimate.
            let w = tv.frame.width > 0 ? tv.frame.width : UIScreen.main.bounds.width - 64
            let h = max(minHeight, ceil(tv.sizeThatFits(CGSize(width: w, height: .infinity)).height))
            // Guard with a 1pt tolerance to avoid triggering redundant SwiftUI redraws.
            guard abs(h - height) > 1 else { return }
            height = h  // callers (textViewDidChange, updateUIView's async block) are on main
        }

        // MARK: Toolbar

        func makeToolbar() -> UIToolbar {
            let bar = UIToolbar()
            bar.sizeToFit()

            func icon(_ name: String, action: @escaping () -> Void) -> UIBarButtonItem {
                UIBarButtonItem(image: UIImage(systemName: name),
                                primaryAction: UIAction { [weak self] _ in
                                    guard self != nil else { return }
                                    action()
                                })
            }
            func label(_ title: String, bold: Bool = false, action: @escaping () -> Void) -> UIBarButtonItem {
                let btn = UIBarButtonItem(title: title,
                                         primaryAction: UIAction { [weak self] _ in
                                             guard self != nil else { return }
                                             action()
                                         })
                btn.setTitleTextAttributes(
                    [.font: bold ? UIFont.boldSystemFont(ofSize: 15) : UIFont.systemFont(ofSize: 15)],
                    for: .normal)
                return btn
            }
            let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let done  = UIBarButtonItem(systemItem: .done,
                                        primaryAction: UIAction { [weak self] _ in
                                            self?.textView?.resignFirstResponder()
                                        })
            bar.items = [
                label("B", bold: true) { [weak self] in self?.inline("**") },
                label("I")             { [weak self] in self?.inline("_") },
                icon("strikethrough")  { [weak self] in self?.inline("~~") },
                icon("list.bullet")    { [weak self] in self?.linePrefix("- ") },
                label("H", bold: true) { [weak self] in self?.linePrefix("## ") },
                space, done
            ]
            return bar
        }

        // MARK: Formatting

        private func inline(_ marker: String) {
            guard let tv = textView, let sel = tv.selectedTextRange else { return }
            let selected = tv.text(in: sel) ?? ""
            if selected.isEmpty {
                tv.replace(sel, withText: "\(marker)\(marker)")
                if let mid = tv.position(from: sel.start, offset: marker.count) {
                    tv.selectedTextRange = tv.textRange(from: mid, to: mid)
                }
            } else {
                tv.replace(sel, withText: "\(marker)\(selected)\(marker)")
            }
            text = tv.text
            recalcHeight(tv)
        }

        private func linePrefix(_ prefix: String) {
            guard let tv = textView, let cursor = tv.selectedTextRange else { return }
            let nsText = tv.text as NSString
            let offset = tv.offset(from: tv.beginningOfDocument, to: cursor.start)
            let lineRange = nsText.lineRange(for: NSRange(location: offset, length: 0))
            guard let start = tv.position(from: tv.beginningOfDocument, offset: lineRange.location),
                  let insert = tv.textRange(from: start, to: start) else { return }
            tv.replace(insert, withText: prefix)
            text = tv.text
            recalcHeight(tv)
        }
    }
}

#Preview {
    ItemDetailSheet(
        item: TaskItem(title: "Draft Q3 report", anchor: .dueAt(.now.addingTimeInterval(86400))),
        onSave: { _ in }
    )
    .environment(AppEnvironment(useInMemory: true))
}
