import SwiftUI

struct MacContentPane: View {
    @Environment(MacNavigationModel.self) private var nav

    var body: some View {
        Group {
            switch nav.selection {
            case .today:    MacPlaceholderView(title: "Today", milestone: "MM3-T01")
            case .inbox:    MacPlaceholderView(title: "Inbox", milestone: "MM3-T03")
            case .habits:   MacPlaceholderView(title: "Habits", milestone: "MM3-T05")
            case .ask:      MacPlaceholderView(title: "Ask LEO", milestone: "MM5-T01")
            case .fitness:  MacPlaceholderView(title: "Fitness", milestone: "MM7-T02")
            case .settings: EmptyView()
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
