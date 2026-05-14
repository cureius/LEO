import SwiftUI

/// Mac Weekly Review window — reuses WeeklyReviewView from iOS.
/// Opened via Window → Weekly Review (⌘⇧W).
struct MacWeeklyReviewWindowContent: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var review: WeeklyReview? = nil
    @State private var isGenerating = false
    @State private var error: String? = nil

    var body: some View {
        Group {
            if let review {
                WeeklyReviewView(review: review)
                    .environment(appEnv)
            } else if isGenerating {
                VStack(spacing: 16) {
                    ProgressView("Generating weekly review…")
                    Text("LEO is reflecting on your week.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.Color.accent)
                    Text("Weekly Review")
                        .font(.title2.bold())
                    Text("Get an AI-powered analysis of your week: completions, streaks, and recommendations.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 360)
                    Button("Generate this week's review") { Task { await generate() } }
                        .buttonStyle(.borderedProminent)
                    if let err = error {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            }
        }
        .navigationTitle("Weekly Review")
    }

    private func generate() async {
        isGenerating = true
        error = nil
        let now = Date.now
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let interval = DateInterval(start: weekStart, end: now)
        do {
            review = try await appEnv.weeklyReviewGenerator.generate(for: interval)
        } catch let err {
            self.error = err.localizedDescription
        }
        isGenerating = false
    }
}
