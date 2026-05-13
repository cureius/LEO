import SwiftUI

struct MacShellView: View {
    @Environment(MacNavigationModel.self) private var nav
    @SceneStorage("leo.sidebar.section") private var sectionRaw: String = SidebarSection.today.rawValue
    @AppStorage("leo.inspector.visible") private var inspectorVisible: Bool = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var navBinding = nav
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebar()
        } content: {
            MacContentPane()
                .frame(minWidth: 400, idealWidth: 600)
        } detail: {
            MacInspector()
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if let restored = SidebarSection(rawValue: sectionRaw) {
                nav.selection = restored
            }
            columnVisibility = inspectorVisible ? .all : .doubleColumn
        }
        .onChange(of: nav.selection) { _, new in sectionRaw = new.rawValue }
        .onChange(of: nav.inspectorVisible) { _, visible in
            inspectorVisible = visible
            columnVisibility = visible ? .all : .doubleColumn
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoSelectSidebarSection)) { note in
            if let section = note.object as? SidebarSection { nav.selection = section }
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoToggleInspector)) { _ in
            nav.inspectorVisible.toggle()
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .leoOpenDebugMenu)) { _ in
            openDebugMenu()
        }
        #endif
    }

    private func openDebugMenu() {
        // Debug menu in a sheet — MM9-T04 wires the keyboard shortcut
    }
}

// MARK: - Notification names (Mac-specific)

extension Notification.Name {
    static let leoSelectSidebarSection  = Notification.Name("leoSelectSidebarSection")
    static let leoToggleInspector       = Notification.Name("leoToggleInspector")
    static let leoOpenQuickAdd          = Notification.Name("leoOpenQuickAdd")
    static let leoOpenCommandPalette    = Notification.Name("leoOpenCommandPalette")
    static let leoCompleteSelectedItem  = Notification.Name("leoCompleteSelectedItem")
    static let leoRescheduleSelectedItem = Notification.Name("leoRescheduleSelectedItem")
    static let leoSnoozeSelected        = Notification.Name("leoSnoozeSelected")
    static let leoDeleteSelectedItem    = Notification.Name("leoDeleteSelectedItem")
    static let leoOpenDebugMenu         = Notification.Name("leoOpenDebugMenu")
}
