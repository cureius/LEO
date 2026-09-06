import Foundation

// MARK: - Model

/// Real, current Anthropic model IDs — kept identical to
/// apps/web/src/ai/models.ts's `ClaudeModel`, which already went through this
/// same update (its own comment used to flag these Swift constants as "one
/// generation behind"; that's fixed now, on both sides).
public enum ClaudeModel: String, Sendable, Codable {
    case opus47   = "claude-opus-4-8"
    case sonnet46 = "claude-sonnet-5"
    case haiku45  = "claude-haiku-4-5-20251001"
}

// MARK: - Message roles

public enum MessageRole: String, Codable, Sendable {
    case user, assistant
}

// MARK: - Content blocks

public struct TextBlock: Codable, Sendable {
    public let type: String       // "text"
    public let text: String
    public var cacheControl: CacheControl?

    public init(text: String, cache: Bool = false) {
        self.type = "text"
        self.text = text
        self.cacheControl = cache ? .ephemeral : nil
    }

    enum CodingKeys: String, CodingKey {
        case type, text, cacheControl = "cache_control"
    }
}

public struct CacheControl: Codable, Sendable {
    public let type: String
    public static let ephemeral = CacheControl(type: "ephemeral")
}

public struct ToolUseBlock: Codable, Sendable {
    public let type: String       // "tool_use"
    public let id: String
    public let name: String
    public let input: JSONValue
}

public struct ImageBlock: Codable, Sendable {
    public let type: String       // "image"
    public let source: ImageSource

    public init(jpegData: Data) {
        self.type = "image"
        self.source = ImageSource(type: "base64", mediaType: "image/jpeg", data: jpegData.base64EncodedString())
    }

    public struct ImageSource: Codable, Sendable {
        public let type: String         // "base64"
        public let mediaType: String    // "image/jpeg"
        public let data: String         // base64 string

        enum CodingKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
        }
    }
}

/// PDF (or other supported document) attachment — Claude reads it natively
/// (text, tables, layout, embedded images), no client-side extraction needed.
/// Mirrors apps/web/src/ai/models.ts's `document` ContentBlock, which already
/// has this working; native previously had no document type at all.
public struct DocumentBlock: Codable, Sendable {
    public let type: String       // "document"
    public let source: DocumentSource

    public init(pdfData: Data) {
        self.type = "document"
        self.source = DocumentSource(type: "base64", mediaType: "application/pdf", data: pdfData.base64EncodedString())
    }

    public struct DocumentSource: Codable, Sendable {
        public let type: String         // "base64"
        public let mediaType: String    // "application/pdf"
        public let data: String         // base64 string

        enum CodingKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
        }
    }
}

public struct ToolResultBlock: Codable, Sendable {
    public let type: String       // "tool_result"
    public let toolUseId: String
    public let content: String
    public var isError: Bool?

    public init(toolUseId: String, content: String, isError: Bool? = nil) {
        self.type = "tool_result"
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }

    enum CodingKeys: String, CodingKey {
        case type, content, isError = "is_error"
        case toolUseId = "tool_use_id"
    }
}

// MARK: - Message

public enum ContentBlock: Sendable {
    case text(TextBlock)
    case image(ImageBlock)
    case document(DocumentBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
}

extension ContentBlock: Encodable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let b):       try b.encode(to: encoder)
        case .image(let b):      try b.encode(to: encoder)
        case .document(let b):   try b.encode(to: encoder)
        case .toolUse(let b):    try b.encode(to: encoder)
        case .toolResult(let b): try b.encode(to: encoder)
        }
    }
}

extension ContentBlock: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":        self = .text(try TextBlock(from: decoder))
        case "document":    self = .document(try DocumentBlock(from: decoder))
        case "image":       self = .image(try ImageBlock(from: decoder))
        case "tool_use":    self = .toolUse(try ToolUseBlock(from: decoder))
        case "tool_result": self = .toolResult(try ToolResultBlock(from: decoder))
        default:            self = .text(TextBlock(text: ""))
        }
    }
    private enum TypeKey: String, CodingKey { case type }
}

public struct Message: Codable, Sendable {
    public let role: MessageRole
    public let content: [ContentBlock]

    public init(role: MessageRole, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String, cache: Bool = false) -> Message {
        Message(role: .user, content: [.text(TextBlock(text: text, cache: cache))])
    }

    public static func assistant(_ text: String) -> Message {
        Message(role: .assistant, content: [.text(TextBlock(text: text))])
    }
}

// MARK: - System message

public struct SystemBlock: Codable, Sendable {
    public let type: String
    public let text: String
    public var cacheControl: CacheControl?

    public init(text: String, cache: Bool = false) {
        self.type = "text"
        self.text = text
        self.cacheControl = cache ? .ephemeral : nil
    }

    enum CodingKeys: String, CodingKey {
        case type, text, cacheControl = "cache_control"
    }
}

// MARK: - Tool definition

public struct ToolDefinition: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONObject

    public init(name: String, description: String, inputSchema: JSONObject) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

// MARK: - Response

public struct ClaudeResponse: Codable, Sendable {
    public let id: String
    public let type: String
    public let role: MessageRole
    public let content: [ContentBlock]
    public let model: String
    public let stopReason: String?
    public let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model, usage
        case stopReason = "stop_reason"
    }

    public struct Usage: Codable, Sendable {
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheCreationInputTokens: Int?
        public let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}

// MARK: - Streaming events

public enum StreamEvent: Sendable {
    case messageStart(id: String, model: String)
    case contentBlockDelta(index: Int, text: String)
    case toolUse(id: String, name: String, inputJSON: String)
    case messageStop(stopReason: String, usage: ClaudeResponse.Usage?)
    case error(String)
}

// MARK: - Errors

public enum ClaudeError: Error, LocalizedError, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case serverError(status: Int)
    case malformedResponse(String)
    case missingAPIKey

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Claude API key found. Go to Settings → AI → Add API key to enable Ask LEO."
        case .unauthorized:
            return "Invalid API key. Check your key in Settings → AI → Update API key."
        case .rateLimited(let after):
            if let after { return "Too many requests. Try again in \(Int(after))s." }
            return "Too many requests. Please wait a moment and try again."
        case .timeout:
            return "Request timed out. Check your connection and try again."
        case .serverError(let status):
            return "Claude API error (HTTP \(status)). Try again in a moment."
        case .malformedResponse(let detail):
            return "Unexpected response from Claude: \(detail)"
        }
    }
}

// MARK: - JSONValue (generic JSON tree)

public enum JSONValue: Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self)  { self = .string(s); return }
        if let n = try? c.decode(Double.self)  { self = .number(n); return }
        if let b = try? c.decode(Bool.self)    { self = .bool(b);   return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        self = .null
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a):  try c.encode(a)
        case .null:          try c.encodeNil()
        }
    }
}

public typealias JSONObject = [String: JSONValue]
