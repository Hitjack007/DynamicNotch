//
//  ChatGPTUsageManager.swift
//  boringNotch
//

import Defaults
import Foundation
import SwiftUI

@MainActor
final class ChatGPTUsageManager: ObservableObject {
    static let shared = ChatGPTUsageManager()

    enum AuthState: Equatable {
        case unauthenticated
        case authenticated
        case expired
        case error(String)
    }

    @Published var authState: AuthState = .unauthenticated
    @Published var usagePercent: Double = 0
    @Published var limitKind: String = ""
    @Published var windowResetsAt: Date?
    @Published var lastFetched: Date?
    @Published var isAuthenticating: Bool = false

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
        if KeychainHelper.load(account: "chatgpt.accessToken") != nil {
            authState = .authenticated
        }
        if Defaults[.showAIUsageTab] && Defaults[.aiUsageProvider] == .chatgpt {
            start()
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                let minutes = Defaults[.aiUsagePollingInterval]
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

        let browser = Defaults[.chatgptPreferredBrowser]
        guard let token0 = findCookie(named: "__Secure-next-auth.session-token.0", for: browser, domain: "chatgpt.com"),
              let token1 = findCookie(named: "__Secure-next-auth.session-token.1", for: browser, domain: "chatgpt.com") else {
            authState = .error("Cookies not found. Log into chatgpt.com in your browser first.")
            return
        }

        await exchangeSessionCookies(token0: token0, token1: token1)
    }

    func reauthenticate() async {
        KeychainHelper.delete(account: "chatgpt.accessToken")
        KeychainHelper.delete(account: "chatgpt.sessionToken")
        authState = .unauthenticated
        usagePercent = 0
        limitKind = ""
        windowResetsAt = nil
        await authenticate()
    }

    func refreshNow() async {
        guard var accessToken = KeychainHelper.load(account: "chatgpt.accessToken") else {
            authState = .unauthenticated
            return
        }

        if isAccessTokenExpired(accessToken) {
            guard let refreshed = await refreshAccessToken() else {
                authState = .expired
                return
            }
            accessToken = refreshed
        }

        await fetchUsage(accessToken: accessToken)
    }

    // MARK: - API

    private func exchangeSessionCookies(token0: String, token1: String) async {
        guard let url = URL(string: "https://chatgpt.com/api/auth/session") else { return }
        var req = URLRequest(url: url)
        req.setValue(
            "__Secure-next-auth.session-token.0=\(token0); __Secure-next-auth.session-token.1=\(token1)",
            forHTTPHeaderField: "Cookie"
        )
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return }
            guard http.statusCode != 401 else { authState = .expired; return }
            guard http.statusCode == 200 else {
                authState = .error("Session exchange failed (HTTP \(http.statusCode)).")
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                authState = .error("Could not parse session response.")
                return
            }

            guard let accessToken = json["accessToken"] as? String else {
                authState = .error("No access token in session response.")
                return
            }

            KeychainHelper.save(accessToken, account: "chatgpt.accessToken")

            if let sessionToken = json["sessionToken"] as? String {
                KeychainHelper.save(sessionToken, account: "chatgpt.sessionToken")
            }

            authState = .authenticated
        } catch {
            authState = .error(error.localizedDescription)
        }
    }

    private func refreshAccessToken() async -> String? {
        guard let sessionToken = KeychainHelper.load(account: "chatgpt.sessionToken"),
              let url = URL(string: "https://chatgpt.com/api/auth/session") else { return nil }

        var req = URLRequest(url: url)
        req.setValue("__Secure-next-auth.session-token=\(sessionToken)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["accessToken"] as? String else { return nil }

        KeychainHelper.save(newAccessToken, account: "chatgpt.accessToken")

        if let newSessionToken = json["sessionToken"] as? String {
            KeychainHelper.save(newSessionToken, account: "chatgpt.sessionToken")
        }

        return newAccessToken
    }

    private func fetchUsage(accessToken: String) async {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")

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

        if let rateLimit = json["rate_limit"] as? [String: Any],
           let primaryWindow = rateLimit["primary_window"] as? [String: Any] {
            if let usedPercent = primaryWindow["used_percent"] as? Int {
                usagePercent = min(Double(usedPercent) / 100.0, 1.0)
            } else if let usedPercent = primaryWindow["used_percent"] as? Double {
                usagePercent = min(usedPercent / 100.0, 1.0)
            }
        }

        if let resetAt = json["reset_at"] as? TimeInterval {
            windowResetsAt = Date(timeIntervalSince1970: resetAt)
        } else if let resetAt = json["reset_at"] as? Int {
            windowResetsAt = Date(timeIntervalSince1970: TimeInterval(resetAt))
        }

        if let planType = json["plan_type"] as? String {
            limitKind = planType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - JWT expiry

    private func isAccessTokenExpired(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return true }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else { return true }
        return Date().timeIntervalSince1970 + 5 * 60 >= exp
    }

    // MARK: - Cookie harvesting

    private func findCookie(named name: String, for browser: AIBrowserPreference, domain: String) -> String? {
        switch browser {
        case .auto:
            return SafariCookieReader.findCookie(named: name, domain: domain)
                ?? ChromeCookieReader.findCookie(named: name, variant: .chrome, domain: domain)
                ?? ChromeCookieReader.findCookie(named: name, variant: .brave, domain: domain)
                ?? ChromeCookieReader.findCookie(named: name, variant: .edge, domain: domain)
        case .safari:
            return SafariCookieReader.findCookie(named: name, domain: domain)
        case .chrome:
            return ChromeCookieReader.findCookie(named: name, variant: .chrome, domain: domain)
        case .brave:
            return ChromeCookieReader.findCookie(named: name, variant: .brave, domain: domain)
        case .edge:
            return ChromeCookieReader.findCookie(named: name, variant: .edge, domain: domain)
        }
    }
}
