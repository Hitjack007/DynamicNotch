//
//  ClaudeUsageManager.swift
//  boringNotch
//

import Defaults
import Foundation
import SwiftUI

@MainActor
final class ClaudeUsageManager: ObservableObject {
    static let shared = ClaudeUsageManager()

    enum AuthState: Equatable {
        case unauthenticated
        case authenticated
        case expired
        case error(String)
    }

    @Published var authState: AuthState = .unauthenticated
    @Published var usagePercent: Double = 0      // 0.0–1.0
    @Published var limitKind: String = ""        // "Session", "Weekly", etc.
    @Published var windowResetsAt: Date?
    @Published var lastFetched: Date?
    @Published var isAuthenticating: Bool = false
    @Published var availableLimitGroups: [String] = []  // debug: all group names from last response

    var isAuthenticated: Bool { authState == .authenticated }

    var timeUntilReset: String {
        guard let date = windowResetsAt else { return "--" }
        let remaining = date.timeIntervalSince(Date())
        guard remaining > 0 else { return "Resetting…" }
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var compactTimeUntilReset: String {
        guard let date = windowResetsAt else { return "--" }
        let remaining = date.timeIntervalSince(Date())
        guard remaining > 0 else { return "0m" }
        if remaining >= 3600 {
            return "\(Int(ceil(remaining / 3600)))h"
        } else {
            return "\(max(1, Int(ceil(remaining / 60))))m"
        }
    }

    private var pollingTask: Task<Void, Never>?

    private init() {
        if KeychainHelper.load(account: "claude.sessionKey") != nil {
            authState = .authenticated
        }
        if Defaults[.showClaudeUsageTab] {
            start()
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                let minutes = Defaults[.claudePollingInterval]
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Auth

    func authenticate() async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        let browser = Defaults[.claudePreferredBrowser]
        guard let sessionKey = findSessionKey(for: browser) else {
            authState = .error("Cookie not found. Log into claude.ai in your browser first.")
            return
        }

        KeychainHelper.save(sessionKey, account: "claude.sessionKey")
        KeychainHelper.delete(account: "claude.orgID")

        // Prefer the org ID from cookies — avoids an unverified API round-trip
        if let orgID = findCookie(named: "lastActiveOrg", for: browser), !orgID.isEmpty {
            KeychainHelper.save(orgID, account: "claude.orgID")
            authState = .authenticated
        } else {
            await discoverOrgID(sessionKey: sessionKey)
        }
    }

    func reauthenticate() async {
        KeychainHelper.delete(account: "claude.sessionKey")
        KeychainHelper.delete(account: "claude.orgID")
        authState = .unauthenticated
        usagePercent = 0
        limitKind = ""
        windowResetsAt = nil
        await authenticate()
    }

    func authenticateManually(sessionKey: String) async {
        let trimmed = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        KeychainHelper.save(trimmed, account: "claude.sessionKey")
        KeychainHelper.delete(account: "claude.orgID")
        await discoverOrgID(sessionKey: trimmed)
    }

    func refreshNow() async {
        guard let sessionKey = KeychainHelper.load(account: "claude.sessionKey") else {
            authState = .unauthenticated
            return
        }
        if let orgID = KeychainHelper.load(account: "claude.orgID") {
            await fetchUsage(sessionKey: sessionKey, orgID: orgID)
        } else {
            await discoverOrgID(sessionKey: sessionKey)
            if let orgID = KeychainHelper.load(account: "claude.orgID") {
                await fetchUsage(sessionKey: sessionKey, orgID: orgID)
            }
        }
    }

    // MARK: - API
    //
    // TODO: Verify endpoints by capturing real claude.ai network traffic in
    // browser devtools (Network tab → XHR/Fetch) while on claude.ai.
    // Update parseUsage() field names to match the actual JSON response shape.

    private func discoverOrgID(sessionKey: String) async {
        guard let url = URL(string: "https://claude.ai/api/organizations") else { return }
        var req = URLRequest(url: url)
        decorate(&req, sessionKey: sessionKey)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return }
            guard http.statusCode != 401 else { authState = .expired; return }
            guard http.statusCode == 200 else { return }

            // Handles both [{id: "..."}, ...] and [{uuid: "..."}, ...] shapes
            if let orgs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = orgs.first,
               let id = (first["id"] ?? first["uuid"]) as? String
            {
                KeychainHelper.save(id, account: "claude.orgID")
                authState = .authenticated
            } else {
                authState = .error("Could not parse org info from Claude API response.")
            }
        } catch {
            authState = .error(error.localizedDescription)
        }
    }

