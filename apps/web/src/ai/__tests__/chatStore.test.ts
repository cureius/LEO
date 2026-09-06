import { describe, expect, it, beforeEach } from 'vitest'
import { useChatStore, type ChatMessage } from '../session/chatStore'

function userMsg(text: string): ChatMessage {
  return { id: crypto.randomUUID(), role: 'user', text, createdAt: new Date().toISOString() }
}
function assistantMsg(text = ''): ChatMessage {
  return { id: crypto.randomUUID(), role: 'assistant', text, createdAt: new Date().toISOString() }
}

beforeEach(() => {
  useChatStore.setState({ conversations: [], activeConversationId: null })
})

describe('useChatStore — multi-conversation support', () => {
  it('addMessage lazily creates a conversation on the first message rather than requiring one upfront', () => {
    expect(useChatStore.getState().conversations).toHaveLength(0)
    useChatStore.getState().addMessage(userMsg('Hello'))
    const state = useChatStore.getState()
    expect(state.conversations).toHaveLength(1)
    expect(state.activeConversationId).toBe(state.conversations[0].id)
    expect(state.conversations[0].messages).toHaveLength(1)
  })

  it('derives the conversation title from the first user message, truncated', () => {
    useChatStore.getState().addMessage(userMsg('What is on my schedule today?'))
    expect(useChatStore.getState().conversations[0].title).toBe('What is on my schedule today?')

    useChatStore.setState({ conversations: [], activeConversationId: null })
    const long = 'a'.repeat(80)
    useChatStore.getState().addMessage(userMsg(long))
    const title = useChatStore.getState().conversations[0].title
    expect(title.endsWith('…')).toBe(true)
    expect(title.length).toBeLessThan(long.length)
  })

  it('does not re-derive the title from later messages', () => {
    useChatStore.getState().addMessage(userMsg('First question'))
    useChatStore.getState().addMessage(assistantMsg('An answer'))
    useChatStore.getState().addMessage(userMsg('A completely different follow-up'))
    expect(useChatStore.getState().conversations[0].title).toBe('First question')
  })

  it('newConversation clears the active id without deleting the previous conversation', () => {
    useChatStore.getState().addMessage(userMsg('First chat'))
    const firstId = useChatStore.getState().activeConversationId
    useChatStore.getState().newConversation()
    expect(useChatStore.getState().activeConversationId).toBeNull()
    expect(useChatStore.getState().getActiveMessages()).toEqual([])
    expect(useChatStore.getState().conversations).toHaveLength(1)
    expect(useChatStore.getState().conversations[0].id).toBe(firstId)
  })

  it('newConversation + a new message creates a second, separate conversation', () => {
    useChatStore.getState().addMessage(userMsg('First chat'))
    useChatStore.getState().newConversation()
    useChatStore.getState().addMessage(userMsg('Second chat'))
    const state = useChatStore.getState()
    expect(state.conversations).toHaveLength(2)
    expect(state.getActiveMessages()).toHaveLength(1)
    expect(state.getActiveMessages()[0].text).toBe('Second chat')
  })

  it('switchConversation changes which conversation getActiveMessages reads from', () => {
    useChatStore.getState().addMessage(userMsg('Chat A'))
    const idA = useChatStore.getState().activeConversationId!
    useChatStore.getState().newConversation()
    useChatStore.getState().addMessage(userMsg('Chat B'))

    useChatStore.getState().switchConversation(idA)
    expect(useChatStore.getState().getActiveMessages()[0].text).toBe('Chat A')
  })

  it('deleteConversation removes it and auto-switches to the most recently updated remaining conversation', async () => {
    useChatStore.getState().addMessage(userMsg('Chat A'))
    const idA = useChatStore.getState().activeConversationId!
    await new Promise((r) => setTimeout(r, 2)) // ensure a distinct updatedAt ordering
    useChatStore.getState().newConversation()
    useChatStore.getState().addMessage(userMsg('Chat B'))
    const idB = useChatStore.getState().activeConversationId!

    useChatStore.getState().switchConversation(idA)
    useChatStore.getState().deleteConversation(idA)

    const state = useChatStore.getState()
    expect(state.conversations.find((c) => c.id === idA)).toBeUndefined()
    expect(state.activeConversationId).toBe(idB)
  })

  it('deleteConversation on a non-active conversation leaves the active one untouched', () => {
    useChatStore.getState().addMessage(userMsg('Chat A'))
    const idA = useChatStore.getState().activeConversationId!
    useChatStore.getState().newConversation()
    useChatStore.getState().addMessage(userMsg('Chat B'))
    const idB = useChatStore.getState().activeConversationId!

    useChatStore.getState().deleteConversation(idA)
    expect(useChatStore.getState().activeConversationId).toBe(idB)
    expect(useChatStore.getState().conversations).toHaveLength(1)
  })

  it('updateMessage finds the message by id even if a different conversation is now active — a background stream must keep updating after the user switches away', () => {
    useChatStore.getState().addMessage(userMsg('Chat A'))
    const msgA = useChatStore.getState().getActiveMessages()[0]
    const idA = useChatStore.getState().activeConversationId!

    useChatStore.getState().newConversation()
    useChatStore.getState().addMessage(userMsg('Chat B'))

    useChatStore.getState().updateMessage(msgA.id, { text: 'streamed content that arrived after switching away' })
    expect(useChatStore.getState().conversations.find((c) => c.id === idA)!.messages[0].text).toBe(
      'streamed content that arrived after switching away'
    )
  })
})
