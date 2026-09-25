import Testing
import Foundation
@testable import DynamicNotch

// MARK: - Helpers

private func event(_ trigger: TriggerID, _ payload: [String: ExtensionValue] = [:]) -> ExtensionTriggerEvent {
    ExtensionTriggerEvent(id: trigger, payload: payload)
}

/// The same encoder/decoder configuration ExtensionPersistenceService uses, so Codable
/// tests here exercise the same wire format the app actually persists.
private func persistenceEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

private func persistenceDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

// MARK: - MatchCondition

@Suite("MatchCondition.isSatisfied")
struct MatchConditionTests {

    @Test("A missing payload field never satisfies any operator")
    func missingFieldNeverSatisfies() {
        let condition = MatchCondition(field: "level", op: .equals, value: .int(50))
        #expect(!condition.isSatisfied(by: [:]))
    }

    @Test("equals/notEquals compare the ExtensionValue directly, so a type mismatch is never equal")
    func equalsIsTypeStrict() {
        let equalsInt = MatchCondition(field: "level", op: .equals, value: .int(1))
        #expect(!equalsInt.isSatisfied(by: ["level": .double(1.0)]), "int(1) and double(1.0) are different ExtensionValue cases")
        #expect(equalsInt.isSatisfied(by: ["level": .int(1)]))

        let notEquals = MatchCondition(field: "level", op: .notEquals, value: .int(1))
        #expect(notEquals.isSatisfied(by: ["level": .double(1.0)]), "A type mismatch counts as \"not equal\"")
        #expect(!notEquals.isSatisfied(by: ["level": .int(1)]))
    }

    @Test("contains matches stringValue case-insensitively, including numeric substrings")
    func containsIsCaseInsensitiveOnStringValue() {
        let condition = MatchCondition(field: "name", op: .contains, value: .string("XCODE"))
        #expect(condition.isSatisfied(by: ["name": .string("Xcode Helper")]))
        #expect(!condition.isSatisfied(by: ["name": .string("Safari")]))

        let numeric = MatchCondition(field: "level", op: .contains, value: .string("4"))
        #expect(numeric.isSatisfied(by: ["level": .int(42)]), "stringValue(42) is \"42\", which contains \"4\"")
    }

    @Test("Numeric operators compare doubleValue, so numeric strings count", arguments: [
        (MatchCondition.Operator.greaterThan, 3.0, 5.0, true),
        (MatchCondition.Operator.greaterThan, 5.0, 3.0, false),
        (MatchCondition.Operator.greaterThanOrEqual, 5.0, 5.0, true),
        (MatchCondition.Operator.lessThan, 5.0, 3.0, true),
        (MatchCondition.Operator.lessThanOrEqual, 5.0, 5.0, true),
    ])
    func numericOperators(op: MatchCondition.Operator, threshold: Double, actual: Double, expected: Bool) {
        let condition = MatchCondition(field: "level", op: op, value: .double(threshold))
        #expect(condition.isSatisfied(by: ["level": .string(String(actual))]) == expected, "A numeric string payload value should compare the same as a real number")
    }

    @Test("Numeric operators fail closed when either side isn't numeric")
    func numericOperatorsFailClosedOnNonNumeric() {
        let condition = MatchCondition(field: "name", op: .greaterThan, value: .double(5))
        #expect(!condition.isSatisfied(by: ["name": .string("not-a-number")]))
    }
}

// MARK: - ExtensionActionStep

@Suite("ExtensionActionStep decoding")
struct ExtensionActionStepTests {

    @Test("payload defaults to empty when omitted from the wire format")
    func payloadDefaultsToEmpty() throws {
        let json = Data(#"{"action":"volume.set"}"#.utf8)
        let step = try JSONDecoder().decode(ExtensionActionStep.self, from: json)
        #expect(step.action == .volumeSet)
        #expect(step.payload.isEmpty)
    }
}

// MARK: - ExtensionRule

@Suite("ExtensionRule decoding and matching")
struct ExtensionRuleTests {

