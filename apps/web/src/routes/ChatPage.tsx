import { useEffect, useMemo, useRef, useState, type ChangeEvent, type FormEvent } from 'react'
import { Camera, Cpu, FileText, Image as ImageIcon, KeyRound, MessageSquarePlus, Paperclip, Sparkles, Trash2, X } from 'lucide-react'
import { toast } from 'sonner'
import '@/ai/tools' // side-effect import — registers every tool with toolRuntime
import { Button } from '@/components/ui/button'
import { TextField } from '@/components/ui/TextField'
import { ChatMessage } from '@/components/chat/ChatMessage'
import { AISettingsPanel } from '@/components/chat/AISettingsPanel'
import { useChatStore, type ChatMessage as ChatMessageType } from '@/ai/session/chatStore'
import { loadStoredApiKey, storeApiKey } from '@/ai/session/chatStore'
import { sendUserMessage, type PendingAttachment } from '@/ai/chatOrchestrator'
import { getProvider, setProvider, isWebGPUSupported, type AIProvider } from '@/ai/provider'
import { cn } from '@/lib/utils'

// Stable reference for the "no active conversation yet" case — a fresh `[]`
// on every selector call would make Zustand's useSyncExternalStore see a
// "changed" value on every render and loop forever (documented gotcha in
// sync/store.ts; the same rule applies to this store).
const EMPTY_MESSAGES: ChatMessageType[] = []

// Anthropic's own request-size ceiling is higher, but this keeps a base64-
// encoded upload (~33% larger than the raw file) comfortably under it.
const MAX_PDF_SIZE_BYTES = 20 * 1024 * 1024
const MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function readFileAsBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      const result = reader.result as string
      // FileReader.readAsDataURL() prefixes with "data:application/pdf;base64," — Claude's
      // document content block wants just the base64 payload, not the data: URL.
      resolve(result.slice(result.indexOf(',') + 1))
    }
    reader.onerror = () => reject(reader.error ?? new Error('Failed to read file'))
    reader.readAsDataURL(file)
  })
}

