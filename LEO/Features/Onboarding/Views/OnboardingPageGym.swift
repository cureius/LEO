import SwiftUI
import HealthKit

/// Skippable gym companion onboarding page. Inserted between calendar step and completion.
struct OnboardingPageGym: View {
    let bodyProfileRepository: BodyProfileRepository
    let onDone: () -> Void

    @State private var showProfileForm = false
    @State private var profile: UserBodyProfile = UserBodyProfile()
    @State private var healthKitGranted = false
    @State private var isSaving = false
    @State private var hasSetupProfile = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 8)

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.Color.accent)

                Text("Gym Companion")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("LEO can generate personalized workout and meal plans, track your calories, and sync with Apple Health — all optional.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)

                // Quick stats card if profile was just set
                if hasSetupProfile {
                    let kcal = Int(BodyMath.dailyKcalTarget(profile: profile).dailyKcal)
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Color.success)
                            Text("Profile saved")
                                .font(Theme.Typography.body.bold())
                        }
                        Text("Daily calorie target: \(kcal) kcal")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .padding()
                    .background(Theme.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }

                // Set up profile button
                Button {
                    showProfileForm = true
                } label: {
                    HStack {
                        Image(systemName: hasSetupProfile ? "pencil.circle" : "person.fill")
                        Text(hasSetupProfile ? "Edit profile" : "Set up my profile")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)

                // HealthKit permission
                Button {
                    Task {
                        let store = HKHealthStore()
                        if HKHealthStore.isHealthDataAvailable() {
                            let types: Set<HKSampleType> = [HKObjectType.workoutType()]
                            try? await store.requestAuthorization(toShare: types, read: types)
                            healthKitGranted = true
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: healthKitGranted ? "heart.fill" : "heart")
                            .foregroundStyle(healthKitGranted ? .red : Theme.Color.accent)
                        Text(healthKitGranted ? "Apple Health connected" : "Connect Apple Health")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .disabled(healthKitGranted)

                Divider()

                VStack(spacing: 12) {
                    Button("Get started") { onDone() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)

                    Button("Skip for now") { onDone() }
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .padding(32)
        }
        .sheet(isPresented: $showProfileForm) {
            BodyProfileFormView(profile: profile) { saved in
                profile = saved
                Task {
                    do {
                        try await bodyProfileRepository.save(saved)
                        hasSetupProfile = true
                    } catch {}
                }
            }
        }
    }
}
