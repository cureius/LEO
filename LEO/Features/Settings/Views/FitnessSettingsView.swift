import SwiftUI

@MainActor
struct FitnessSettingsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var profile: UserBodyProfile?
    @State private var showProfileEdit = false
    @State private var unitPreference: UnitPreference = .metric
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    /// Prevents onChange from firing when loadProfile sets the unit picker programmatically.
    @State private var isLoadingProfile = true
    @State private var showGeneratePlan = false

    var body: some View {
        List {
            Section("Body profile") {
                if let p = profile {
                    profileSummary(p)
                } else {
                    Text("No profile set up yet.")
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Button("Edit profile") {
                    showProfileEdit = true
                }
            }

            Section("Units") {
                Picker("Display units", selection: $unitPreference) {
                    ForEach(UnitPreference.allCases, id: \.self) { u in
                        Text(u.displayName).tag(u)
                    }
                }
                .onChange(of: unitPreference) { _, new in
                    Task { await saveUnitPreference(new) }
                }
            }

            Section("Actions") {
                Button {
                    if profile != nil {
                        showGeneratePlan = true
                    } else {
                        errorMessage = "Set up your body profile first so we can pick the right calorie target and diet."
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Generate new plan")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .foregroundStyle(Theme.Color.textPrimary)
                }
            }

            Section {
                Text("LEO is not a medical device. Plans are general fitness guidance only. Consult a qualified healthcare professional for medical advice, especially if you have a medical condition.")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .navigationTitle("Fitness")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProfile() }
        .alert("Fitness", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showProfileEdit) {
            BodyProfileFormView(profile: profile ?? UserBodyProfile()) { updated in
                Task { await saveProfile(updated) }
            }
        }
        .sheet(isPresented: $showGeneratePlan) {
            GeneratePlanFlowView()
                .environment(appEnv)
        }
    }

    // MARK: - Profile summary

    private func profileSummary(_ p: UserBodyProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let kcal = Int(BodyMath.dailyKcalTarget(profile: p).dailyKcal)
            let bmi = BodyMath.bmi(weightKg: p.weightKg, heightCm: p.heightCm)
            LabeledContent("Weight", value: unitPreference == .metric ? "\(p.weightKg.formatted(.number.precision(.fractionLength(1)))) kg" : "\(p.weightLb.formatted(.number.precision(.fractionLength(1)))) lb")
            LabeledContent("BMI", value: bmi.formatted(.number.precision(.fractionLength(1))))
            LabeledContent("Daily target", value: "\(kcal) kcal")
            LabeledContent("Goal", value: p.goalPhysique.displayName)
            LabeledContent("Diet", value: p.dietType.displayName)
        }
    }

    // MARK: - Loaders

    private func loadProfile() async {
        isLoadingProfile = true
        profile = await appEnv.bodyProfileRepository.load()
        unitPreference = profile?.unitPreference ?? .metric
        isLoadingProfile = false
    }

    private func saveProfile(_ p: UserBodyProfile) async {
        do {
            try await appEnv.bodyProfileRepository.save(p)
            profile = p
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveUnitPreference(_ pref: UnitPreference) async {
        guard var p = profile else { return }
        p.unitPreference = pref
        await saveProfile(p)
    }
}

// MARK: - Body profile form

struct BodyProfileFormView: View {
    @State private var draft: UserBodyProfile
    let onSave: (UserBodyProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    init(profile: UserBodyProfile, onSave: @escaping (UserBodyProfile) -> Void) {
        _draft = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Body metrics") {
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("cm", value: $draft.heightCm, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("cm")
                    }
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("kg", value: $draft.weightKg, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kg")
                    }
                    Picker("Sex", selection: $draft.sex) {
                        ForEach(BiologicalSex.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    DatePicker("Date of birth", selection: $draft.birthDate, displayedComponents: .date)
                    HStack {
                        Text("Body fat %")
                        Spacer()
                        let binding = Binding<String>(
                            get: { draft.bodyFatPct.map { "\($0.formatted(.number.precision(.fractionLength(0))))" } ?? "" },
                            set: { draft.bodyFatPct = Double($0) }
                        )
                        TextField("optional", text: binding)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("%")
                    }
                    Picker("Activity level", selection: $draft.activityLevel) {
                        ForEach(ActivityLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }

                Section("Goals") {
                    Picker("Goal physique", selection: $draft.goalPhysique) {
                        ForEach(GoalPhysique.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    HStack {
                        Text("Goal weight")
                        Spacer()
                        let binding = Binding<String>(
                            get: { draft.goalWeightKg.map { "\($0.formatted(.number.precision(.fractionLength(1))))" } ?? "" },
                            set: { draft.goalWeightKg = Double($0) }
                        )
                        TextField("optional kg", text: binding)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }

                Section("Diet") {
                    Picker("Diet type", selection: $draft.dietType) {
                        ForEach(DietType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }

                Section("Medical flags (optional)") {
                    ForEach(MedicalFlag.allCases, id: \.self) { flag in
                        Toggle(flag.displayName, isOn: Binding(
                            get: { draft.medicalFlags.contains(flag) },
                            set: { on in
                                if on { draft.medicalFlags.append(flag) }
                                else { draft.medicalFlags.removeAll { $0 == flag } }
                            }
                        ))
                    }
                    Text("Medical flags are informational. LEO will note them in AI recommendations and suggest consulting a professional.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }

                Section("Units") {
                    Picker("Display units", selection: $draft.unitPreference) {
                        ForEach(UnitPreference.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(draft); dismiss() }
                }
            }
        }
    }
}
