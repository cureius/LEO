import { FileText, Image as ImageIcon, Loader2, ScanText } from 'lucide-react'
import { DiffReview } from './DiffReview'
import { Markdown } from '@/components/markdown/Markdown'
import { toolActivityLabel } from '@/ai/toolDisplay'
import { useChatStore, type ChatAttachment, type ChatMessage as ChatMessageType } from '@/ai/session/chatStore'

/** Read-only file chip shown on a sent message. If `base64` is missing (the
 *  message survived a page reload — see chatStore.ts's `partialize`, which
 *  strips attachment bytes before writing to localStorage), the filename is
 *  still shown but marked as no longer attached, since re-analyzing it would
 *  need the file re-uploaded. */
function AttachmentChips({ attachments }: { attachments: ChatAttachment[] }) {
  return (
    <div className="mb-1.5 flex flex-wrap gap-1.5">
      {attachments.map((a) => (
        <span
          key={a.id}
          className="flex items-center gap-1.5 rounded-leo-pill bg-white/15 px-2.5 py-1 text-xs"
          title={a.base64 ? undefined : 'No longer attached — the file isn\'t kept after a reload, only its name'}
        >
          {a.kind === 'image' ? (
            <ImageIcon className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
          ) : (
            <FileText className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
          )}
          <span className="max-w-[160px] truncate">{a.name}</span>
          {!a.base64 && <span className="opacity-70">(not attached)</span>}
        </span>
      ))}
    </div>
  )
}

/** Photo thumbnail + on-device-OCR caption — shown whenever a photo was
 *  attached, regardless of whether OCR succeeded (mirrors ChatSessionView.swift's
 *  UserMessageRow image+ocrText block). On reload `imagePreview` is gone
 *  (stripped on persist, see chatStore.ts), so only the caption survives. */
function PhotoPreview({ imagePreview, mimeType, ocrText }: { imagePreview?: string; mimeType?: string; ocrText?: string }) {
  return (
    <div className="mb-1.5 flex flex-col gap-1.5">
      {imagePreview && (
        <img
          src={`data:${mimeType ?? 'image/jpeg'};base64,${imagePreview}`}
          alt="Attached photo"
          className="max-h-45 max-w-55 rounded-leo-sm object-cover"
        />
      )}
      {ocrText && (
        <div className="flex items-start gap-1.5 rounded-leo-sm bg-white/15 px-2.5 py-1.5 text-xs">
          <ScanText className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden="true" />
          <span className="line-clamp-6 font-mono">{ocrText}</span>
        </div>
      )}
    </div>
  )
}

/** Three-dot "thinking" indicator — shown before LEO has decided what it's
 *  doing yet (no text, no tool call in flight). */
function TypingDots() {
  return (
    <span className="inline-flex items-center gap-1 py-0.5" aria-label="LEO is typing">
      <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-text-secondary [animation-delay:-0.3s]" />
      <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-text-secondary [animation-delay:-0.15s]" />
      <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-text-secondary" />
    </span>
  )
}

/** "Checking today's schedule…" style status while a tool call is in flight. */
function ToolActivity({ toolName }: { toolName: string }) {
  return (
    <span className="inline-flex items-center gap-2 py-0.5 text-sm text-text-secondary">
      <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden="true" />
      {toolActivityLabel(toolName)}…
    </span>
  )
}

export function ChatMessage({ message }: { message: ChatMessageType }) {
  const updateMessage = useChatStore((s) => s.updateMessage)
  const isUser = message.role === 'user'
  const isPending = !isUser && !message.text && !message.error

  return (
    <div className={`flex ${isUser ? 'justify-end' : 'justify-start'}`}>
      <div className={`max-w-[80%] rounded-leo-md px-3 py-2 ${isUser ? 'bg-accent text-white' : 'bg-surface-elevated text-text-primary'}`}>
        {isUser && (message.imagePreview || message.ocrText) && (
          <PhotoPreview
            imagePreview={message.imagePreview}
            mimeType={message.attachments?.find((a) => a.kind === 'image')?.mimeType}
            ocrText={message.ocrText}
          />
        )}
        {isUser && message.attachments && message.attachments.filter((a) => a.kind !== 'image').length > 0 && (
          <AttachmentChips attachments={message.attachments.filter((a) => a.kind !== 'image')} />
        )}
        {isUser && <p className="text-sm whitespace-pre-wrap">{message.text}</p>}

        {!isUser && message.text && <Markdown text={message.text} className="text-sm" />}

        {isPending && (message.activeTool ? <ToolActivity toolName={message.activeTool} /> : <TypingDots />)}

        {message.error && (
          <p className="text-sm text-danger">
            {message.text && <span className="mr-1">·</span>}
            Couldn't get a response: {message.error}
          </p>
        )}
        {message.pendingDiff && !message.diffResolved && (
          <DiffReview diff={message.pendingDiff} onResolved={() => updateMessage(message.id, { diffResolved: true })} />
        )}
      </div>
    </div>
  )
}
