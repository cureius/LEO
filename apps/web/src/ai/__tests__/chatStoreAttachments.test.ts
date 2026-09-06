import { describe, expect, it, beforeEach } from 'vitest'
import { useChatStore, type ChatMessage } from '../session/chatStore'

function userMsgWithAttachment(text: string, base64 = 'ZmFrZS1wZGYtYnl0ZXM='): ChatMessage {
  return {
    id: crypto.randomUUID(),
    role: 'user',
    text,
    createdAt: new Date().toISOString(),
    attachments: [{ id: crypto.randomUUID(), name: 'invoice.pdf', mimeType: 'application/pdf', sizeBytes: 12345, kind: 'pdf', base64 }],
  }
}

beforeEach(() => {
  useChatStore.setState({ conversations: [], activeConversationId: null })
})

describe('useChatStore — attachment persistence', () => {
  it('keeps the full base64 payload in the live in-memory store', () => {
    useChatStore.getState().addMessage(userMsgWithAttachment('what does this say?'))
    const messages = useChatStore.getState().getActiveMessages()
    expect(messages[0].attachments?.[0].base64).toBe('ZmFrZS1wZGYtYnl0ZXM=')
    expect(messages[0].attachments?.[0].name).toBe('invoice.pdf')
  })

  it('strips base64 bytes (but keeps name/mimeType/size) on the path that actually writes to localStorage — a multi-MB PDF must never sit in persisted storage forever', () => {
    useChatStore.getState().addMessage(userMsgWithAttachment('what does this say?'))

    const partialize = useChatStore.persist.getOptions().partialize
    expect(partialize).toBeTypeOf('function')
    const persisted = partialize!(useChatStore.getState())

    const persistedAttachment = persisted.conversations[0].messages[0].attachments?.[0]
    expect(persistedAttachment?.base64).toBeUndefined()
    expect(persistedAttachment?.name).toBe('invoice.pdf')
    expect(persistedAttachment?.mimeType).toBe('application/pdf')
    expect(persistedAttachment?.sizeBytes).toBe(12345)
  })

  it('a message with no attachments is untouched by partialize', () => {
    useChatStore.getState().addMessage({ id: crypto.randomUUID(), role: 'user', text: 'plain message', createdAt: new Date().toISOString() })
    const partialize = useChatStore.persist.getOptions().partialize!
    const persisted = partialize(useChatStore.getState())
    expect(persisted.conversations[0].messages[0].attachments).toBeUndefined()
  })
})
