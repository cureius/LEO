import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { DiffPayload } from '../diff/types'

export type ChatAttachment = {
  id: string
  name: string
  mimeType: string
  sizeBytes: number
  /** 'pdf' sends as a `document` block; 'image' sends as an `image` block —
   *  only reached when on-device OCR (ocr.ts) found nothing readable, since a
   *  successful OCR sends extracted text instead and never attaches the
   *  image bytes at all (see ChatMessage.imagePreview/ocrText below). */
  kind: 'pdf' | 'image'
  /**
   * Base64-encoded file bytes (no `data:` URL prefix) — present for the
   * lifetime of the browser session, but deliberately stripped before
   * writing to localStorage (see the `partialize` option below). A single
   * PDF can be several MB; keeping every attachment's full bytes in
   * persisted storage forever would blow past localStorage's ~5-10MB quota
   * after a handful of conversations. Trade-off: follow-up questions about
   * an attached PDF work for the rest of THIS session, but re-analyzing it
   * after a reload requires re-attaching — the message and its filename are
   * still remembered, just not the bytes.
   */
  base64?: string
}

export type ChatMessage = {
  id: string
  role: 'user' | 'assistant'
  text: string
  pendingDiff?: DiffPayload
  diffResolved?: boolean
  createdAt: string
  /** Set when the turn that produced this message failed — see chatOrchestrator.ts.
   *  Without this, a failed request left a permanently empty assistant placeholder that
   *  rendered as "…" forever, indistinguishable from "still streaming." */
  error?: string
  /** Name of the tool currently executing, while there's no text yet — cleared
   *  once text starts streaming or the turn finishes. Lets the UI show "Checking
   *  today's schedule…" instead of a bare, undifferentiated typing indicator. */
  activeTool?: string
  attachments?: ChatAttachment[]
  /**
   * Display-only photo thumbnail (base64 JPEG, no `data:` prefix) — set
   * whenever a photo was attached, REGARDLESS of whether on-device OCR
   * (ocr.ts) succeeded. Mirrors AssistantChatViewModel.swift's `imageData`
   * on ChatMessage: what's shown to the user and what's sent to Claude are
   * two different things on the OCR-success path (shown: the photo + the
   * extracted text as a caption; sent: just the text, no image bytes at
   * all) — this field is purely for the former. Stripped on persist, same
   * reasoning as ChatAttachment.base64.
   */
  imagePreview?: string
  /** Text extracted on-device by ocr.ts, or the "couldn't read locally" fallback
   *  message — set whenever a photo was attached. Mirrors ChatMessage.ocrText. */
  ocrText?: string
  /** True only when `ocrText` holds real extracted text (safe to weave into a
   *  resend to Claude — see chatOrchestrator.ts's buildMessageContent); false/
   *  undefined for the "couldn't read locally" fallback caption, which must
   *  never be sent to Claude as if it were the photo's actual content. */
  ocrSucceeded?: boolean
}

export type Conversation = {
  id: string
  title: string
  messages: ChatMessage[]
  createdAt: string
  updatedAt: string
}

type ChatState = {
  conversations: Conversation[]
  /** null means "no conversation materialized yet" — the New Chat state.
   *  A conversation is lazily created on the first message, not eagerly on
   *  clicking New Chat, so clicking it repeatedly without sending anything
   *  doesn't pile up empty entries in the sidebar. */
  activeConversationId: string | null

  addMessage: (message: ChatMessage) => void
  updateMessage: (id: string, patch: Partial<ChatMessage>) => void
  /** Always reads live state at call time — unlike destructuring `.messages`
   *  off a `getState()` snapshot captured earlier in the same function, which
   *  goes stale the moment any `set()` call happens afterward (a real bug
   *  caught here: chatOrchestrator.ts was building the array sent to Claude
   *  from a snapshot taken BEFORE the current turn's own addMessage calls,
   *  so the user's just-typed message — and on the first message of a
   *  conversation, every message — never actually reached the model). */
  getActiveMessages: () => ChatMessage[]

  newConversation: () => void
  switchConversation: (id: string) => void
  deleteConversation: (id: string) => void
}

// What actually round-trips through localStorage — just the data, not the
// action methods (which wouldn't survive JSON.stringify anyway). Naming this
// explicitly, rather than letting `partialize`'s return type be inferred,
// is what keeps zustand's `migrate` (which only ever needs to produce this
// same shape) correctly typed instead of TypeScript inferring it needs to
// return the full state-with-methods.
type PersistedChatState = Pick<ChatState, 'conversations' | 'activeConversationId'>

const TITLE_MAX_LENGTH = 48

function deriveTitle(text: string): string {
  const trimmed = text.trim().replace(/\s+/g, ' ')
  if (!trimmed) return 'New conversation'
  return trimmed.length > TITLE_MAX_LENGTH ? `${trimmed.slice(0, TITLE_MAX_LENGTH)}…` : trimmed
}