    @Test("Only trigger and actions are required on the wire — everything else gets a default")
    func minimalRuleFillsInDefaults() throws {
        let json = Data(#"""
        { "trigger": "battery.levelChanged", "actions": [{ "action": "volume.set", "payload": { "level": 0.5 } }] }
        """#.utf8)
        let rule = try JSONDecoder().decode(ExtensionRule.self, from: json)
        #expect(rule.trigger == .batteryLevelChanged)
        #expect(rule.conditions.isEmpty)
        #expect(rule.prerequisites.isEmpty)
        #expect(rule.mode == .entry)
        #expect(rule.sustainFor == nil)
        #expect(rule.actions == [ExtensionActionStep(action: .volumeSet, payload: ["level": .double(0.5)])])
    }

    @Test("A missing trigger fails to decode")
    func missingTriggerThrows() {
        let json = Data(#"{ "actions": [{ "action": "volume.set" }] }"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ExtensionRule.self, from: json)
        }
    }

    @Test("A missing actions array fails to decode")
    func missingActionsThrows() {
        let json = Data(#"{ "trigger": "battery.levelChanged" }"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ExtensionRule.self, from: json)
        }
    }

    @Test("An unknown trigger id fails to decode rather than being silently dropped")
    func unknownTriggerIDThrows() {
        let json = Data(#"{ "trigger": "not.a.real.trigger", "actions": [] }"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ExtensionRule.self, from: json)
        }
    }

    @Test("An empty actions array is accepted")
    func emptyActionsArrayIsAccepted() throws {
        let json = Data(#"{ "trigger": "battery.levelChanged", "actions": [] }"#.utf8)
        let rule = try JSONDecoder().decode(ExtensionRule.self, from: json)
        #expect(rule.actions.isEmpty)
    }

    @Test("matches() requires the trigger id to be equal and every condition to pass (AND)")
    func matchesANDsConditions() {
        let rule = ExtensionRule(
            trigger: .appFrontmostChanged,
            conditions: [
                MatchCondition(field: "name", op: .contains, value: .string("Xcode")),
                MatchCondition(field: "bundleIdentifier", op: .equals, value: .string("com.apple.dt.Xcode")),
            ],
            actions: [ExtensionActionStep(action: .caffeineSet, payload: ["enabled": .bool(true)])]
        )

        let bothMatch = event(.appFrontmostChanged, ["name": .string("Xcode"), "bundleIdentifier": .string("com.apple.dt.Xcode")])
        #expect(rule.matches(bothMatch))

        let onlyNameMatches = event(.appFrontmostChanged, ["name": .string("Xcode"), "bundleIdentifier": .string("com.something.else")])
        #expect(!rule.matches(onlyNameMatches), "Both conditions must pass, not just one")

        let wrongTrigger = event(.appLaunched, ["name": .string("Xcode"), "bundleIdentifier": .string("com.apple.dt.Xcode")])
        #expect(!rule.matches(wrongTrigger))
    }

    @Test("Empty conditions match every occurrence of the trigger")
    func emptyConditionsMatchEveryOccurrence() {
        let rule = ExtensionRule(trigger: .sleepDidWake, actions: [])
        #expect(rule.matches(event(.sleepDidWake)))
        #expect(rule.matches(event(.sleepDidWake, ["anything": .string("goes")])))
    }
}

// MARK: - ExtensionRecord

@Suite("ExtensionRecord persistence round-trip")
struct ExtensionRecordTests {

    @Test("A record round-trips through the same encoder/decoder configuration the app persists with")
    func roundTripsThroughPersistenceEncoding() throws {
        // A whole-second date: the default ISO8601 formatter this encoder/decoder pair uses
        // has no fractional-second component, so Date() here would lose precision on decode
        // and make the round-trip comparison fail for a reason that has nothing to do with
        // ExtensionRecord itself.
        let record = ExtensionRecord(
            name: "Xcode Focus",
            summary: "Turns Caffeine on while Xcode is frontmost.",
            enabled: true,
            rules: [
                ExtensionRule(
                    trigger: .appFrontmostChanged,
                    conditions: [MatchCondition(field: "name", op: .contains, value: .string("Xcode"))],
                    actions: [ExtensionActionStep(action: .caffeineSet, payload: ["enabled": .bool(true)])],
                    prerequisites: [ExtensionActionStep(action: .caffeineSet, payload: ["enabled": .bool(false)])],
                    mode: .entry,
                    sustainFor: 7200
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try persistenceEncoder().encode(record)
        let restored = try persistenceDecoder().decode(ExtensionRecord.self, from: data)
        #expect(restored == record)
    }

    @Test("Every field is required when decoding a stored record — none of the property defaults apply")
    func decodingRequiresEveryField() {
        let json = Data(#"{ "name": "Missing everything else" }"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try persistenceDecoder().decode(ExtensionRecord.self, from: json)
        }
    }
}
