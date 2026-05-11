import SwiftUI

@MainActor
struct FitnessSettingsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var profile: UserBodyProfile?
    @State private var showProfileEdit = false
    @State private var unitPreference: UnitPreference = .metric
    @State private var healthKitEnabled = false
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    /// Prevents onChange from firing when loadProfile sets the toggle programmatically.
    @State private var isLoadingProfile = true
    @State private var isRequestingHK = false
    /// Set to true when we know HealthKit can't be used in this build (entitlement missing).
    @State private var hkBlockedReason: String? = nil

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

            Section("HealthKit") {
                if !appEnv.healthKitBridge.isAvailable {
                    Label("Apple Health not available on this device", systemImage: "heart.slash")
                        .foregroundStyle(Theme.Color.textSecondary)
                        .font(.caption)
                } else if let blocked = hkBlockedReason {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Apple Health unavailable", systemImage: "heart.slash")
                            .font(.callout)
                        Text(blocked)
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                } else {
                    HStack {
                        Toggle("Sync with Apple Health", isOn: $healthKitEnabled)
                            .disabled(isRequestingHK)
                            .onChange(of: healthKitEnabled) { _, enabled in
                                // Skip when loadProfile sets the toggle programmatically
                                guard !isLoadingProfile else { return }
                                if enabled {
                                    Task { await requestHealthKitAccess() }
                                }
                            }
                        if isRequestingHK {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                Text("When enabled, LEO writes completed workouts and meals to Apple Health and reads your weight automatically.")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Section("Actions") {
                NavigationLink("Generate new plan") {
                    generatePlanView
                }
                Button("View measurements chart") {
                    // Navigate via parent
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
        .alert("Health Access", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showProfileEdit) {
            BodyProfileFormView(profile: profile ?? UserBodyProfile()) { updated in
                Task { await saveProfile(updated) }
            }
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

    // MARK: - Generate plan view (stub entry point)

    private var generatePlanView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(Theme.Color.accent)
            Text("Generate a fitness plan")
                .font(.title2.bold())
            Text("Go to Ask LEO and say:\n\"Generate a 4-week workout and meal plan\"")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .navigationTitle("Generate plan")
    }

    // MARK: - Loaders

    private func loadProfile() async {
        isLoadingProfile = true
        profile = await appEnv.bodyProfileRepository.load()
        unitPreference = profile?.unitPreference ?? .metric
        if appEnv.healthKitBridge.isAvailable {
            let status = await appEnv.healthKitBridge.authorizationStatus()
            healthKitEnabled = (status == .sharingAuthorized)
        }
        isLoadingProfile = false
    }

    private func requestHealthKitAccess() async {
        isRequestingHK = true
        defer { isRequestingHK = false }

        let outcome = await appEnv.healthKitBridge.requestAccess()

        // For .granted, verify with a follow-up status query so the toggle reflects
        // what HK actually returned (the user may have denied in the system sheet).
        var trulyGranted = false
        if case .granted = outcome {
            let status = await appEnv.healthKitBridge.authorizationStatus()
            trulyGranted = (status == .sharingAuthorized)
        }

        // Always sync the toggle back to ground truth — never leave it stuck on.
        isLoadingProfile = true
        healthKitEnabled = trulyGranted
        isLoadingProfile = false

        switch outcome {
        case .granted where trulyGranted:
            break  // success — nothing to show
        case .granted:
            // System sheet returned success but no permissions actually granted
            errorMessage = "Apple Health didn't grant any permissions. Open iOS Settings → Privacy & Security → Health → LEO to enable the categories you want to sync."
        case .denied:
            errorMessage = "HealthKit access was denied. You can change this in iOS Settings → Privacy & Security → Health → LEO."
        case .unavailable:
            errorMessage = "HealthKit is not available on this device."
        case .entitlementMissing:
            hkBlockedReason = "This build of LEO is signed without the HealthKit capability. Reinstall a Release build or add the HealthKit capability in Xcode → Signing & Capabilities."
        case .timedOut:
            hkBlockedReason = "Apple Health didn't respond in 5 seconds. This usually means LEO is missing the HealthKit capability. Add it in Xcode → Signing & Capabilities and reinstall."
        case .error(let msg):
            errorMessage = "Apple Health error: \(msg)"
        }
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
