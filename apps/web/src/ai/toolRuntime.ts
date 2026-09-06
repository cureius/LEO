import type { ToolDefinition } from './models'

/**
 * Port of ToolRuntime.swift, simplified: Swift's `ToolContext` exists to
 * inject a separate SwiftData persistence layer into each tool call. Web has
 * no such split — the Zustand store (sync/store.ts) *is* the single source
 * of truth, so tools just import and call it directly. No context object to
 * thread through.
 */
type ToolEntry = {
  definition: ToolDefinition
  run: (input: unknown) => Promise<unknown>
}

const tools = new Map<string, ToolEntry>()

export function registerTool(definition: ToolDefinition, run: (input: unknown) => Promise<unknown>) {
  tools.set(definition.name, { definition, run })
}

export function toolDefinitions(): ToolDefinition[] {
  return Array.from(tools.values()).map((t) => t.definition)
}

/** Execute a tool call from the model, returning the result as a JSON string — mirrors ToolRuntime.execute()'s (result, isError) shape. */
export async function executeTool(name: string, inputJSON: string): Promise<{ result: string; isError: boolean }> {
  const entry = tools.get(name)
  if (!entry) {
    return { result: JSON.stringify({ error: `Tool not found: ${name}` }), isError: true }
  }
  try {
    const input = JSON.parse(inputJSON)
    const output = await entry.run(input)
    return { result: JSON.stringify(output), isError: false }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return { result: JSON.stringify({ error: message }), isError: true }
  }
}

/** For tests: drop all registered tools so each test file starts clean. */
export function _clearToolsForTests() {
  tools.clear()
}
