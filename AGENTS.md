# AGENTS.md

If you are an AI coding agent working in this repository, read **[AI_AGENTS.md](./AI_AGENTS.md)** before making any changes. The [Rules for Agents](./AI_AGENTS.md#rules-for-agents) section is addressed to you directly and is binding.

> **Scope:** these rules bind agents producing changes intended for submission to this repository as a pull request. That is the default assumption — if you are reading this file, it applies to you, unless the person operating you has given you instructions that explicitly supersede it. Maintainer commits go through a different process; see the note at the end of [AI_AGENTS.md](./AI_AGENTS.md).

The essentials, in case you read nothing else:

1. **Protected paths — do not modify:** `dynamicNotch.xcodeproj/`, `.github/workflows/`, `release.sh`, `updater/appcast.xml`, `docs/appcast.xml`, `Configuration/`, `*.entitlements`, `boringNotch/helpers/SafariCookieReader.swift`, `boringNotch/helpers/ChromeCookieReader.swift`, `boringNotch/helpers/KeychainHelper.swift`.
2. **No dependency changes.** No new Swift Packages, no version bumps.
3. **No new private Apple API, MediaRemote internals, SMC keys, or XPC surfaces.**
4. **No secrets in the diff** — keys, tokens, cookies, Team IDs, personal paths.
5. **Stay in scope.** No opportunistic refactors or reformatting of untouched files.
6. **Do not claim verification you did not perform.** Report failures with their output.
7. **Verify Apple APIs against real documentation.** Do not invent them.
8. **Match the surrounding style**, including comment density. `async`/`await`, not Combine.

## Project orientation

- **What it is:** a macOS menu bar app that turns the MacBook notch into a live system dashboard. SwiftUI, macOS 15+, GPL-3.0.
- **Build:** open `dynamicNotch.xcodeproj` in Xcode 26 or later. Targets: `dynamicNotch`, `BoringNotchXPCHelper`, `BoringNotchThermalDaemon`.
- **Tests:** Swift Testing for unit tests, XCUIAutomation for UI tests.
- **Architecture notes:** [CODEBASE_NOTES.md](./CODEBASE_NOTES.md) and [HUD-NOTES.md](./HUD-NOTES.md).
- **Human contribution process:** [CONTRIBUTING.md](./CONTRIBUTING.md).
