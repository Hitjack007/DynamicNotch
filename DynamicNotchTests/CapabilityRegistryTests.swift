import Testing
@testable import DynamicNotch

// MARK: - Tests

@Suite("CapabilityRegistry completeness and consistency")
struct CapabilityRegistryTests {

    @Test("Every TriggerID case has exactly one descriptor")
    func everyTriggerHasExactlyOneDescriptor() {
        for id in TriggerID.allCases {
            let matches = CapabilityRegistry.triggers.filter { $0.id == id }
            #expect(matches.count == 1, "\(id.rawValue) should have exactly one TriggerDescriptor, found \(matches.count)")
        }
        #expect(CapabilityRegistry.triggers.count == TriggerID.allCases.count, "There should be no descriptor for a trigger id that no longer exists")
    }

    @Test("Every ActionID case has exactly one descriptor")
    func everyActionHasExactlyOneDescriptor() {
        for id in ActionID.allCases {
            let matches = CapabilityRegistry.actions.filter { $0.id == id }
            #expect(matches.count == 1, "\(id.rawValue) should have exactly one ActionDescriptor, found \(matches.count)")
        }
        #expect(CapabilityRegistry.actions.count == ActionID.allCases.count, "There should be no descriptor for an action id that no longer exists")
    }

    @Test("trigger(_:) and action(_:) never force-unwrap-crash for any known id")
    func lookupsNeverCrash() {
        for id in TriggerID.allCases {
            #expect(CapabilityRegistry.trigger(id).id == id)
        }
        for id in ActionID.allCases {
            #expect(CapabilityRegistry.action(id).id == id)
        }
    }

    @Test("prerequisiteEligible agrees with the ids ExtensionActionExecutor.currentlyMatches hard-codes as non-eligible")
    func prerequisiteEligibilityMatchesExecutorSwitch() {
        let nonEligibleInExecutor: Set<ActionID> = [
            .notificationRequest, .notificationShowInApp, .sneakPeekShow,
            .mediaNextTrack, .mediaPreviousTrack, .shortcutRun,
            .audioOutputSet, .volumeSet, .brightnessSet, .clipboardSetText,
        ]
        for descriptor in CapabilityRegistry.actions {
            let isEligible = descriptor.prerequisiteEligible
            let executorConsidersEligible = !nonEligibleInExecutor.contains(descriptor.id)
            #expect(isEligible == executorConsidersEligible, "\(descriptor.id.rawValue): CapabilityRegistry says prerequisiteEligible=\(isEligible), but ExtensionActionExecutor.currentlyMatches disagrees")
        }
    }

    @Test("referenceText() mentions every trigger and action id, with the prerequisite suffix only on eligible actions")
    func referenceTextIsComplete() {
        let text = CapabilityRegistry.referenceText()

        for descriptor in CapabilityRegistry.triggers {
            #expect(text.contains(descriptor.id.rawValue))
        }
        for descriptor in CapabilityRegistry.actions {
            #expect(text.contains(descriptor.id.rawValue))
            let line = text.split(separator: "\n").first { $0.contains("- \(descriptor.id.rawValue):") }
            #expect(line != nil)
            if let line {
                #expect(line.contains("(usable as a prerequisite)") == descriptor.prerequisiteEligible, "\(descriptor.id.rawValue) prerequisite suffix should track prerequisiteEligible")
            }
        }
    }

    @Test("chatbotPrompt embeds the request text and the caller's current rules JSON verbatim")
    func chatbotPromptEmbedsInputs() {
        let prompt = CapabilityRegistry.chatbotPrompt(currentRulesJSON: "[{\"marker\":\"unique-rules-json\"}]", request: "turn on Do Not Disturb at night")
        #expect(prompt.contains("turn on Do Not Disturb at night"))
        #expect(prompt.contains("unique-rules-json"))
    }

    @Test("payloadSchema's keys match the leading \"key:\" in each descriptor's payloadFields doc strings")
    func payloadSchemaKeysMatchDocStrings() {
        func keys(from docStrings: [String]) -> Set<String> {
            Set(docStrings.compactMap { $0.components(separatedBy: ": ").first })
        }
        for descriptor in CapabilityRegistry.triggers {
            let docKeys = keys(from: descriptor.payloadFields)
            let schemaKeys = Set(descriptor.payloadSchema.map(\.key))
            #expect(docKeys == schemaKeys, "\(descriptor.id.rawValue): payloadSchema keys \(schemaKeys) don't match payloadFields doc keys \(docKeys)")
        }
        for descriptor in CapabilityRegistry.actions {
            let docKeys = keys(from: descriptor.payloadFields)
            let schemaKeys = Set(descriptor.payloadSchema.map(\.key))
            #expect(docKeys == schemaKeys, "\(descriptor.id.rawValue): payloadSchema keys \(schemaKeys) don't match payloadFields doc keys \(docKeys)")
        }
    }
}

// MARK: - issues(in:) safety validation

@Suite("CapabilityRegistry.issues(in:) safety validation")
struct CapabilityRegistryIssuesTests {

