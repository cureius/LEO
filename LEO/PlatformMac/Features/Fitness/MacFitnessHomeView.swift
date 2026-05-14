import SwiftUI

/// Mac Gym Companion home. Wraps the shared FitnessHomeView.
@MainActor
struct MacFitnessHomeView: View {
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        FitnessHomeView()
    }
}
