import SwiftUI
import Charts

struct MeasurementsChartView: View {
    let measurements: [BodyMeasurement]
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var last12Weeks: [BodyMeasurement] {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) ?? .now
        return measurements.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if last12Weeks.isEmpty {
                    LEOEmptyState(
                        title: "No measurements yet",
                        message: "Log your first weight to start tracking progress.",
                        icon: "chart.line.uptrend.xyaxis",
                        action: ("Add measurement", { onAdd() })
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            weightChart
                            if last12Weeks.contains(where: { $0.bodyFatPct != nil }) {
                                bodyFatChart
                            }
                            statsSummary
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { onAdd() }
                }
            }
        }
    }

    private var weightChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight (kg)")
                .font(Theme.Typography.body.bold())

            Chart(last12Weeks) { m in
                LineMark(
                    x: .value("Date", m.date),
                    y: .value("Weight", m.weightKg)
                )
                .foregroundStyle(Theme.Color.accent)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", m.date),
                    y: .value("Weight", m.weightKg)
                )
                .foregroundStyle(Theme.Color.accent)
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        }
        .padding()
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var bodyFatChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Body fat %")
                .font(Theme.Typography.body.bold())

            let fatData = last12Weeks.filter { $0.bodyFatPct != nil }
            Chart(fatData) { m in
                LineMark(
                    x: .value("Date", m.date),
                    y: .value("Fat %", m.bodyFatPct!)
                )
                .foregroundStyle(Theme.Color.warning)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", m.date),
                    y: .value("Fat %", m.bodyFatPct!)
                )
                .foregroundStyle(Theme.Color.warning)
            }
            .frame(height: 140)
        }
        .padding()
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var statsSummary: some View {
        VStack(spacing: 16) {
            if let first = last12Weeks.first, let last = last12Weeks.last {
                let delta = last.weightKg - first.weightKg
                HStack {
                    statItem(label: "Start", value: "\(first.weightKg.formatted(.number.precision(.fractionLength(1)))) kg")
                    Spacer()
                    statItem(label: "Current", value: "\(last.weightKg.formatted(.number.precision(.fractionLength(1)))) kg")
                    Spacer()
                    statItem(
                        label: "Change",
                        value: "\(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) kg",
                        color: delta < 0 ? Theme.Color.success : Theme.Color.warning
                    )
                }
                .padding()
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }

    private func statItem(label: String, value: String, color: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            Text(value)
                .font(Theme.Typography.body.bold())
                .foregroundStyle(color ?? Theme.Color.textPrimary)
        }
    }
}
