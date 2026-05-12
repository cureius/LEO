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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $vm.title)
                        .font(Theme.Typography.headline)
                }

                Section("Description") {
                    MarkdownTextEditor(
                        text: $vm.notes,
                        placeholder: "Notes, links, or formatting…",
                        dynamicHeight: $notesEditorHeight
                    )
                    .frame(height: notesEditorHeight)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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

    enum AnchorMode: String, CaseIterable { case untimed, dueAt, timeBlock, point }
    @State private var mode: AnchorMode = .untimed

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Picker("Time type", selection: $mode) {
                Text("Inbox").tag(AnchorMode.untimed)
                Text("Due by").tag(AnchorMode.dueAt)
                Text("Time block").tag(AnchorMode.timeBlock)
                Text("Reminder").tag(AnchorMode.point)
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in applyMode() }

            switch mode {
            case .untimed: EmptyView()
            case .dueAt:
                DatePicker("Due date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: dueDate) { _, v in anchor = .dueAt(v) }
            case .timeBlock:
                DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: startDate) { _, _ in applyMode() }
                DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: endDate) { _, _ in applyMode() }
            case .point:
                DatePicker("Time", selection: $pointDate, displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: pointDate) { _, v in anchor = .point(v) }
            }
        }
        .onAppear { syncFromAnchor() }
    }

    private func syncFromAnchor() {
        switch anchor {
        case .untimed:          mode = .untimed
        case .dueAt(let d):     mode = .dueAt;      dueDate = d
        case .timeBlock(let s, let e): mode = .timeBlock; startDate = s; endDate = e
        case .point(let d):     mode = .point;      pointDate = d
        default:                mode = .untimed
        }
    }

    private func applyMode() {
        switch mode {
        case .untimed:   anchor = .untimed
        case .dueAt:     anchor = .dueAt(dueDate)
        case .timeBlock: anchor = .timeBlock(start: startDate, end: max(endDate, startDate.addingTimeInterval(900)))
        case .point:     anchor = .point(pointDate)
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
