import SwiftUI

struct MacContentPane: View {
    @Environment(MacNavigationModel.self) private var nav

    var body: some View {
        NavigationStack {
            Group {
                switch nav.selection {
                case .today:   MacTodayView()
                case .inbox:   MacInboxView()
                case .habits:  MacHabitsView()
                case .ask:     MacAssistantChatView()
                case .fitness: MacFitnessHomeView()
                case .settings: EmptyView()
                }
            }
        }
    }
}

struct MacPlaceholderView: View {
    let title: String
    let milestone: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title2.bold())
            Text("Coming in \(milestone)")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
