import SwiftUI

/// Today tab: the timeline + the pinned quick-add bar.
@MainActor
struct TodayTabView: View {
    @State private var refreshToken = UUID()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                TodayView()
                    .id(refreshToken)
                    .navigationTitle("")
                    .navigationBarHidden(true)

                QuickAddBar {
                    // Refresh Today when a new item is captured
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
