//
//  ExtensionGenerationService.swift
//  boringNotch
//
//  On-device generation: turns a plain-English description into the same
//  rules JSON the manual editor already validates. This is the primary way
//  to fill out an extension when it's available; hand-typed JSON and pasting
//  a response from an external chatbot are the fallbacks, and all three feed
//  the exact same downstream validation in ExtensionEditorView — generation
//  only ever produces a first draft, never something pre-trusted.
//
//  Gated behind #if canImport(FoundationModels) and @available(macOS 26, *)
//  since this project's deployment target is macOS 15 and still ships an
//  Intel slice — on-device generation is unavailable for a real chunk of the
//  install base, not just a theoretical edge case, so everything here must
//  degrade to a clear "why" rather than assume availability.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
enum ExtensionGenerationStatus: String {
    case ok
    case needsClarification
    case cannotBuild
}

@available(macOS 26.0, *)
@Generable
struct ExtensionGenerationOutput {
    @Guide(description: "\"ok\" if you could build this, \"needsClarification\" if the request is ambiguous in a way that changes behavior, \"cannotBuild\" if it needs a trigger or action that isn't in the list below")
    var status: ExtensionGenerationStatus

    @Guide(description: "Only when status is needsClarification: one short question. Empty string otherwise.")
    var clarifyingQuestion: String

    @Guide(description: "Only when status is cannotBuild: one sentence explaining what's missing. Empty string otherwise.")
    var reason: String

    @Guide(description: "A short, human-friendly name for the extension, e.g. \"Low battery alert\". Empty string if status is not ok.")
    var name: String

    @Guide(description: "One plain-English sentence describing what it does. Empty string if status is not ok.")
    var summary: String

    @Guide(description: "A JSON array of rule objects, as a string, using only the trigger/action ids from the list in the instructions and matching the exact shape described there. \"[]\" if status is not ok.")
    var rulesJSON: String
}
#endif

enum ExtensionGenerationAvailability: Equatable {
    case available
    case unavailable(reason: String)
}

enum ExtensionGenerationError: Error, LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        }
    }
}

/// Plain-Swift mirror of `ExtensionGenerationOutput` so `ExtensionEditorView`
/// never has to import FoundationModels or deal with its availability guards.
struct ExtensionGenerationResult {
    let status: String
    let clarifyingQuestion: String
    let reason: String
    let name: String
    let summary: String
    let rulesJSON: String
}

enum ExtensionGenerationService {
    static var availability: ExtensionGenerationAvailability {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            return .unavailable(reason: "On-device generation needs a newer macOS. Write or paste JSON instead.")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence isn't turned on. Enable it in System Settings, or write/paste JSON instead.")
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This Mac doesn't support Apple Intelligence. Write or paste JSON instead.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "The on-device model hasn't finished downloading yet. Write or paste JSON instead, or try again shortly.")
        case .unavailable:
            return .unavailable(reason: "On-device generation isn't available right now. Write or paste JSON instead.")
        }
        #else
        return .unavailable(reason: "On-device generation isn't available in this build. Write or paste JSON instead.")
        #endif
    }

    static func generate(request: String, currentRulesJSON: String) async throws -> ExtensionGenerationResult {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            throw ExtensionGenerationError.unavailable("On-device generation needs a newer macOS.")
        }
        guard case .available = SystemLanguageModel.default.availability else {
            throw ExtensionGenerationError.unavailable("On-device generation isn't available right now.")
        }

        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        Build this extension: "\(request)"

        Current rules, if this is a follow-up edit (ignore if starting fresh):
        \(currentRulesJSON)
        """
        let response = try await session.respond(to: prompt, generating: ExtensionGenerationOutput.self)
        let output = response.content
        return ExtensionGenerationResult(
            status: output.status.rawValue,
            clarifyingQuestion: output.clarifyingQuestion,
            reason: output.reason,
            name: output.name,
            summary: output.summary,
            rulesJSON: output.rulesJSON
        )
        #else
        throw ExtensionGenerationError.unavailable("On-device generation isn't available in this build.")
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static var instructions: String {
        """
        You are the Extension Builder for DynamicNotch, a Mac app. An extension is a \
        JSON array of rules, each with this shape:

        { "trigger": "<id>", "conditions": [{ "field": "<payload field>", "op": "equals|notEquals|greaterThan|greaterThanOrEqual|lessThan|lessThanOrEqual|contains", "value": <string, number, or bool> }], "action": "<id>", "payload": { "...": "fields the action expects" }, "revertAction": "<id, optional>", "revertPayload": { "...": "optional" } }

        `conditions` is optional — omit it to match every occurrence of the trigger; entries \
        are ANDed together. `revertAction`/`revertPayload` are optional: only include them if \
        the action should automatically be undone the next time the trigger fires again and the \
        conditions no longer match.

        Only use trigger and action ids from this exact list — never invent one:

        \(CapabilityRegistry.referenceText())
        """
    }
    #endif
}