function ConversationList({
  activeConversationId,
  onSwitch,
  onNew,
  onDelete,
}: {
  activeConversationId: string | null
  onSwitch: (id: string) => void
  onNew: () => void
  onDelete: (id: string) => void
}) {
  const conversations = useChatStore((s) => s.conversations)
  const sorted = useMemo(() => [...conversations].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)), [conversations])

  return (
    <div className="flex w-56 shrink-0 flex-col border-r border-divider pr-3">
      <Button variant="secondary" size="sm" onClick={onNew} className="mb-3 justify-start gap-2">
        <MessageSquarePlus className="h-4 w-4" aria-hidden="true" />
        New chat
      </Button>

      <ul className="flex flex-1 flex-col gap-0.5 overflow-y-auto">
        {sorted.length === 0 && <li className="px-2 text-xs text-text-secondary">No conversations yet</li>}
        {sorted.map((c) => (
          <li key={c.id} className="group flex items-center gap-1">
            <button
              type="button"
              onClick={() => onSwitch(c.id)}
              aria-pressed={c.id === activeConversationId}
              className={cn(
                'flex-1 truncate rounded-leo-sm px-2 py-1.5 text-left text-sm',
                c.id === activeConversationId
                  ? 'bg-accent-muted font-medium text-accent'
                  : 'text-text-primary hover:bg-surface-elevated'
              )}
            >
              {c.title}
            </button>
            <button
              type="button"
              onClick={() => onDelete(c.id)}
              aria-label={`Delete conversation "${c.title}"`}
              className="rounded-leo-sm p-1 text-text-secondary opacity-0 hover:bg-surface-elevated hover:text-danger group-hover:opacity-100"
            >
              <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}

export function ChatPage() {
  const activeConversationId = useChatStore((s) => s.activeConversationId)
  const messages = useChatStore((s) => s.conversations.find((c) => c.id === s.activeConversationId)?.messages ?? EMPTY_MESSAGES)
  const newConversation = useChatStore((s) => s.newConversation)
  const switchConversation = useChatStore((s) => s.switchConversation)
  const deleteConversation = useChatStore((s) => s.deleteConversation)

  const [apiKey, setApiKeyState] = useState(() => loadStoredApiKey())
  const [provider, setProviderState] = useState<AIProvider>(() => getProvider())
  const [keyInput, setKeyInput] = useState('')
  const [input, setInput] = useState('')
  const [sending, setSending] = useState(false)
  const [pendingAttachments, setPendingAttachments] = useState<PendingAttachment[]>([])
  const scrollRef = useRef<HTMLDivElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const imageInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
  }, [messages])

  function handleSaveKey(e: FormEvent) {
    e.preventDefault()
    const trimmed = keyInput.trim()
    if (!trimmed) return
    storeApiKey(trimmed)
    setApiKeyState(trimmed)
    setKeyInput('')
  }

  // Without this, a bad/expired key had no recovery path short of clearing
  // localStorage in DevTools — ChatPage only ever showed the key-entry
  // screen when NO key was stored, not when the stored one stopped working.
  function handleChangeKey() {
    storeApiKey('')
    setApiKeyState('')
  }

  function handleProviderChange(next: AIProvider) {
    setProvider(next)
    setProviderState(next)
  }

  async function handleSend(e: FormEvent) {
    e.preventDefault()
    const text = input.trim()
    if ((!text && pendingAttachments.length === 0) || sending) return
    setInput('')
    const attachments = pendingAttachments
    setPendingAttachments([])
    setSending(true)
    try {
      await sendUserMessage(text, attachments)
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      toast.error("Couldn't reach LEO", { description: message })
    } finally {
      setSending(false)
    }
  }

  async function handleFilesSelected(e: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? [])
    e.target.value = '' // clears the input so selecting the same file again still fires onChange
    for (const file of files) {
      if (file.type !== 'application/pdf') {
        toast.error(`"${file.name}" isn't a PDF`, { description: 'Only PDF attachments are supported right now.' })
        continue
      }
      if (file.size > MAX_PDF_SIZE_BYTES) {
        toast.error(`"${file.name}" is too large`, { description: `PDFs are limited to ${MAX_PDF_SIZE_BYTES / (1024 * 1024)} MB.` })
        continue
      }
      try {
        const base64 = await readFileAsBase64(file)
        setPendingAttachments((prev) => [...prev, { name: file.name, mimeType: file.type, base64, sizeBytes: file.size, kind: 'pdf' }])
      } catch {
        toast.error(`Couldn't read "${file.name}"`)
      }
    }
  }

  // Camera/photo picker — `capture="environment"` opens the rear camera directly
  // on mobile browsers; desktop browsers fall back to a plain file picker. On-
  // device OCR runs later, at send time (see chatOrchestrator.ts's
  // sendUserMessage), mirroring AssistantChatViewModel.swift's design — the
  // attach step here just holds the raw bytes.
  async function handleImageSelected(e: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? [])
    e.target.value = ''
    for (const file of files) {
      if (!file.type.startsWith('image/')) {
        toast.error(`"${file.name}" isn't an image`)
        continue
      }
      if (file.size > MAX_IMAGE_SIZE_BYTES) {
        toast.error(`"${file.name}" is too large`, { description: `Photos are limited to ${MAX_IMAGE_SIZE_BYTES / (1024 * 1024)} MB.` })
        continue
      }
      try {
        const base64 = await readFileAsBase64(file)
        setPendingAttachments((prev) => [...prev, { name: file.name, mimeType: file.type, base64, sizeBytes: file.size, kind: 'image' }])
      } catch {
        toast.error(`Couldn't read "${file.name}"`)
      }
    }
  }

  function removePendingAttachment(index: number) {
    setPendingAttachments((prev) => prev.filter((_, i) => i !== index))
  }

  if (provider === 'webllm' && !isWebGPUSupported()) {
    return (
      <div className="flex h-full flex-col items-center justify-center p-6 text-center">
        <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-accent-muted">
          <Cpu className="h-6 w-6 text-accent" aria-hidden="true" />
        </div>
        <h1 className="mb-1 text-xl font-semibold text-text-primary">On-device mode isn't supported here</h1>
        <p className="mb-6 max-w-sm text-sm text-text-secondary">
          The on-device model needs WebGPU, which this browser doesn't have available. Try a recent Chrome or Edge,
          or switch back to Claude.
        </p>
        <Button onClick={() => handleProviderChange('claude')}>Switch to Claude</Button>
      </div>
    )
  }

  if (provider === 'claude' && !apiKey) {
    return (
      <div className="flex h-full flex-col items-center justify-center p-6 text-center">
        <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-accent-muted">
          <KeyRound className="h-6 w-6 text-accent" aria-hidden="true" />
        </div>
        <h1 className="mb-1 text-xl font-semibold text-text-primary">API Key Required</h1>
        <p className="mb-6 max-w-sm text-sm text-text-secondary">
          Ask LEO uses the Claude API. Add your Anthropic API key to get started. It's stored in your browser's local
          storage and sent to our proxy, which forwards it to Anthropic — visible to anyone with access to this
          browser via DevTools.
        </p>
        <form onSubmit={handleSaveKey} className="flex w-full max-w-sm gap-2">
          <TextField
            label="Anthropic API key"
            type="password"
            className="flex-1"
            value={keyInput}
            onChange={(e) => setKeyInput(e.target.value)}
          />
        </form>
        <Button className="mt-3" onClick={handleSaveKey}>
          Add API Key
        </Button>
        <a href="https://console.anthropic.com" target="_blank" rel="noreferrer" className="mt-4 text-sm text-accent hover:underline">
          Get a key at console.anthropic.com
        </a>
        {isWebGPUSupported() && (
          <>
            <div className="mt-6 flex w-full max-w-sm items-center gap-2 text-xs text-text-secondary">
              <div className="h-px flex-1 bg-divider" />
              or
              <div className="h-px flex-1 bg-divider" />
            </div>
            <Button variant="outline" className="mt-4 gap-2" onClick={() => handleProviderChange('webllm')}>
              <Cpu className="h-4 w-4" aria-hidden="true" />
              Use a free on-device model instead
            </Button>
            <p className="mt-2 max-w-sm text-xs text-text-secondary">
              Runs locally in this browser tab, no API key or cost — can read your schedule/fitness data and propose
              changes too, but needs a one-time ~5GB model download and is noticeably less reliable than Claude at
              picking the right tool.
            </p>
          </>
        )}
      </div>
    )
  }

  return (
    <div className="flex h-full p-6">
      <ConversationList
        activeConversationId={activeConversationId}
        onSwitch={switchConversation}
        onNew={newConversation}
        onDelete={deleteConversation}
      />

      <div className="flex flex-1 flex-col pl-6">
        <div className="mb-4 flex items-center justify-between">
          <h1 className="flex items-center gap-2 text-xl font-semibold text-text-primary">
            {provider === 'webllm' ? (
              <Cpu className="h-5 w-5 text-accent" aria-hidden="true" />
            ) : (
              <Sparkles className="h-5 w-5 text-accent" aria-hidden="true" />
            )}
            Ask LEO
            {provider === 'webllm' && (
              <span className="rounded-leo-pill bg-surface-elevated px-2 py-0.5 text-xs font-medium text-text-secondary">
                On-device
              </span>
            )}
          </h1>
          <div className="flex items-center gap-1">
            {provider === 'claude' && <AISettingsPanel />}
            {provider === 'webllm' ? (
              <Button variant="ghost" size="sm" onClick={() => handleProviderChange('claude')} className="gap-1.5 text-text-secondary">
                <Sparkles className="h-3.5 w-3.5" aria-hidden="true" />
                Switch to Claude
              </Button>
            ) : (
              <>
                <Button variant="ghost" size="sm" onClick={() => handleProviderChange('webllm')} className="gap-1.5 text-text-secondary">
                  <Cpu className="h-3.5 w-3.5" aria-hidden="true" />
                  Switch to on-device
                </Button>
                <Button variant="ghost" size="sm" onClick={handleChangeKey} className="gap-1.5 text-text-secondary">
                  <KeyRound className="h-3.5 w-3.5" aria-hidden="true" />
                  Change API key
                </Button>
              </>
            )}
          </div>
        </div>

        <div ref={scrollRef} className="mb-4 flex-1 overflow-y-auto">
          {messages.length === 0 && (
            <p className="text-sm text-text-secondary">
              {provider === 'webllm'
                ? "Chat with a model running locally in this browser tab — free, and it can check your schedule/fitness data and propose changes, same as Claude mode, but less reliably. No PDF/photo attachments here. First message downloads the model (~5GB)."
                : "Ask about your schedule, or ask LEO to reschedule, add, or cancel items — you'll always review changes before they're applied. You can also attach a PDF, or a photo of handwritten notes, for LEO to read."}
            </p>
          )}
          <div className="flex flex-col gap-3">
            {messages.map((m) => (
              <ChatMessage key={m.id} message={m} />
            ))}
          </div>
        </div>

        <form onSubmit={handleSend} className="flex flex-col gap-2">
          {pendingAttachments.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {pendingAttachments.map((a, i) => (
                <span
                  key={`${a.name}-${i}`}
                  className="flex items-center gap-1.5 rounded-leo-pill bg-surface-elevated py-1 pr-1 pl-2.5 text-xs text-text-primary"
                >
                  {a.kind === 'image' ? (
                    <ImageIcon className="h-3.5 w-3.5 shrink-0 text-accent" aria-hidden="true" />
                  ) : (
                    <FileText className="h-3.5 w-3.5 shrink-0 text-accent" aria-hidden="true" />
                  )}
                  <span className="max-w-[160px] truncate">{a.name}</span>
                  <span className="shrink-0 text-text-secondary">{formatBytes(a.sizeBytes)}</span>
                  <button
                    type="button"
                    onClick={() => removePendingAttachment(i)}
                    aria-label={`Remove ${a.name}`}
                    className="shrink-0 rounded-full p-0.5 hover:bg-surface"
                  >
                    <X className="h-3 w-3" aria-hidden="true" />
                  </button>
                </span>
              ))}
            </div>
          )}
          <div className="flex gap-2">
            <input ref={fileInputRef} type="file" accept="application/pdf" multiple className="hidden" onChange={handleFilesSelected} />
            <Button
              type="button"
              variant="outline"
              size="icon"
              onClick={() => fileInputRef.current?.click()}
              disabled={sending || provider === 'webllm'}
              aria-label="Attach a PDF"
              title={provider === 'webllm' ? "On-device mode can't read attachments" : undefined}
              className="self-end"
            >
              <Paperclip className="h-4 w-4" aria-hidden="true" />
            </Button>
            <input
              ref={imageInputRef}
              type="file"
              accept="image/*"
              capture="environment"
              multiple
              className="hidden"
              onChange={handleImageSelected}
            />
            <Button
              type="button"
              variant="outline"
              size="icon"
              onClick={() => imageInputRef.current?.click()}
              disabled={sending || provider === 'webllm'}
              aria-label="Attach a photo"
              title={provider === 'webllm' ? "On-device mode can't read attachments" : undefined}
              className="self-end"
            >
              <Camera className="h-4 w-4" aria-hidden="true" />
            </Button>
            <TextField
              label="Message"
              className="flex-1"
              placeholder="Ask LEO…"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              disabled={sending}
            />
            <Button type="submit" disabled={sending || (!input.trim() && pendingAttachments.length === 0)} className="self-end">
              {sending ? 'Sending…' : 'Send'}
            </Button>
          </div>
        </form>
      </div>
    </div>
  )
}
