import { useEffect, useState } from 'react'
import { subscribeArmedCount } from './scheduler'

/**
 * Unmissable, not a buried caveat: whenever >=1 alarm is armed, a persistent
 * banner states the actual limitation plainly — a browser tab has no
 * background execution, so an alarm only fires while this tab stays open.
 * Two visually distinct states driven by the Page Visibility API, matching
 * the plan's §8 design.
 */
export function AlarmBanner() {
  const [armedCount, setArmedCount] = useState(0)
  const [visible, setVisible] = useState(document.visibilityState === 'visible')

  useEffect(() => {
    const unsubscribe = subscribeArmedCount(setArmedCount)
    const onVisibilityChange = () => setVisible(document.visibilityState === 'visible')
    document.addEventListener('visibilitychange', onVisibilityChange)
    return () => {
      unsubscribe()
      document.removeEventListener('visibilitychange', onVisibilityChange)
    }
  }, [])

  if (armedCount === 0) return null

  return (
    <div
      role="status"
      className={`px-3 py-1.5 text-center text-xs font-medium ${
        visible ? 'bg-accent-muted text-accent' : 'bg-warning/20 text-warning'
      }`}
    >
      {visible
        ? `${armedCount} alarm${armedCount === 1 ? '' : 's'} armed — keep this tab open`
        : `⚠ Tab is in the background — ${armedCount} alarm${armedCount === 1 ? '' : 's'} may not fire reliably`}
    </div>
  )
}
