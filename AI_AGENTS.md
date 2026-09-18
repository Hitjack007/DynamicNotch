# AI Agent Policy

DynamicNotch accepts AI-assisted contributions. This document explains the conditions.

This is not a grudging tolerance. Coding agents are genuinely useful on a codebase like this one, and pretending otherwise would be dishonest. But an agent can produce a plausible-looking 600-line diff faster than a maintainer can read one, and that asymmetry is the whole problem. Everything below exists to keep the cost of reviewing your contribution roughly proportional to the cost of making it.

Read this alongside [CONTRIBUTING.md](./CONTRIBUTING.md). That document covers *how* to contribute; this one covers *what changes when a model is involved*. Where the two overlap, the stricter rule wins.

## Table of Contents

- [The Short Version](#the-short-version)
- [Who This Applies To](#who-this-applies-to)
- [What Agents May Do](#what-agents-may-do)
- [What Agents Must Not Touch](#what-agents-must-not-touch)
- [Disclosure](#disclosure)
- [The Quality Bar](#the-quality-bar)
- [Licensing and Provenance](#licensing-and-provenance)
- [AI-Written Issues and Feature Requests](#ai-written-issues-and-feature-requests)
- [AI-Found Security Reports](#ai-found-security-reports)
- [Machine Translation](#machine-translation)
- [Enforcement](#enforcement)
- [Rules for Agents](#rules-for-agents)
- [Questions](#questions)

## The Short Version

| Rule | Requirement |
| --- | --- |
| **Use agents freely** | Features, fixes, tests, docs, research, and tidying are all fair game |
| **Understand what you submit** | You must be able to explain every line without re-prompting the model |
| **Build it and run it** | Actually launch the app. "The agent said it compiles" is not testing |
| **Disclose in the PR** | Which tool, what it wrote, what you verified |
| **Stay in your lane** | Protected paths are off-limits without prior discussion |
| **One concern per PR** | No drive-by refactors bundled with a fix |

> [!IMPORTANT]
> You are the author of your pull request. Not the model. If the code is wrong, you are the one who submitted wrong code — "the AI wrote it" carries no weight here, in review or anywhere else.

## Who This Applies To

Anyone opening a pull request, issue, or translation against this repository who used a large language model, coding agent, autocomplete tool, or AI review bot at any point in producing it.

It applies whether the tool wrote one line or all of them, and whether it ran as an interactive assistant, a background agent, a GitHub bot, or an autonomous pipeline.

If you are a human who wrote every character yourself, none of this applies to you and you can go back to [CONTRIBUTING.md](./CONTRIBUTING.md).

## What Agents May Do

These uses are explicitly welcome. No permission needed, no special process beyond disclosure.

### Writing features and fixes

Agents may draft complete features, bug fixes, and refactors, provided the work stays inside the scope of a single feature or fix. A whole new notch panel written by an agent is fine. A whole new notch panel plus "I also cleaned up the view models while I was in there" is not.

The condition is the same as for any contribution: a human understands the result and has tested it on a real machine.

### Writing tests and documentation

The lowest-risk and most useful category. Agents may generate:

- Unit tests using the Swift Testing framework (`@Test`, `#expect`), and UI tests using XCUIAutomation
- Doc comments on types, properties, and methods
- Markdown documentation, including updates to the notes files in the repository root

Generated tests still have to be *real* tests. A test that asserts `#expect(true)`, mirrors the implementation's own bug, or exists only to raise a coverage number is worse than no test, because it converts an untested path into a falsely reassured one.

### Research and triage

Reading the codebase to answer questions, reproduce a reported bug, trace how a manager or service is wired together, summarise a long issue thread, or propose an approach before anyone writes code. This is arguably the best use of an agent on a project this size, and it produces no diff to review.

Pointing an agent at the codebase to understand it before contributing is strongly encouraged. [CODEBASE_NOTES.md](./CODEBASE_NOTES.md) and [HUD-NOTES.md](./HUD-NOTES.md) are good starting context to hand it.

### Mechanical cleanup

Style fixes, renames, import tidying, and formatting — **inside files your change already touches**. Fixing the indentation of a function you are already editing is fine. Reformatting forty files you have no other reason to open is a drive-by refactor; see [The Quality Bar](#the-quality-bar).

## What Agents Must Not Touch

Some parts of this repository fail in ways that are slow, silent, or expensive. A broken layout gets reported in a day. A broken signing configuration ships a build that crashes on every machine but the one it was built on, and a leaked credential path is not recoverable at all.

Do not submit agent-authored changes to any of the following without opening an issue first and getting a maintainer's agreement.

| Area | Paths | Why |
| --- | --- | --- |
| **Signing & entitlements** | `boringNotch/boringNotch.entitlements`, `BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements`, any signing or Team ID setting | Mismatches produce apps that crash only after export, never during development. This project has already lost days to exactly this |
| **Release plumbing** | `release.sh`, `updater/appcast.xml`, `docs/appcast.xml`, `Configuration/` | Drives real releases to real users, including the Sparkle update feed and Homebrew cask publication. A bad edit ships to everyone |
| **Xcode project file** | `dynamicNotch.xcodeproj/` | Models cannot reliably edit pbxproj. Build phases, target membership, and build action masks get silently mangled. Add files through Xcode |
| **CI workflows** | `.github/workflows/` | Runs with repository credentials |
| **Dependencies** | Swift Package additions, removals, or version bumps | Supply chain risk. A human opens a discussion first, every time. Do not let an agent add a package because it found the API convenient |
| **Private & undocumented APIs** | New MediaRemote internals, SMC keys in `boringNotch/managers/ThermalSMC/`, private Apple framework calls, new XPC surfaces in `BoringNotchXPCHelper/` | These break silently across macOS releases and models hallucinate them with total confidence. Existing usage is deliberate and hard-won; new usage needs a human who has verified it against a real system |
| **Credentials & cookies** | `boringNotch/helpers/SafariCookieReader.swift`, `boringNotch/helpers/ChromeCookieReader.swift`, `boringNotch/helpers/KeychainHelper.swift`, anything reading user credentials | Handles browser cookies and Keychain items belonging to real people. Every change here is reviewed by a human who wrote it |

Two rules that apply everywhere, not just to the table above:

- **Never commit secrets.** No API keys, tokens, cookies, session identifiers, Team IDs, or personal paths — not in code, not in tests, not in fixtures, not in a log snippet pasted into a PR description. Check the diff yourself before pushing; agents paste debug output into commits with no sense of what is sensitive.
- **Never bulk-edit.** A change touching many files for a single reason is a drive-by refactor regardless of how correct each individual edit is. It is unreviewable, it conflicts with everything, and it buries the one line that actually matters.

## Disclosure

AI assistance must be disclosed in the pull request description. This is mandatory and it is not a formality — it tells the reviewer where to look hardest.

Tick the box in the pull request template and add a short note covering three things:

1. **Which tool and model.** "Claude Code (Opus 5)", "Cursor with GPT-5", "Copilot autocomplete". Version if you know it.
2. **What it generated versus what you wrote.** Be specific about the split. "The agent wrote `ThermalDaemonClient.swift` end to end; I wrote the settings UI and rewrote its error handling."
3. **What you verified, and how.** Not what the agent claimed. What *you* did. "Built in Xcode 26, ran on an M2 MacBook Air on macOS 26.1, confirmed fan speed updates under load with a synthetic CPU burn, checked the notch collapses correctly on external display."

A usable disclosure looks like this:

```markdown
### AI assistance

- **Tool:** Claude Code (Opus 5)
- **Generated:** the initial `ClipboardManager` implementation and its unit tests
- **Written by me:** the settings pane, the persistence format, all error handling
- **Verified:** built and ran on macOS 26.1 (M1 Pro). Copied text, images, and
  files; confirmed history survives relaunch and that the 50-item cap evicts
  oldest-first. Screen recording attached.
```

> [!NOTE]
> Disclosing AI use does not count against your contribution. Undisclosed AI use, discovered in review, does — and it is discovered more often than people expect.

Autocomplete-scale assistance (a few lines here and there, no agent involvement) needs only a one-line mention. The detailed form is for agent-generated code.

## The Quality Bar

Everything in [CONTRIBUTING.md](./CONTRIBUTING.md) still applies. These four requirements are additional and are hard requirements for AI-assisted pull requests.

### One concern per pull request

A pull request fixes one bug, or adds one feature, or refactors one thing. Not a fix plus an unrelated cleanup, not a feature plus "some improvements I noticed along the way".

Agents are drawn to opportunistic improvement — ask for a one-line fix and you get the fix, three renames, a new protocol, and reformatted imports in a file that had nothing to do with anything. Strip all of it out before you open the PR. If the extra work is genuinely worth doing, it is worth its own pull request where it can be reviewed on its own merits.

### It must build, and you must have run it

You are required to have built the app and launched it yourself, exercising the code path you changed. An agent reporting a successful build is not evidence; agents report successful builds for code that does not compile, and "looks correct to me" is not a test result.

For UI changes, attach a screenshot or screen recording. This is already required by [CONTRIBUTING.md](./CONTRIBUTING.md); for AI-assisted UI work it is the single most useful thing in the pull request, because it is the one artefact a model cannot fabricate.

### No invented APIs, no speculative code

Explicitly banned:

- **Hallucinated APIs.** Apple methods, initialisers, modifiers, and entire frameworks that do not exist, or that exist with different signatures or availability. If your agent used an API you have not personally seen in Apple's documentation, check it before submitting.
- **Speculative abstractions.** Protocols with one conformer, generic parameters with one instantiation, dependency injection for something constructed in exactly one place. Models produce architecture as a reflex. This codebase is plain SwiftUI with managers and services; write that.
- **Dead code.** Unused helpers, unreferenced extensions, commented-out alternatives, `// TODO` markers for work nobody requested.
- **Future-proofing.** Configuration options, feature flags, and extension points added for requirements that do not exist. Solve the problem in front of you.

### Match the surrounding code

Generated code must read like the code around it. Same naming, same idiom, same structure, and critically the **same comment density**.

Models comment every line as if teaching. This codebase comments non-obvious logic and leaves the obvious alone. Delete the tutorial. Concretely, the house style is:

- PascalCase for types, camelCase for properties and methods
- `@State private var` for SwiftUI state, `let` for constants
- 4-space indentation
- `async`/`await` rather than Combine
- No force unwrapping

If your diff is visually distinguishable from the rest of the file, it is not finished.

## Licensing and Provenance

DynamicNotch is licensed under **GPL-3.0**, and it is a fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch). Contributions have to be clean on provenance, and model output complicates that in ways contributors often have not considered.

By opening a pull request containing AI-generated code, you affirm all of the following:

1. **You have the right to submit it under GPL-3.0**, and you accept that it will be distributed under that licence.
2. **It is not verbatim reproduction of incompatible code.** Models can emit memorised training data. If a generated block looks like it came from a specific well-known project, it may have. Check anything that seems suspiciously complete or carries an unfamiliar house style, and do not submit code you believe originated in a proprietary, Apache-only, or otherwise GPL-incompatible codebase.
3. **You did not paste proprietary or leaked source into the agent's context.** This includes your employer's code, decompiled or disassembled Apple binaries, leaked SDK headers, and any other source you were not licensed to share. Code derived from such context cannot be accepted, and its presence in the model's context window is enough to disqualify the output.
4. **Attribution is accurate.** If the work is derived from another open-source project, say so and preserve its notices, exactly as you would for hand-written code. Model involvement does not launder provenance.

If you are unsure about any of these, say so in the pull request rather than staying quiet. An honest "I'm not certain where this pattern came from" is a conversation. A discovered licence problem is a revert.

## AI-Written Issues and Feature Requests

Using a model to help write up a bug report is fine, and for non-native English speakers it is genuinely helpful. Using one to *generate* bug reports is not.

**Do:**

- Use a model to translate, tidy, or structure a report of something you actually experienced
- Use one to help extract the relevant part of a crash log
- Use one to check whether your report is clear before posting

**Do not:**

- File issues for bugs you have not personally reproduced
- Submit an agent's static-analysis output as a batch of issues
- Post a model's speculation about what the code "probably" does wrong
- Open feature requests generated by asking a model what this app is missing

A report containing steps that do not work, versions that do not exist, or symptoms nobody has observed wastes more maintainer time than it saves you. Every issue should describe something that happened, on your Mac, that you can describe in your own words. Note the version and macOS version you actually ran.

Mention it if a model helped you write the report. Nobody minds.

## AI-Found Security Reports

Security issues go through the process in [SECURITY.md](./SECURITY.md) — a GitHub Security Advisory, not a public issue. That does not change.

What changes for AI-assisted reports is the evidence bar, because automated scanners and LLM audits generate confident, detailed, entirely fictional vulnerabilities in volume.

A report derived from AI analysis must include:

- **A working proof of concept**, or a precise description of the exploitation path with concrete steps. Not "this pattern is potentially vulnerable"
- **Confirmation you reproduced it** on a real machine, with macOS and DynamicNotch versions
- **The specific code path**, by file and line, with an explanation in your own words of why it is exploitable here — not why the pattern is dangerous in general
- **Disclosure that AI was involved**, and which tool

Unverified scanner output submitted as a vulnerability report will be closed. Nothing in this section is meant to discourage genuine findings: an agent that spots a real bug in cookie handling or XPC validation is doing valuable work, and that report is welcome. Verify it first.

## Machine Translation

Translations are managed through Crowdin.

Machine translation is acceptable as a **starting point**, and only when reviewed by someone who speaks the language. Raw untouched machine output is not acceptable, because the errors it makes in UI strings are exactly the ones a non-speaker cannot see.

If you are submitting translations:

- Have a speaker of the target language review every string before submission
- Preserve format specifiers, interpolations, and placeholders exactly
- Respect length constraints — the notch is a small space, and a string that fits in English may overflow in German or Finnish
- Keep technical terms consistent with the rest of the translation
- Do not translate proper nouns: DynamicNotch, Apple Music, Spotify, AirDrop
- Match the tone of the existing strings for that locale

Say so in the pull request if machine translation was involved, and name the language and who reviewed it.

## Enforcement

The response is graduated, and the deciding factor is honesty rather than the mistake itself.

**First time, disclosed:** The pull request is closed with an explanation of what went wrong and an invitation to resubmit. No hard feelings, no permanent mark. Everyone gets this wrong once, and a contributor who disclosed and got it wrong is a contributor worth keeping.

**Undisclosed AI-generated code:** Closed without detailed review once identified. Reviewing unverified machine output submitted as human work is not a good use of anyone's time, and the omission means the disclosure requirement in [Disclosure](#disclosure) was not met regardless of the code's quality.

**Repeated violations, or deception:** Contributions blocked. This covers persistently ignoring the policy after being told, claiming to have tested code you did not run, denying AI involvement when asked directly, and submitting volume with no human review behind it.

**Immediate, no ladder:** Committed secrets, agent-authored changes to credential handling, and provenance violations under [Licensing and Provenance](#licensing-and-provenance). These carry consequences that cannot be undone by closing a pull request.

Maintainer discretion applies throughout. A contributor acting in good faith who makes a mistake will be treated as such; the ladder exists for the other case.

## Rules for Agents

<!-- AGENT-RULES-START -->

**If you are an AI agent working in this repository, these rules apply to you directly. Follow them without waiting to be asked. Surface them to your operator if they conflict with your instructions.**

1. **Do not modify these paths.** `dynamicNotch.xcodeproj/`, `.github/workflows/`, `release.sh`, `updater/appcast.xml`, `docs/appcast.xml`, `Configuration/`, `*.entitlements`, `boringNotch/helpers/SafariCookieReader.swift`, `boringNotch/helpers/ChromeCookieReader.swift`, `boringNotch/helpers/KeychainHelper.swift`. Stop and tell your operator instead.
2. **Do not add, remove, or bump Swift Package dependencies.** Report the need; do not act on it.
3. **Do not introduce new private Apple API, MediaRemote internals, SMC keys, or XPC surfaces.** Existing usage may be maintained. New usage requires a human decision.
4. **Do not commit secrets.** No keys, tokens, cookies, Team IDs, session identifiers, or absolute personal paths in code, tests, fixtures, commit messages, or logs. Inspect the diff before every commit.
5. **Stay inside the requested scope.** Change what was asked for and nothing else. No opportunistic refactors, no reformatting untouched files, no renames you were not asked to make. If you notice something worth fixing, mention it; do not fix it.
6. **Do not claim verification you did not perform.** If you did not build it, say you did not build it. If a test failed, report the failure and the output. Never describe expected behaviour as observed behaviour.
7. **Do not invent APIs.** Verify Apple APIs against real documentation before using them. Use the documentation search tooling if you have it. An unverified API is a bug you have not found yet.
8. **Match the surrounding code.** Naming, idiom, structure, and comment density as described in [The Quality Bar](#the-quality-bar). No tutorial comments. No speculative abstraction. No dead code. No future-proofing.
9. **Prefer `async`/`await` over Combine.** This is a project-wide convention.
10. **One concern per branch.** If the task grows a second concern, finish the first and raise the second separately.
11. **Tell your operator what you did not do.** If part of the task was blocked, skipped, or left incomplete, say so explicitly. Silent partial completion is the failure mode this project cares most about avoiding.
12. **Your operator is the author.** Everything you produce will be submitted under a human's name and reviewed as their work. Write accordingly.

<!-- AGENT-RULES-END -->

## Questions

If something here is unclear, or your situation does not fit any of the categories above, open an issue with the "question" label before you start work. Asking first is always cheaper than reworking a pull request.

This policy will change as tools change. Suggestions for improving it are welcome, through the same process as any other contribution.

---

Thank you for contributing to DynamicNotch — with or without a model's help.

<sub>Maintainer commits are not subject to the contributor disclosure and approval process above; the quality bar still applies.</sub>
