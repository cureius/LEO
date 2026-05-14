import SwiftUI

@MainActor
struct WeeklyReviewView: View {
    let review: WeeklyReview
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    #if os(iOS)
    @State private var shareImage: UIImage? = nil
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero
                    heroSection

                    // Stats
                    statsSection

                    // Habits
                    habitsSection

                    // AI narrative
                    narrativeSection

                    // Suggestions (actionable)
                    suggestionsSection
                }
                .padding()
            }
            .navigationTitle("Weekly Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .leoTopBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .leoTopBarTrailing) {
                    ShareLink("Share", item: "Week of \(formattedWeek)")
                }
            }
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: 8) {
            Text("Week of \(formattedWeek)")
                .font(.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            Text("\(review.completedCount) items completed")
                .font(.system(size: 34, weight: .bold))
            if review.slippedCount > 0 {
                Text("\(review.slippedCount) slipped past deadline")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.warning)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private var statsSection: some View {
        HStack(spacing: 16) {
            StatCard(title: "Completed", value: "\(review.completedCount)", color: Theme.Color.success)
            StatCard(title: "Slipped", value: "\(review.slippedCount)", color: Theme.Color.warning)
        }
    }

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Habits")
                .font(Theme.Typography.headline)
            ForEach(review.habitStreakSummaries, id: \.habitName) { summary in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.habitName)
                            .font(Theme.Typography.body)
                        Text("\(summary.completedThisWeek)/\(summary.totalThisWeek) this week")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                    Label("\(summary.streakDays)d", systemImage: "flame.fill")
                        .font(.caption.bold())
                        .foregroundStyle(summary.streakDays > 7 ? Theme.Color.warning : Theme.Color.textSecondary)
                }
                .padding(10)
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }

    private var narrativeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReviewNarrativeCard(title: "Highlights", icon: "star.fill", color: Theme.Color.accent, text: review.highlights)
            ReviewNarrativeCard(title: "What slipped", icon: "exclamationmark.triangle", color: Theme.Color.warning, text: review.slips)
            ReviewNarrativeCard(title: "Themes", icon: "lightbulb", color: Theme.Color.success, text: review.themes)
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions")
                .font(Theme.Typography.headline)
            ForEach(review.suggestions, id: \.self) { suggestion in
                HStack {
                    Text(suggestion)
                        .font(Theme.Typography.body)
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.Color.accent)
                }
                .padding(12)
                .background(Theme.Color.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }

    // MARK: - Helpers

    private var formattedWeek: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return "\(f.string(from: review.weekInterval.start)) – \(f.string(from: review.weekInterval.end))"
    }
}

// MARK: - Helper views

private struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

private struct ReviewNarrativeCard: View {
    let title: String
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(text)
                .font(Theme.Typography.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}
