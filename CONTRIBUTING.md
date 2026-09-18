# Contributing

Thank you for taking the time to contribute!

These guidelines help streamline the contribution process for everyone involved. By following them, you'll make it easier for maintainers to review your work and collaborate with you effectively.

You can contribute in many ways: writing code, improving documentation, reporting bugs, requesting features, or creating tutorials. Every contribution, large or small, helps make DynamicNotch better.

> [!IMPORTANT]
> Using an AI coding agent or assistant? Read the **[AI Agent Policy](./AI_AGENTS.md)** as well. AI-assisted contributions are welcome, but they come with extra requirements around disclosure, testing, and which parts of the codebase agents may touch.

## Table of Contents

- [Contributing Code](#contributing-code)
  - [Before You Start](#before-you-start)
  - [Setting Up Your Environment](#setting-up-your-environment)
  - [Making Changes](#making-changes)
  - [Pull Requests](#pull-requests)
- [Using AI Agents](#using-ai-agents)
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)
- [Getting Help](#getting-help)

## Contributing Code

### Before You Start

- **Check existing issues**: Before creating a new issue or starting work, search existing issues to avoid duplicates.
- **Discuss major changes**: For significant features or major changes, please open an issue first to discuss your approach with maintainers.

> [!IMPORTANT]
> All code contributions must be based on the `main` branch.

### Setting Up Your Environment

1. **Fork the repository**: Click the "Fork" button at the top of the repository page to create your own copy.

2. **Clone your fork**:
   ```bash
   git clone https://github.com/{your-username}/DynamicNotch.git
   cd DynamicNotch
   ```
   Replace `{your-username}` with your GitHub username.

3. **Open the project**:
   ```bash
   open dynamicNotch.xcodeproj
   ```

4. **Create a new feature branch**:
   ```bash
   git checkout -b feature/{your-feature-name}
   ```
   Replace `{your-feature-name}` with a descriptive name. Use lowercase letters, numbers, and hyphens only (e.g., `feature/add-dark-mode` or `fix/notification-crash`).

### Making Changes

1. **Make your changes**: Implement your feature or bug fix. Write clean, well-documented code.

2. **Test your changes**: Ensure your changes work as expected and don't break existing functionality.

3. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Add descriptive commit message"
   ```
   Write clear, concise commit messages that explain what your changes do and why.

4. **Keep your branch up to date**:
   Regularly sync your branch with the latest changes from `main` to avoid conflicts.

5. **Push to your fork**:
   ```bash
   git push origin feature/{your-feature-name}
   ```

### Pull Requests

1. **Create a pull request**: Go to the original repository and click "New Pull Request." Select your feature branch and set the base branch to `main`.

2. **Write a detailed description**: Your PR should include:
   - A clear title summarizing the changes
   - A detailed description of what was changed and why
   - Reference to any related issues (e.g., "Fixes #123" or "Relates to #456")
   - Screenshots or screen recordings for UI changes
   - A disclosure of any AI assistance, as described in the [AI Agent Policy](./AI_AGENTS.md#disclosure)

3. **Respond to feedback**: Maintainers may request changes.

4. **Be patient**: Reviews take time. Maintainers will get to your PR as soon as they can.

## Using AI Agents

AI-assisted contributions are accepted. The maintainer uses coding agents on this project, so it would be strange to ask you not to.

The conditions, in brief:

- **Disclose it** in your pull request — which tool, what it generated, and what you verified yourself
- **Understand what you submit** — you must be able to explain every line without re-prompting the model
- **Build it and run it** — an agent reporting a successful build is not a test result
- **Keep to one concern per PR** — strip out the refactors the agent threw in along the way
- **Respect the protected paths** — signing, entitlements, release scripts, the Xcode project file, CI, dependencies, private APIs, and anything touching credentials are off-limits without discussion first

The full rules, including what agents are explicitly allowed to do, the licensing affirmations you are making, and what happens when the policy is ignored, are in **[AI_AGENTS.md](./AI_AGENTS.md)**.

That document also contains a [Rules for Agents](./AI_AGENTS.md#rules-for-agents) section written for the agent itself — point your tool at it before you start.

## Reporting Bugs

When reporting bugs, please include:

- A clear, descriptive title
- Steps to reproduce the issue
- Expected behavior vs. actual behavior
- Screenshots or error messages if applicable
- Your environment details (OS version, app version, etc.)

Report only bugs you have personally reproduced. If a model helped you write the report, say so — see [AI-Written Issues and Feature Requests](./AI_AGENTS.md#ai-written-issues-and-feature-requests).

## Feature Requests

Feature requests are welcome! Please:

- Check if the feature has already been requested
- Clearly describe the feature and its use case
- Explain why this feature would be valuable to users
- Be open to discussion and alternative approaches

## Getting Help

If you need help or have questions:

- Check the project documentation
- Search existing issues for similar questions
- Open a new issue with the "question" label

---

Thank you for contributing to DynamicNotch! Your efforts help make this project better for everyone.
