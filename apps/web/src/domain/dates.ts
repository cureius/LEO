/** 23:59 local time on the given day — used wherever a "due by end of day"
 *  default is needed (Inbox's EOD bulk action, QuickAddForm's day-page default). */
export function endOfDay(date: Date): Date {
  const d = new Date(date)
  d.setHours(23, 59, 0, 0)
  return d
}
