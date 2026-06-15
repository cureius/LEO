import SwiftUI

/// Today tab: the timeline.
@MainActor
struct TodayTabView: View {
    var body: some View {
        NavigationStack {
            TodayView()
                .navigationTitle("")
                #if os(iOS)
                .navigationBarHidden(true)
                #endif
        }
    }
}

#Preview {
    TodayTabView()
        .environment(AppEnvironment(useInMemory: true))
}