    private func fetchUsage(sessionKey: String, orgID: String) async {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgID)/usage") else { return }
        var req = URLRequest(url: url)
        decorate(&req, sessionKey: sessionKey)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return }
            guard http.statusCode != 401 else { authState = .expired; return }
            guard http.statusCode == 200 else { return }
            parseUsage(data)
            lastFetched = Date()
            authState = .authenticated
        } catch {
            // Keep last-good data on transient network errors
        }
    }

    private func parseUsage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // The `limits` array is the authoritative source — each entry has `percent` (0–100),
        // `resets_at`, `group` ("session"/"weekly"), and `is_active`.
        if let limits = json["limits"] as? [[String: Any]], !limits.isEmpty {
            availableLimitGroups = limits.compactMap { $0["group"] as? String }

            // JSON percent may arrive as Int or Double — handle both
            func pctValue(_ d: [String: Any]) -> Double {
                if let v = d["percent"] as? Double { return v }
                if let v = d["percent"] as? Int { return Double(v) }
                return 0
            }

            // Always prefer the 5-hour session limit regardless of is_active —
            // is_active just marks the currently binding constraint, not what to display.
            // Fall back to highest-percent limit when no session-type entry exists.
            let sessionKeywords = ["session", "five", "hour"]
            let best = limits.first {
                let g = ($0["group"] as? String ?? "").lowercased()
                return sessionKeywords.contains { g.contains($0) }
            } ?? limits.max { pctValue($0) < pctValue($1) }

            if let limit = best {
                usagePercent = min(pctValue(limit) / 100.0, 1.0)
                limitKind = (limit["group"] as? String ?? "")
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
                if let resetStr = limit["resets_at"] as? String {
                    windowResetsAt = isoFormatter.date(from: resetStr)
                } else {
                    windowResetsAt = nil
                }
            }
        } else {
            // Fallback: read five_hour or seven_day directly
            let bucket = (json["five_hour"] as? [String: Any]) ?? (json["seven_day"] as? [String: Any])
            if let pct = bucket?["utilization"] as? Int {
                usagePercent = min(Double(pct) / 100.0, 1.0)
            }
            if let resetStr = bucket?["resets_at"] as? String {
                windowResetsAt = isoFormatter.date(from: resetStr)
            }
        }
    }

    private func decorate(_ req: inout URLRequest, sessionKey: String) {
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    // MARK: - Cookie harvesting

    private func findSessionKey(for browser: ClaudeBrowserPreference) -> String? {
        findCookie(named: "sessionKey", for: browser)
    }

    private func findCookie(named name: String, for browser: ClaudeBrowserPreference) -> String? {
        switch browser {
        case .auto:
            return SafariCookieReader.findCookie(named: name)
                ?? ChromeCookieReader.findCookie(named: name, variant: .chrome)
                ?? ChromeCookieReader.findCookie(named: name, variant: .brave)
                ?? ChromeCookieReader.findCookie(named: name, variant: .edge)
        case .safari:
            return SafariCookieReader.findCookie(named: name)
        case .chrome:
            return ChromeCookieReader.findCookie(named: name, variant: .chrome)
        case .brave:
            return ChromeCookieReader.findCookie(named: name, variant: .brave)
        case .edge:
            return ChromeCookieReader.findCookie(named: name, variant: .edge)
        }
    }
}