/**
 * Persisted to localStorage, matching native: `ConversationStore.swift`
 * persists chat history to a local file, NOT synced to Supabase/CloudKit —
 * chat history is device-local-only even on iOS/Mac today. This is parity,
 * not a shortcut; a cross-device-synced chat history is a legitimate v2
 * idea, explicitly out of scope here.
 *
 * Deliberately a separate storage key from the API key (below) — mixing a
 * credential into the same persisted blob as conversation history, purely
 * because they're both "chat state," would be a real reason to keep them
 * apart, not just tidiness.
 */
export const useChatStore = create<ChatState>()(
  persist(
    (set, get) => ({
      conversations: [],
      activeConversationId: null,

      addMessage: (message) =>
        set((state) => {
          let conversations = state.conversations
          let activeConversationId = state.activeConversationId
          let convo = conversations.find((c) => c.id === activeConversationId)
          const now = new Date().toISOString()

          if (!convo) {
            convo = { id: crypto.randomUUID(), title: 'New conversation', messages: [], createdAt: now, updatedAt: now }
            conversations = [convo, ...conversations]
            activeConversationId = convo.id
          }

          const isFirstUserMessage = message.role === 'user' && convo.messages.every((m) => m.role !== 'user')
          const updatedConvo: Conversation = {
            ...convo,
            title: isFirstUserMessage ? deriveTitle(message.text) : convo.title,
            messages: [...convo.messages, message],
            updatedAt: now,
          }

          return {
            conversations: conversations.map((c) => (c.id === updatedConvo.id ? updatedConvo : c)),
            activeConversationId,
          }
        }),

      // Finds the message by id across ALL conversations, not just the
      // currently active one — a streamed response must keep updating even
      // if the user switches to a different conversation mid-stream (as any
      // real chat app allows). Message ids are globally unique (crypto.
      // randomUUID()), so this is unambiguous.
      updateMessage: (id, patch) =>
        set((state) => ({
          conversations: state.conversations.map((c) =>
            c.messages.some((m) => m.id === id)
              ? { ...c, messages: c.messages.map((m) => (m.id === id ? { ...m, ...patch } : m)) }
              : c
          ),
        })),

      getActiveMessages: () => {
        const state = get()
        return state.conversations.find((c) => c.id === state.activeConversationId)?.messages ?? []
      },

      newConversation: () => set({ activeConversationId: null }),

      switchConversation: (id) => set({ activeConversationId: id }),

      deleteConversation: (id) =>
        set((state) => {
          const conversations = state.conversations.filter((c) => c.id !== id)
          const activeConversationId =
            state.activeConversationId === id ? (conversations[0]?.id ?? null) : state.activeConversationId
          return { conversations, activeConversationId }
        }),
    }),
    {
      name: 'leo_chat_session',
      version: 1,
      // Migrates the old single-thread shape ({ messages: ChatMessage[] })
      // into the new multi-conversation shape — without this, upgrading
      // would silently drop every existing user's chat history on next load.
      migrate: (persisted) => {
        const old = persisted as { messages?: ChatMessage[] } | undefined
        if (!old?.messages || old.messages.length === 0) {
          return { conversations: [], activeConversationId: null }
        }
        const now = new Date().toISOString()
        const firstUser = old.messages.find((m) => m.role === 'user')
        const convo: Conversation = {
          id: crypto.randomUUID(),
          title: deriveTitle(firstUser?.text ?? ''),
          messages: old.messages,
          createdAt: old.messages[0]?.createdAt ?? now,
          updatedAt: now,
        }
        return { conversations: [convo], activeConversationId: convo.id }
      },
      // Runs only on the write-to-localStorage path — the live in-memory
      // store (returned by getState()) keeps full attachment bytes, so
      // multi-turn Q&A about a PDF within the same session is unaffected.
      // Only what actually hits disk gets the bytes stripped.
      partialize: (state): PersistedChatState => ({
        activeConversationId: state.activeConversationId,
        conversations: state.conversations.map((c) => ({
          ...c,
          messages: c.messages.map((m) => ({
            ...m,
            imagePreview: undefined,
            attachments: m.attachments?.map((a) => ({ ...a, base64: undefined })),
          })),
        })),
      }),
    }
  )
)

/**
 * Plain localStorage, no fake "secure" wrapper — Keychain genuinely is more
 * secure at rest than anything a browser can offer, and the Settings UI
 * says so outright rather than implying parity with native.
 */
const API_KEY_STORAGE_KEY = 'leo_claude_api_key'

export function loadStoredApiKey(): string {
  return localStorage.getItem(API_KEY_STORAGE_KEY) ?? ''
}

export function storeApiKey(key: string): void {
  if (key) localStorage.setItem(API_KEY_STORAGE_KEY, key)
  else localStorage.removeItem(API_KEY_STORAGE_KEY)
}