    @Test("An eligible action with no prerequisite gate is flagged, and clears once one is added")
    func issuesFlagsMissingPrerequisiteGate() {
        var rule = ExtensionRule(trigger: .appFrontmostChanged, actions: [ExtensionActionStep(action: .caffeineSet, payload: ["enabled": .bool(true)])])
        #expect(CapabilityRegistry.issues(in: [rule]).contains { $0.contains("caffeine.set") && $0.contains("needs a prerequisite gate") })

        rule.prerequisites = [ExtensionActionStep(action: .caffeineSet, payload: ["enabled": .bool(false)])]
        #expect(CapabilityRegistry.issues(in: [rule]).isEmpty)
    }

    @Test("A non-eligible action never triggers the prerequisite-gate check")
    func nonEligibleActionNeverFlagged() {
        let rule = ExtensionRule(trigger: .appLaunched, actions: [ExtensionActionStep(action: .notificationRequest, payload: ["title": .string("Hi")])])
        #expect(CapabilityRegistry.issues(in: [rule]).isEmpty)
    }

    @Test("A durationElapsed-triggered rule never needs a prerequisite gate, even with no prerequisites at all")
    func durationElapsedRuleNeverFlagged() {
        // The exact "undo caffeine after Xcode has been idle for an hour" pair a user
        // hand-wrote: the sustainFor entry rule needs its gate (satisfied here), but the
        // durationElapsed rule that undoes it needs none — durationElapsed only fires once
        // per armed timer, so there's nothing recurring for a gate to guard against.
        let entryRule = ExtensionRule(
            trigger: .appFrontmostChanged,
            conditions: [MatchCondition(field: "name", op: .contains, value: .string("Xcode"))],
            actions: [ExtensionActionStep(action: .caffeineSet, payload: ["enabled": .bool(true)])],
            prerequisites: [ExtensionActionStep(action: .caffeineSet, payload: ["enabled": .bool(false)])],
            mode: .entry,
            sustainFor: 3600
        )
        let durationElapsedRule = ExtensionRule(
            trigger: .durationElapsed,
            conditions: [MatchCondition(field: "name", op: .contains, value: .string("Xcode"))],
            actions: [
                ExtensionActionStep(action: .caffeineSet, payload: ["enabled": .bool(false)]),
                ExtensionActionStep(action: .notificationShowInApp, payload: ["title": .string("Xcode Idle"), "message": .string("Caffeine disabled")]),
            ],
            prerequisites: [],
            mode: .entry
        )
        #expect(durationElapsedRule.actionsMissingPrerequisiteGate.isEmpty)
        #expect(CapabilityRegistry.issues(in: [entryRule, durationElapsedRule]).isEmpty)
    }

    @Test("Turning on fanFloorSet with no paired exit rule is flagged, even with its own prerequisite gate satisfied")
    func fanFloorWithoutExitRuleIsFlagged() {
        let rule = ExtensionRule(
            trigger: .appFrontmostChanged,
            actions: [ExtensionActionStep(action: .fanFloorSet, payload: ["enabled": .bool(true), "level": .double(0.8)])],
            prerequisites: [ExtensionActionStep(action: .fanFloorSet, payload: ["enabled": .bool(false)])],
            mode: .entry
        )
        #expect(CapabilityRegistry.actionsRequiringExitRule(in: [rule]) == [.fanFloorSet])
        #expect(CapabilityRegistry.issues(in: [rule]).contains { $0.contains("fan.floorSet") && $0.contains("turns it back off") })
    }

    @Test("A second rule with a matching .exit gate satisfies the fanFloorSet pairing requirement")
    func fanFloorWithExitRuleIsSatisfied() {
        let onRule = ExtensionRule(
            trigger: .appFrontmostChanged,
            actions: [ExtensionActionStep(action: .fanFloorSet, payload: ["enabled": .bool(true), "level": .double(0.8)])],
            prerequisites: [ExtensionActionStep(action: .fanFloorSet, payload: ["enabled": .bool(false)])],
            mode: .entry
        )
        let exitRule = ExtensionRule(
            trigger: .appTerminated,
            actions: [ExtensionActionStep(action: .fanFloorSet, payload: ["enabled": .bool(false)])],
            prerequisites: [ExtensionActionStep(action: .fanFloorSet, payload: ["enabled": .bool(true)])],
            mode: .exit
        )
        #expect(CapabilityRegistry.actionsRequiringExitRule(in: [onRule, exitRule]).isEmpty)
        #expect(CapabilityRegistry.issues(in: [onRule, exitRule]).isEmpty)
    }

    @Test("Turning fanFloorSet off (enabled: false) never requires a paired exit rule")
    func fanFloorTurnedOffNeverFlagged() {
        let rule = ExtensionRule(
            trigger: .appTerminated,
            actions: [ExtensionActionStep(action: .fanFloorSet, payload: ["enabled": .bool(false)])],
            prerequisites: [ExtensionActionStep(action: .fanFloorSet, payload: ["enabled": .bool(true)])]
        )
        #expect(CapabilityRegistry.actionsRequiringExitRule(in: [rule]).isEmpty)
    }
}
