//
//  ExtensionTypes.swift
//  boringNotch
//
//  Shared value types for the extensions system (CapabilityRegistry,
//  ExtensionEventBus, ExtensionActionExecutor). Kept dependency-free so the
//  same types can later be reused by persistence and the JSON editor.
//

import Foundation

/// A dynamically-typed payload value. Used instead of `Any` so trigger
/// payloads and action arguments stay `Codable` and `Equatable` end to end —
/// this is what eventually gets round-tripped through JSON when extensions
/// are stored, hand-edited, or pasted in from an external chatbot.
enum ExtensionValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
}

extension ExtensionValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "Unsupported ExtensionValue"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension ExtensionValue {
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        case .string(let value): return Double(value)
        case .bool, .null: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        case .string(let value): return Int(value)
        case .bool, .null: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value): return Bool(value)
        case .int, .double, .null: return nil
        }
    }
}

/// A normalized occurrence of one of the `TriggerID`s in `CapabilityRegistry`,
/// published by `ExtensionEventBus`.
struct ExtensionTriggerEvent: Equatable {
    let id: TriggerID
    let payload: [String: ExtensionValue]
    let date: Date

    init(id: TriggerID, payload: [String: ExtensionValue] = [:], date: Date = Date()) {
        self.id = id
        self.payload = payload
        self.date = date
    }
}

/// Result of running one `ActionID` through `ExtensionActionExecutor`.
struct ExtensionActionResult: Equatable {
    let success: Bool
    let message: String?

    static func ok(_ message: String? = nil) -> Self { .init(success: true, message: message) }
    static func failed(_ message: String) -> Self { .init(success: false, message: message) }
}
