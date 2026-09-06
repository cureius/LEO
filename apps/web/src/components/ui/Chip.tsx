import type { ReactNode } from 'react'

/** Port of LEO/DesignSystem/Components/LEOChip.swift — small pill used for importance/tags. */
export function Chip({ children, tone = 'default' }: { children: ReactNode; tone?: 'default' | 'danger' | 'warning' }) {
  const toneClasses =
    tone === 'danger'
      ? 'bg-danger/15 text-danger'
      : tone === 'warning'
        ? 'bg-warning/15 text-warning'
        : 'bg-accent-muted text-text-primary'

  return <span className={`whitespace-nowrap rounded-leo-pill px-2 py-0.5 text-xs font-medium ${toneClasses}`}>{children}</span>
}
