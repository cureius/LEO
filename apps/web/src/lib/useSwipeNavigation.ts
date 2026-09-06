import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'

// A trackpad flick fires a burst of wheel events; these tune when that burst
// counts as a deliberate back/forward swipe rather than incidental drift.
const TRIGGER_DISTANCE = 110
const GESTURE_IDLE_MS = 250
const HORIZONTAL_RATIO = 1.6

// Whether the cursor is over an element that can itself scroll
// horizontally — the gesture is suppressed there unconditionally (not just
// mid-scroll), since a swipe on that area reads as "scroll this" to the
// user, not "navigate the app," even once it's hit the start/end edge.
function isOverHorizontallyScrollable(target: EventTarget | null): boolean {
  let el = target instanceof Element ? target : null
  while (el) {
    const overflowX = getComputedStyle(el).overflowX
    if ((overflowX === 'auto' || overflowX === 'scroll') && el.scrollWidth - el.clientWidth > 1) return true
    el = el.parentElement
  }
  return false
}

/** Two-finger horizontal trackpad swipes navigate back/forward, the way they
 *  do in Chrome and Safari.
 *
 *  Only active inside the Tauri shell: its WKWebView ships with
 *  `allowsBackForwardNavigationGestures` off, so without this the gesture is
 *  simply dead. Real browsers already handle it natively, and running this
 *  there too would navigate twice per swipe. */
export function useSwipeNavigation() {
  const navigate = useNavigate()

  useEffect(() => {
    if (!('__TAURI_INTERNALS__' in window)) return

    let accumulatedX = 0
    let lastEventAt = 0
    let triggered = false

    function handleWheel(event: WheelEvent) {
      const now = Date.now()
      if (now - lastEventAt > GESTURE_IDLE_MS) {
        accumulatedX = 0
        triggered = false
      }
      lastEventAt = now

      if (triggered) return
      if (Math.abs(event.deltaX) < Math.abs(event.deltaY) * HORIZONTAL_RATIO) return
      if (isOverHorizontallyScrollable(event.target)) return

      accumulatedX += event.deltaX
      if (Math.abs(accumulatedX) < TRIGGER_DISTANCE) return

      triggered = true
      navigate(accumulatedX < 0 ? -1 : 1)
      accumulatedX = 0
    }

    window.addEventListener('wheel', handleWheel, { passive: true })
    return () => window.removeEventListener('wheel', handleWheel)
  }, [navigate])
}
