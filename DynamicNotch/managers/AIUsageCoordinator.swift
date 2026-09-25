//
//  AIUsageCoordinator.swift
//  DynamicNotch
//
//  Single owner of AI usage polling and alert state.
//
//  This used to live as `.onChange` handlers in ContentView, which is created
//  once per screen — fine for idempotent start/stop, but threshold alerts would
//  have fired once per display. Polling also never restarted when the interval
//  setting changed, so switching 30 min → 1 min could take half an hour to take
//  effect. Both are handled here instead.
//

import Defaults
import Foundation
import UserNotifications

/// The slice of a usage manager the coordinator needs. Deliberately narrow —
/// this is not a general provider abstraction.
@MainActor
protocol AIUsageSource: AnyObject {
    var displayName: String { get }
    var usagePercent: Double { get }
    var windowResetsAt: Date? { get }
    var timeUntilReset: String { get }
    var isAuthenticated: Bool { get }
    var hasError: Bool { get }
    func refreshNow() async
}

@MainActor
final class AIUsageCoordinator: ObservableObject {
    static let shared = AIUsageCoordinator()

    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var pollingTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?

    // Last values acted on, so a settings change that does not affect polling
    // does not tear the loop down and start a fresh request.
    private var appliedEnabled: Bool?
    private var appliedProvider: AIUsageProvider?
    private var appliedInterval: Int?

    private init() {}

    var activeSource: any AIUsageSource {
        Defaults[.aiUsageProvider] == .claude
            ? ClaudeUsageManager.shared
            : ChatGPTUsageManager.shared
    }

    /// Called once from the app delegate.
    func bootstrap() {
        UNUserNotificationCenter.current().delegate = AIUsageNotifier.shared
        Task { await refreshNotificationStatus() }

        settingsTask = Task { [weak self] in
            let keys: [Defaults._AnyKey] = [
                .showAIUsageTab, .aiUsageProvider, .aiUsagePollingInterval,
            ]
            for await _ in Defaults.updates(keys) {
                self?.applySettings()
            }
        }
    }

    // MARK: - Settings

    private func applySettings() {
        let enabled = Defaults[.showAIUsageTab]
        let provider = Defaults[.aiUsageProvider]
        let interval = Defaults[.aiUsagePollingInterval]

        guard enabled != appliedEnabled
            || provider != appliedProvider
            || interval != appliedInterval
        else { return }

        // Switching provider invalidates the window history — the thresholds
        // already announced for one provider say nothing about the other.
        if let previous = appliedProvider, previous != provider {
            Defaults[.aiUsageThresholdState] = .init()
        }

        appliedEnabled = enabled
        appliedProvider = provider
        appliedInterval = interval

        stopPolling()
        if enabled { startPolling() }
    }

    // MARK: - Polling

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                let minutes = max(1, Defaults[.aiUsagePollingInterval])
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Fetch immediately without disturbing the polling schedule.
    func refreshNow() async {
        await tick()
    }

    private func tick() async {
        let source = activeSource
        await source.refreshNow()
        // Never evaluate alerts against a reading we could not trust.
        guard source.isAuthenticated, !source.hasError else { return }
        evaluateAlerts(for: source)
    }

    // MARK: - Alerts

    /// The configured alert points, with disabled slots removed.
    private var configuredThresholds: [Int] {
        [
            Defaults[.aiUsageThresholdA],
            Defaults[.aiUsageThresholdB],
            Defaults[.aiUsageThresholdC],
        ]
        .filter { $0 > 0 }
    }

    private func evaluateAlerts(for source: any AIUsageSource) {
        // State advances even when notifications are switched off, so enabling
        // them later does not deliver a backlog of crossings already passed.
        var state = Defaults[.aiUsageThresholdState]
        let events = state.ingest(
            percent: source.usagePercent,
            resetsAt: source.windowResetsAt,
            thresholds: configuredThresholds
        )
        Defaults[.aiUsageThresholdState] = state

        guard Defaults[.aiUsageNotificationsEnabled] else { return }

        for event in events {
            switch event {
            case let .crossed(threshold, _):
                AIUsageNotifier.shared.postThreshold(
                    provider: source.displayName,
                    threshold: threshold,
                    timeUntilReset: source.timeUntilReset
                )
            case let .windowReset(previousPeak):
                guard Defaults[.aiUsageNotifyOnReset],
                      previousPeak >= Double(Defaults[.aiUsageResetNotifyMinPercent])
                else { continue }
                AIUsageNotifier.shared.postWindowReset(
                    provider: source.displayName,
                    previousPeak: previousPeak
                )
            }
        }
    }

    // MARK: - Notification authorization

    func refreshNotificationStatus() async {
        notificationStatus = await AIUsageNotifier.shared.authorizationStatus()
    }

    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        let granted = await AIUsageNotifier.shared.requestAuthorization()
        await refreshNotificationStatus()
        return granted
    }
}
