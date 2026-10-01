//
//  AppleScriptHelper.swift
//  DynamicNotch
//
//  Created by Mark Greene on 2025-03-29.
//

import Foundation

class AppleScriptHelper {
    @discardableResult
    class func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let script = NSAppleScript(source: scriptText)
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error) {
                    continuation.resume(returning: descriptor)
                } else if let error = error {
                    // The real OSAError (e.g. -1743 "not authorized") was previously
                    // discarded in favor of a hardcoded code 1, making automation-permission
                    // denials indistinguishable from any other script failure in logs.
                    let number = (error[NSAppleScript.errorNumber] as? Int) ?? 1
                    let message = (error[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
                    AppLogger.general.error("AppleScript execution failed, OSAError=\(number): \(message)")
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: number, userInfo: error as? [String: Any]))
                } else {
                    AppLogger.general.error("AppleScript execution failed with no error dictionary")
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }
    
    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
}
