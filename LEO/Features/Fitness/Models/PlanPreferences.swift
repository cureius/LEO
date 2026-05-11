import Foundation

/// User-tunable inputs for the local fitness plan generator.
struct PlanPreferences: Hashable, Sendable {
    var weeks: Int
    var daysPerWeek: Int
    var splitStyle: SplitStyle
    var equipment: Set<Equipment>
    /// 24-hour hour at which workouts begin (5–22).
    var workoutHour: Int
    var workoutDurationMinutes: Int

    var includeMealPlan: Bool
    var mealsPerDay: Int

    var startDate: Date

    init(
        weeks: Int = 4,
        daysPerWeek: Int = 3,
        splitStyle: SplitStyle = .fullBody,
        equipment: Set<Equipment> = [.bodyweight, .dumbbells],
        workoutHour: Int = 7,
        workoutDurationMinutes: Int = 60,
        includeMealPlan: Bool = true,
        mealsPerDay: Int = 3,
        startDate: Date? = nil
    ) {
        self.weeks = weeks
        self.daysPerWeek = daysPerWeek
        self.splitStyle = splitStyle
        self.equipment = equipment
        self.workoutHour = workoutHour
        self.workoutDurationMinutes = workoutDurationMinutes
        self.includeMealPlan = includeMealPlan
        self.mealsPerDay = mealsPerDay
        self.startDate = startDate ?? PlanPreferences.nextMonday()
    }

    static func nextMonday() -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        comps.weekday = 2  // Monday
        let monday = cal.date(from: comps) ?? .now
        return monday > .now ? monday : cal.date(byAdding: .weekOfYear, value: 1, to: monday) ?? .now
    }
}
