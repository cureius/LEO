/**
 * Human-readable "what LEO is doing right now" labels shown in the chat
 * while a tool call is in flight — without this, the only visible state
 * between "you sent a message" and "the final answer appears" was a bare
 * "…", even when LEO was actually off checking the calendar or building a
 * multi-step plan for several seconds.
 */
const TOOL_LABELS: Record<string, string> = {
  get_today: "Checking today's schedule",
  get_week: "Checking this week's schedule",
  get_past_items: 'Looking back through your history',
  find_free_slots: 'Finding free time',
  get_item: 'Looking up item details',
  get_body_profile: 'Checking your fitness profile',
  get_fitness_items: 'Checking all your workouts and meals',
  propose_reschedule: 'Preparing a reschedule',
  propose_add: 'Preparing new items',
  propose_cancel: 'Preparing a cancellation',
  propose_workout_plan: 'Building a workout plan',
  propose_meal_plan: 'Building a meal plan',
  set_workout_exercises: 'Filling in exercises, sets & reps',
  adjust_plan: 'Adjusting the plan',
}

export function toolActivityLabel(toolName: string): string {
  return TOOL_LABELS[toolName] ?? `Using ${toolName.replace(/_/g, ' ')}`
}
