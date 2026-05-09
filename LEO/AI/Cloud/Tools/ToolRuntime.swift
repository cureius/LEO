import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "tool-runtime")

// MARK: - Tool context

/// Dependencies injected into each tool execution.
struct ToolContext: Sendable {
    let itemRepository: ItemRepository
    let calendar: Calendar
}

// MARK: - Erasure protocol

protocol AnyTool: Sendable {
    var definition: ToolDefinition { get }
    func run(inputJSON: String, context: ToolContext) async throws -> String
}

// MARK: - Typed tool protocol

protocol LEOTool: AnyTool {
    associatedtype Input: Decodable & Sendable
    associatedtype Output: Encodable & Sendable
    var definition: ToolDefinition { get }
    func run(_ input: Input, context: ToolContext) async throws -> Output
}

extension LEOTool {
    func run(inputJSON: String, context: ToolContext) async throws -> String {
        let data = Data(inputJSON.utf8)
        let input = try JSONDecoder().decode(Input.self, from: data)
        let output = try await run(input, context: context)
        let outData = try JSONEncoder().encode(output)
        return String(data: outData, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Tool runtime

/// Registers tools, executes them on behalf of the AI, returns results.
actor ToolRuntime {
    private var tools: [String: AnyTool] = [:]
    private let context: ToolContext

    init(context: ToolContext) {
        self.context = context
        register(GetTodayTool())
        register(GetWeekTool())
        register(FindFreeSlotsTool())
        register(GetItemTool())
        register(ProposeRescheduleTool())
        register(ProposeAddTool())
        register(ProposeCancelTool())
    }

    func register(_ tool: some AnyTool) {
        tools[tool.definition.name] = tool
    }

    var toolDefinitions: [ToolDefinition] {
        Array(tools.values.map(\.definition))
    }

    /// Execute a tool call from the model, returning the result as a JSON string.
    func execute(name: String, inputJSON: String) async -> (result: String, isError: Bool) {
        guard let tool = tools[name] else {
            logger.warning("Tool '\(name)' not found")
            return ("{\"error\": \"Tool not found: \(name)\"}", true)
        }
        do {
            let result = try await tool.run(inputJSON: inputJSON, context: context)
            logger.info("Tool '\(name)' executed OK")
            return (result, false)
        } catch {
            logger.error("Tool '\(name)' failed: \(error)")
            return ("{\"error\": \"\(error.localizedDescription)\"}", true)
        }
    }
}
