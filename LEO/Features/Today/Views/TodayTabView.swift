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
                    #if os(iOS)
                    .navigationBarHidden(true)
                    #endif

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
