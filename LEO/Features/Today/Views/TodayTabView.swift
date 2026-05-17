import SwiftUI

/// Today tab: the timeline + the pinned quick-add bar.
@MainActor
struct TodayTabView: View {
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                TodayView()
                    .navigationTitle("")
                    #if os(iOS)
                    .navigationBarHidden(true)
                    #endif

                QuickAddBar(repository: appEnv.itemRepository)
            }
        }
    }
}

#Preview {
    TodayTabView()
        .environment(AppEnvironment(useInMemory: true))
}
