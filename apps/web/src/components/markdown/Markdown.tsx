import ReactMarkdown, { type Components } from 'react-markdown'
import remarkGfm from 'remark-gfm'

/**
 * Shared Tailwind-styled overrides for every element markdown content
 * actually uses in practice (bold emphasis, lists, links, inline/fenced
 * code) — sized and spaced for LEO's compact UI rather than react-markdown's
 * unstyled defaults, which read as a wall of text at text-sm. Originally
 * ChatMessage-only (chat bubbles); pulled out so project notes and task
 * notes render with the exact same look instead of a second hand-copied set
 * of overrides drifting from this one.
 */
const MARKDOWN_COMPONENTS: Components = {
  p: ({ children }) => <p className="mb-2 whitespace-pre-wrap last:mb-0">{children}</p>,
  ul: ({ children }) => <ul className="mb-2 ml-4 list-disc space-y-0.5 last:mb-0">{children}</ul>,
  ol: ({ children }) => <ol className="mb-2 ml-4 list-decimal space-y-0.5 last:mb-0">{children}</ol>,
  li: ({ children }) => <li>{children}</li>,
  strong: ({ children }) => <strong className="font-semibold text-text-primary">{children}</strong>,
  em: ({ children }) => <em className="italic">{children}</em>,
  a: ({ children, href }) => (
    <a href={href} target="_blank" rel="noreferrer" className="text-accent underline hover:no-underline">
      {children}
    </a>
  ),
  code: ({ children, className }) => {
    const isFenced = /language-/.test(className ?? '')
    if (isFenced) return <code className={className}>{children}</code>
    return <code className="rounded bg-surface px-1 py-0.5 font-mono text-[0.85em]">{children}</code>
  },
  pre: ({ children }) => <pre className="my-2 overflow-x-auto rounded-leo-sm bg-surface p-2 font-mono text-xs">{children}</pre>,
  h1: ({ children }) => <h3 className="mt-2 mb-1 text-base font-semibold first:mt-0">{children}</h3>,
  h2: ({ children }) => <h3 className="mt-2 mb-1 text-base font-semibold first:mt-0">{children}</h3>,
  h3: ({ children }) => <h4 className="mt-2 mb-1 text-sm font-semibold first:mt-0">{children}</h4>,
  blockquote: ({ children }) => <blockquote className="border-l-2 border-divider pl-2 text-text-secondary italic">{children}</blockquote>,
  hr: () => <hr className="my-2 border-divider" />,
  table: ({ children }) => (
    <div className="mb-2 overflow-x-auto">
      <table className="border-collapse text-xs">{children}</table>
    </div>
  ),
  th: ({ children }) => <th className="border border-divider px-2 py-1 text-left font-semibold">{children}</th>,
  td: ({ children }) => <td className="border border-divider px-2 py-1">{children}</td>,
}

export function Markdown({ text, className }: { text: string; className?: string }) {
  return (
    <div className={className}>
      <ReactMarkdown remarkPlugins={[remarkGfm]} components={MARKDOWN_COMPONENTS}>
        {text}
      </ReactMarkdown>
    </div>
  )
}
