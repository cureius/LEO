import SwiftUI

struct MacShellView: View {
    @Environment(MacNavigationModel.self) private var nav
    @Environment(AppEnvironment.self) private var appEnv
    @SceneStorage("leo.sidebar.section") private var sectionRaw: String = SidebarSection.today.rawValue
    @AppStorage("leo.inspector.visible") private var inspectorVisible: Bool = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isRefreshing = false

    var body: some View {
        @Bindable var navBinding = nav
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebar()
        } content: {
            MacContentPane()
                .frame(minWidth: 400, idealWidth: 600)
        } detail: {
            MacInspector()
                .frame(minWidth: 280, idealWidth: 320)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .leoTopBarLeading) {
                MacQuickAddView()
                    .frame(minWidth: 260, idealWidth: 360)
            }
            ToolbarItem(placement: .leoTopBarTrailing) {
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    NotificationCenter.default.post(name: .leoRefreshRequested, object: nil)
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
                .help("Refresh — pull the latest events and synced items (⌘R)")
                .accessibilityLabel("Refresh")
            }
        }
        // Handle item actions from menu bar / keyboard shortcuts
        .onReceive(NotificationCenter.default.publisher(for: .leoSelectSidebarSection)) { note in
            if let section = note.object as? SidebarSection {
                nav.selection = section
                nav.selectedItemID = nil  // clear item selection when changing sections
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoCompleteSelectedItem)) { _ in
            guard let id = nav.selectedItemID else { return }
            Task {
                guard var items = try? await appEnv.itemRepository.fetch(predicate: .byID(id)),
                      var item = items.first else { return }
                item.completion = .completed(at: .now)
                try? await appEnv.itemRepository.update(item)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoDeleteSelectedItem)) { _ in
            guard let id = nav.selectedItemID else { return }
            Task {
                try? await appEnv.itemRepository.delete(id: id)
                nav.selectedItemID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoRescheduleSelectedItem)) { _ in
            // Bug 2: open inspector so user can edit the anchor
            guard nav.selectedItemID != nil else { return }
            nav.inspectorVisible = true
            columnVisibility = .all
        }
        .onAppear {
            if let restored = SidebarSection(rawValue: sectionRaw) {
                nav.selection = restored
            }
            nav.inspectorVisible = inspectorVisible  // sync model with persisted value (Bug 1)
            columnVisibility = inspectorVisible ? .all : .doubleColumn
        }
        .onChange(of: nav.selection) { _, new in sectionRaw = new.rawValue }
        .onChange(of: nav.inspectorVisible) { _, visible in
            inspectorVisible = visible
            columnVisibility = visible ? .all : .doubleColumn
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoToggleInspector)) { _ in
            nav.inspectorVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoRefreshCompleted)) { _ in
            isRefreshing = false
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
    /// User asked for fresh data (⌘R or the toolbar button). `.refreshable` is a
    /// pull-down gesture and macOS has no pull-to-refresh, so the Mac needs an
    /// explicit command.
    static let leoRefreshRequested      = Notification.Name("leoRefreshRequested")
    /// Posted by the refresh handler once the calendar + cloud sync finishes, so
    /// the toolbar button's spinner reflects real completion rather than a guess.
    static let leoRefreshCompleted      = Notification.Name("leoRefreshCompleted")
}
