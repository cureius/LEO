import SwiftUI

/// Today tab: the timeline + the pinned quick-add bar.
@MainActor
struct TodayTabView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var refreshToken = UUID()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                TodayView()
                    .id(refreshToken)
                    .navigationTitle("")
                    .navigationBarHidden(true)

                QuickAddBar(repository: appEnv.itemRepository) {
                    refreshToken = UUID()
                }
            }
        }
    }
}

#Preview {
    TodayTabView()
        .environment(AppEnvironment(useInMemory: true))
}
