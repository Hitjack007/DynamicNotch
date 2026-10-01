//
//  YouTubeMusicAuthentication.swift
//  DynamicNotch
//
//  Created by Mark Greene on 2025-09-14.
//

import Foundation

// MARK: - Authentication Manager
actor YouTubeMusicAuthManager {
    private var accessToken: String?
    private var authenticationTask: Task<String, Error>?
    private let httpClient: YouTubeMusicHTTPClient
    
    init(httpClient: YouTubeMusicHTTPClient) {
        self.httpClient = httpClient
    }
    
    var currentToken: String? {
        accessToken
    }
    
    func authenticate() async throws -> String {
        // Return existing token if valid
        if let token = accessToken {
            return token
        }

        // Wait for ongoing authentication if in progress
        if let task = authenticationTask {
            AppLogger.auth.debug("YouTube Music auth: joining in-flight authentication")
            return try await task.value
        }

        AppLogger.auth.info("YouTube Music auth: requesting new token")
        // Start new authentication
        let task = Task<String, Error> {
            do {
                let token = try await httpClient.authenticate()
                await setToken(token)
                AppLogger.auth.info("YouTube Music auth: token obtained")
                return token
            } catch {
                await clearAuthenticationTask()
                if let urlError = error as? URLError {
                    AppLogger.auth.error("YouTube Music auth: request failed, URLError.Code=\(urlError.code.rawValue)")
                } else if let httpError = error as? YouTubeMusicError {
                    AppLogger.auth.error("YouTube Music auth: request failed, \(httpError.errorDescription ?? "unknown")")
                } else {
                    AppLogger.auth.error("YouTube Music auth: request failed, \(type(of: error))")
                }
                throw error
            }
        }

        authenticationTask = task
        return try await task.value
    }

    func invalidateToken() async {
        AppLogger.auth.notice("YouTube Music auth: invalidating cached token")
        accessToken = nil
        authenticationTask?.cancel()
        authenticationTask = nil
    }
    
    private func setToken(_ token: String) async {
        accessToken = token
        authenticationTask = nil
    }
    
    private func clearAuthenticationTask() async {
        authenticationTask = nil
    }
}

// MARK: - Authentication State
enum AuthenticationState: Sendable {
    case unauthenticated
    case authenticating
    case authenticated(String)
    case failed(Error)
    
    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }
    
    var token: String? {
        if case .authenticated(let token) = self {
            return token
        }
        return nil
    }
}