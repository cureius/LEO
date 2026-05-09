import SwiftUI

/// Visual recurrence rule builder with natural-language input, frequency/interval pickers,
/// weekday grid, end-condition selector, and a live next-5-occurrences preview.
@MainActor
struct RecurrenceBuilderView: View {
    @Bindable var vm: RecurrenceBuilderViewModel
    /// Called with the final RecurrenceRule when the user taps Done.
    var onDone: ((RecurrenceRule) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                nlSection
                frequencySection
                endConditionSection
                extensionsSection
                previewSection
            }
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone?(vm.recurrenceRule)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Natural language

    private var nlSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                TextField("e.g. every other Tuesday", text: $vm.nlInput)
                    .textInputAutocapitalization(.never)
                    .onSubmit { vm.applyNLInput() }
                if !vm.summaryText.isEmpty {
                    Text(vm.summaryText)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        } header: {
            Text("Natural language")
        }
    }

    // MARK: - Frequency + interval + weekdays

    private var frequencySection: some View {
        Section("Repeat") {
            Picker("Frequency", selection: $vm.frequency) {
                Text("Daily").tag(RRuleFrequency.daily)
                Text("Weekly").tag(RRuleFrequency.weekly)
                Text("Monthly").tag(RRuleFrequency.monthly)
                Text("Yearly").tag(RRuleFrequency.yearly)
            }
            .pickerStyle(.segmented)

            Stepper("Every \(vm.interval) \(frequencyUnit)", value: $vm.interval, in: 1...99)

            if vm.frequency == .weekly {
                weekdayGrid
            }
        }
    }

    private var weekdayGrid: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { wd in
                let selected = vm.selectedWeekdays.contains(wd)
                Button {
                    if selected { vm.selectedWeekdays.remove(wd) }
                    else        { vm.selectedWeekdays.insert(wd) }
                } label: {
                    Text(wd.displayName.prefix(1))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(selected ? Theme.Color.accent : Theme.Color.surface)
                        .foregroundStyle(selected ? .white : Theme.Color.textPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - End condition

    private var endConditionSection: some View {
        Section("Ends") {
            Picker("", selection: $vm.endCondition) {
                Text("Never").tag(RecurrenceBuilderViewModel.EndCondition.never)
                Text("After").tag(RecurrenceBuilderViewModel.EndCondition.afterCount)
                Text("On date").tag(RecurrenceBuilderViewModel.EndCondition.onDate)
            }
            .pickerStyle(.segmented)

            switch vm.endCondition {
            case .never:
                EmptyView()
            case .afterCount:
                Stepper("\(vm.count) occurrence\(vm.count == 1 ? "" : "s")",
                        value: $vm.count, in: 1...999)
            case .onDate:
                DatePicker("End date", selection: $vm.until, displayedComponents: .date)
            }
        }
    }

    // MARK: - LEO extensions

    private var extensionsSection: some View {
        Section("Smart scheduling") {
            ForEach(LEORuleExtension.allCases, id: \.self) { ext in
                Toggle(ext.displayName, isOn: Binding(
                    get: { vm.extensionsEnabled[ext] ?? false },
                    set: { vm.extensionsEnabled[ext] = $0 }
                ))
            }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section("Next occurrences") {
            if vm.nextOccurrences.isEmpty {
                Text("No upcoming occurrences in the next year.")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                ForEach(vm.nextOccurrences, id: \.self) { date in
                    Text(date, style: .date) + Text(" ") + Text(date, style: .time)
                }
            }
        }
        .task(id: vm.rule.rfc5545) {
            await vm.refreshOccurrences()
        }
    }

    // MARK: - Helpers

    private var frequencyUnit: String {
        let plural = vm.interval != 1
        switch vm.frequency {
        case .daily:   return plural ? "days" : "day"
        case .weekly:  return plural ? "weeks" : "week"
        case .monthly: return plural ? "months" : "month"
        case .yearly:  return plural ? "years" : "year"
        }
    }
}

// MARK: - LEORuleExtension display

extension LEORuleExtension {
    var displayName: String {
        switch self {
        case .workdaysOnly:        return "Weekdays only"
        case .skipUSHolidays:      return "Skip US federal holidays"
        case .firstWeekdayOfMonth: return "Move to first weekday if on weekend"
        }
    }
}

// MARK: - Preview

#Preview {
    struct Wrapper: View {
        @State private var vm: RecurrenceBuilderViewModel
        init() { _vm = State(wrappedValue: RecurrenceBuilderViewModel()) }
        var body: some View {
            RecurrenceBuilderView(vm: vm)
        }
    }
    return Wrapper()
}
