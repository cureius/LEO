import { describe, expect, it, beforeEach } from 'vitest'
import { registerTool, toolDefinitions, executeTool, _clearToolsForTests } from '../toolRuntime'

beforeEach(() => {
  _clearToolsForTests()
})

describe('toolRuntime', () => {
  it('registers a tool and exposes its definition', () => {
    registerTool({ name: 'ping', description: 'test', input_schema: { type: 'object', properties: {} } }, async () => ({ pong: true }))
    expect(toolDefinitions()).toEqual([{ name: 'ping', description: 'test', input_schema: { type: 'object', properties: {} } }])
  })

  it('executeTool returns the tool\'s output as a JSON string, isError=false', async () => {
    registerTool({ name: 'echo', description: '', input_schema: {} }, async (input) => input)
    const { result, isError } = await executeTool('echo', JSON.stringify({ hello: 'world' }))
    expect(isError).toBe(false)
    expect(JSON.parse(result)).toEqual({ hello: 'world' })
  })

  it('executeTool returns an error result for an unregistered tool name, never throws', async () => {
    const { result, isError } = await executeTool('does_not_exist', '{}')
    expect(isError).toBe(true)
    expect(JSON.parse(result).error).toContain('does_not_exist')
  })

  it('executeTool catches a tool that throws and returns isError=true rather than propagating', async () => {
    registerTool({ name: 'boom', description: '', input_schema: {} }, async () => {
      throw new Error('kaboom')
    })
    const { result, isError } = await executeTool('boom', '{}')
    expect(isError).toBe(true)
    expect(JSON.parse(result).error).toBe('kaboom')
  })

  it('executeTool catches malformed input JSON rather than throwing', async () => {
    registerTool({ name: 'strict', description: '', input_schema: {} }, async (input) => input)
    const { isError } = await executeTool('strict', '{not valid json')
    expect(isError).toBe(true)
  })
})
