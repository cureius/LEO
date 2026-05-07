import SwiftUI

@MainActor
struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var showDebugMenu = false

    var body: some View {
        AppTabView()
            #if DEBUG
            .onShake { showDebugMenu = true }
            .sheet(isPresented: $showDebugMenu) { DebugMenu() }
            #endif
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment(useInMemory: true))
}
