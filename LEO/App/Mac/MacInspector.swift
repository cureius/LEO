import SwiftUI

struct MacInspector: View {
    @Environment(MacNavigationModel.self) private var nav
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        MacItemDetailInspector()
            .frame(minWidth: 280, idealWidth: 320)
    }
}
