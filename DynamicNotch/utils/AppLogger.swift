//
//  AppLogger.swift
//  DynamicNotch
//
//  One logger per subsystem area. Every call goes to the unified log (os.Logger, the
//  full Console.app/`log stream`/sysdiagnose firehose) and unconditionally to
//  DiagnosticsCollector's full log; DiagnosticsCollector itself decides whether a
//  given call also qualifies for the small curated log - see that type.
//
//  Call-site discipline instead of OSLogMessage privacy annotations: because messages
//  here are plain, fully-built Swift Strings (not `Logger` format-string literals with
//  \(value, privacy:) arguments), nothing is auto-redacted. Never build a message that
//  interpolates a raw Error, a full URL, a token, or a cookie value - extract only the
//  safe part (status code, error domain/code, host-only URL) before calling.
//

import Foundation
import os

struct CategoryLogger {
    fileprivate let category: String
    private let osLogger: Logger

    fileprivate init(category: String, subsystem: String) {
        self.category = category
        self.osLogger = Logger(subsystem: subsystem, category: category)
    }

    func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
        DiagnosticsCollector.record(level: .debug, category: category, message: message)
    }

    func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        DiagnosticsCollector.record(level: .info, category: category, message: message)
    }

    func notice(_ message: String) {
        osLogger.notice("\(message, privacy: .public)")
        DiagnosticsCollector.record(level: .default, category: category, message: message)
    }

    func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        DiagnosticsCollector.record(level: .error, category: category, message: message)
    }

    func fault(_ message: String) {
        osLogger.fault("\(message, privacy: .public)")
        DiagnosticsCollector.record(level: .fault, category: category, message: message)
    }
}

enum AppLogger {
    static let subsystem = "com.mark.dynamicnotch"

    static let launch      = CategoryLogger(category: "launch", subsystem: subsystem)
    static let media       = CategoryLogger(category: "media", subsystem: subsystem)
    static let network     = CategoryLogger(category: "network", subsystem: subsystem)
    static let auth        = CategoryLogger(category: "auth", subsystem: subsystem)
    static let shelf       = CategoryLogger(category: "shelf", subsystem: subsystem)
    static let calendar    = CategoryLogger(category: "calendar", subsystem: subsystem)
    static let extensions  = CategoryLogger(category: "extensions", subsystem: subsystem)
    static let thermal     = CategoryLogger(category: "thermal", subsystem: subsystem)
    static let audio       = CategoryLogger(category: "audio", subsystem: subsystem)
    static let xpc         = CategoryLogger(category: "xpc", subsystem: subsystem)
    static let aiUsage     = CategoryLogger(category: "aiUsage", subsystem: subsystem)
    static let keychain    = CategoryLogger(category: "keychain", subsystem: subsystem)
    static let updates     = CategoryLogger(category: "updates", subsystem: subsystem)
    static let battery     = CategoryLogger(category: "battery", subsystem: subsystem)
    static let permissions = CategoryLogger(category: "permissions", subsystem: subsystem)
    static let general     = CategoryLogger(category: "general", subsystem: subsystem)
}
