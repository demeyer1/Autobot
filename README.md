# Autobot

**AutoBot: a self-improving agentic harness that makes frontier AI better at finishing complex knowledge work.**

AutoBot achieved **18.5% higher task completion than the published OpenAI Sol Max baseline**, surpassing **Anthropic’s Claude Opus 5 Max** on OSWorld 2.0, a benchmark of long, multi-application workflows. It also reached **#1 on the official AssistantBench hidden-test leaderboard**. [Results and methodology](https://github.com/demeyer1/Autobot/tree/main/benchmarks)

**Hard workflows become upgrades to the agent itself.** AutoBot repairs its own harness, independently validates the changes, and carries them forward. The next workflow inherits the improvement. **Compounding capability, without retraining the model.**

**Your knowledge outgrows the context window.** Hierarchical memory lives on disk; task-specific retrieval builds the working context. Nightly consolidation integrates new knowledge and corrections. Your agent accumulates institutional memory across projects and conversations.

**Your project can outlive the agent working on it.** Persistent task graphs, atomic checkpoints and independent supervision let a replacement worker resume the assignment. Completion is bound to current requirements and verified destination evidence.

**Local compute makes persistent intelligence economical.** Your CPU handles orchestration, state and integrity checks. Compiled context and reusable proofs reduce repeated inference, directing the model’s budget toward the difficult judgments that move work forward.

Open source. Native ChatGPT on your Mac. Built by [Autonomous Production](https://autoprod.ai). [Get AutoBot](https://github.com/demeyer1/Autobot/releases).

## Benchmarks

### AssistantBench

**#1 on the recorded official hidden-test leaderboard: 50.70% accuracy across 181 tasks.**

[![AssistantBench leaderboard with AutoBot’s result highlighted in red](docs/benchmark-charts/assistantbench-highlighted.png)](benchmarks/assistantbench/)

<sub>AutoAssist was the harness's previous brand name, changed to AutoBot.</sub>

[Results and verification](benchmarks/assistantbench/)

### OSWorld 2.0

**32.41% binary accuracy and 64.28% partial accuracy across 108 tasks.** Final best-valid-per-task aggregate, compared with the published September 10, 2026 leaderboard snapshot.

[![OSWorld 2.0 comparison with AutoBot’s result highlighted in red](docs/benchmark-charts/osworld-2.0-highlighted.png)](benchmarks/osworld-2.0/)

[Results and methodology](benchmarks/osworld-2.0/)

## What it changes

- **Privacy by relationship and purpose.** Personal, family and friends, work, and deliberately shared context have separate zones. Nothing moves into `SHARED` automatically.
- **Independent completion.** The local runtime rejects validation under the producer label. The operating contract also requires a separate validator to inspect current evidence, including the real destination when the task changes something outside the workspace.
- **Durable follow-through.** Native ChatGPT Goals keep the active work moving. Autobot keeps the objective, stages, evidence, and recovery state on disk so an interrupted chat does not silently erase the commitment.
- **Clean external actions.** Recipient-visible writes use the signed-in first-party app through Computer Use. The operating contract requires the active ChatGPT workflow to verify the account, destination, and visible content before the action, then check the rendered result for a duplicate, failure, or unwanted AI attribution. If the clean route cannot be verified, the workflow must stop.
- **Tone that stays in its lane.** Communication profiles are separated by channel and audience. A family text profile does not become a work email profile. Autobot stores compact, user-approved patterns rather than raw message archives by default.

## What Autobot includes

Autobot is the combination of two layers:

1. **Native ChatGPT:** the desktop app, local Projects, Voice, Goals, skills and plugins, scheduled work, notifications, and Computer Use.
2. **The Autobot workspace:** the operating contract in `AGENTS.md`, privacy zones, selective memory, project status, a local objective state machine, a one-minute liveness supervisor, external-action policy, and first-time setup.

Autobot is not a separate model, chatbot, or agent gateway. It depends on current ChatGPT capabilities and their plan, region, usage, sandbox, and permission limits. See [Architecture](docs/ARCHITECTURE.md) and [Permissions](docs/PERMISSIONS.md).

## Autobot compared with OpenClaw and Hermes

This comparison evaluates Autobot plus native ChatGPT for one person managing personal and work tasks on a Mac. "Better" means a more explicit default for the stated user need, based on the published design; it does not mean a measured advantage in accuracy, speed, or reliability. "Doesn't do" means the specific built-in requirement was not found in the primary documentation reviewed on September 10, 2026. Both alternatives can be extended.

| | Top 3 shared capabilities: Autobot's approach and user benefits | Top 3 additional Autobot capabilities and user benefits |
| --- | --- | --- |
| [**OpenClaw**](https://github.com/openclaw/openclaw) | **1. Remember context with explicit boundaries.** OpenClaw persists and searches memory. Autobot adds default personal, family/friends, work, and opt-in shared zones. This makes the rules for reusing private context in a work task more explicit. [Memory](https://docs.openclaw.ai/concepts/memory) / [Autobot privacy](PRIVACY.md).<br><br>**2. Track the promised outcome.** OpenClaw records background tasks and delivery state. Autobot assigns each promised output an owner, destination, and completion gate. This gives the user a clearer record of what remains owed after an interruption. [Tasks](https://docs.openclaw.ai/automation/tasks) / [Autobot contract](AGENTS.md#projects-and-unfinished-work).<br><br>**3. Check the result of an app action.** OpenClaw supports tools and outbound audit history. Autobot requires account, destination, and content checks before a write, followed by rendered inspection. This adds an explicit check for a wrong destination, failed save, or duplicate action. [Audit](https://docs.openclaw.ai/gateway/audit) / [Autobot writes](AGENTS.md#external-reads-and-writes). | **1. Require a separate completion validator.** Autobot's five-stage process requires current evidence and a validator label different from the producer, with destination readback for external work. This gives users evidence beyond the worker's own success report. [Completion](AGENTS.md#completion-integrity).<br><br>**2. Block writes when clean delivery cannot be verified.** Autobot's default policy requires first-party Computer Use and stops a route that forces unwanted attribution. This gives users an explicit publication rule instead of relying on each connector's behavior. [Write policy](AGENTS.md#external-reads-and-writes).<br><br>**3. Keep learned tone separate by channel and audience.** Autobot requires authorized examples and compact, separate communication profiles. This helps keep a family-text style from shaping a customer email. [Profiles](00_CONTEXT/COMMUNICATION-PROFILES.md). |
| [**Hermes**](https://github.com/NousResearch/hermes-agent) | **1. Remember context with purpose-specific retrieval.** Hermes has curated memory, user profiles, and session search. Autobot makes relationship and purpose part of its default retrieval rules. This gives users clearer control over which personal facts may inform professional work. [Memory](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory) / [Autobot privacy](PRIVACY.md).<br><br>**2. Follow work through to its deliverable.** Hermes schedules jobs and delivers their outputs. Autobot also retains the objective, ordered evidence stages, and unfinished outputs. This makes it easier to distinguish a job that ran from a requested artifact that was saved and checked. [Scheduling](https://hermes-agent.nousresearch.com/docs/user-guide/features/cron) / [Autobot completion](AGENTS.md#completion-integrity).<br><br>**3. Verify user-visible changes.** Hermes provides tool approvals and execution controls. Autobot adds a standard before-and-after inspection of the signed-in destination. This gives the user a specific check that an authorized action produced the intended visible result. [Security](https://hermes-agent.nousresearch.com/docs/user-guide/security) / [Autobot writes](AGENTS.md#external-reads-and-writes). | **1. Require independent acceptance of every completion stage.** Autobot separates the producer and validator labels and requires fresh destination evidence for external outputs. This makes an unsupported "done" report insufficient under the operating contract. [Completion](AGENTS.md#completion-integrity).<br><br>**2. Require a clean first-party write route by default.** Autobot checks the exact account and visible content, then rejects forced-attribution or unverifiable delivery routes. This gives users a consistent rule for communications across services. [Write policy](AGENTS.md#external-reads-and-writes).<br><br>**3. Require audience-specific tone-learning boundaries.** Hermes supports personality and user-style preferences; Autobot specifies separately authorized profiles for each channel and audience. This gives users more explicit control over which examples shape each kind of message. [Hermes memory](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory) / [Autobot profiles](00_CONTEXT/COMMUNICATION-PROFILES.md). |

These are operating-contract differences, not guarantees of error-free execution. Autobot's privacy zones and validator separation are procedural within one Mac; they are not OS isolation or cryptographic identities. OpenClaw and Hermes offer broader standalone deployment, messaging, and model choices. The absence findings above concern the exact required workflows, not an absence of memory, privacy controls, voice, verification tools, or automation in either project.

## What is new in 0.3.0

The project-local first-time skill now acts as the setup operator. It checks current state, applies safe local defaults, runs supported actions, preserves the earliest unresolved user or capability gate, and returns to the user's original task only after current marker and status readback.

The base folder installs without Node or sign-in. The advanced runtime needs Node 22 or newer. Native app capabilities are discovered separately; no model, account, notification recipient or external write is configured for you. See [capabilities and availability](docs/CAPABILITIES.md).

## Privacy zones

| Zone | Intended context | Default boundary |
| --- | --- | --- |
| `PRIVATE` | Sensitive personal facts, preferences, health, finances, and private plans | Never shared automatically |
| `FAMILY_FRIENDS` | Relationships, events, logistics, and authorized personal communication patterns | Never used for work without a current explicit need |
| `WORK` | Organizations, projects, teammates, customers, vendors, and professional communication patterns | Never used for personal communication unless explicitly relevant |
| `SHARED` | The minimum facts you deliberately make reusable across zones | Opt-in only, with provenance |

These are owner-only folders and operating rules inside one macOS account. They are not separate encrypted vaults, macOS users, or hardware security boundaries. Use separate macOS accounts or separate machines when the trust domains require stronger isolation. Read [Privacy](PRIVACY.md).

## Completion that requires evidence

Each durable objective moves through five ordered stages:

1. `research_complete`
2. `draft_complete`
3. `destination_updated`
4. `save_confirmed`
5. `rendered_readback_verified`

The local runtime enforces stage order, evidence hashes, and a validator label different from the producer label. The operating contract requires a genuinely separate validator to use fresh evidence and inspect the authoritative destination for external work.

This is procedural independence on one Mac, not a separate security enclave. Autobot cannot bypass a login, MFA, macOS permission, plan limit, user decision, or the scope of the user's instruction. The supervisor records liveness and flags stalled objectives. It does not control desktop apps in the background or manufacture permission to continue.

## No-attribution, fail-closed writes

Autobot treats connectors, apps, MCP tools, browser integrations, and APIs as read-only unless a destination-specific adapter proves the same clean-write properties. Recipient-visible writes normally use the signed-in first-party interface through native ChatGPT Computer Use.

Before a live write, the operating contract requires the active ChatGPT workflow to check the app, account, destination, scope, and final visible content. Afterward, the workflow must inspect the rendered result and check for the intended mutation, no duplicate, no failure, and no added AI or ChatGPT attribution. If a platform forces a non-removable label or the result is ambiguous, the workflow must not claim success.

That policy cannot remove immutable metadata or disclosures controlled by a third-party platform. Details: [Security](SECURITY.md).

## Native Voice and long-running work

[ChatGPT Voice](https://learn.chatgpt.com/docs/features/voice) can start separate threads for longer tasks, check them, send follow-ups, and bring progress or blockers back into the voice conversation. [Goal mode](https://learn.chatgpt.com/docs/long-running-work) keeps the outcome and completion criteria attached to the work.

Important limits:

- Voice availability, usage, and rollout depend on the ChatGPT plan and workspace.
- Only one voice chat can be active across desktop at a time.
- Tasks started from Voice also use the Codex usage budget.
- Local long-running work needs the Mac and workspace to remain available. Enable **Prevent sleep while running** when appropriate.
- Starting a Goal does not broaden sandbox access or approval authority.

## Commands

```zsh
./runtime/bin/autoassist doctor
./runtime/bin/autoassist version
./runtime/bin/autoassist core status
./runtime/bin/autoassist core help
```

Run `./runtime/bin/autoassist help` for the complete local command list.

`privacy-scan` is a clean release-candidate check, not a post-install scan of a populated user workspace. Run it only before user configuration or against a separate clean release tree.

## Read next

- [Install](#setup-and-installation)
- [Permissions](docs/PERMISSIONS.md)
- [Capabilities and availability](docs/CAPABILITIES.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Local runtime reference](docs/CLI-REFERENCE.md)
- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)
- [Autobot and OpenClaw](docs/COMPARISON.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Current status

Autobot `0.4.0` is an early public release for a single user on a Mac. The package is not a multi-tenant service, an OS sandbox, a cryptographic privacy boundary, or a guarantee that every third-party action will succeed. Treat a downloadable ZIP as verified only when its checksum and manifest match the adjacent release artifacts and the packaged candidate passes the bundled release checks.

## License

Autobot is available under the [MIT License](LICENSE). Copyright (c) 2026 Autobot contributors.

## Setup and installation

Set up AutoBot on your MacBook, then use it from your phone.

For a local-only first task, use the [minimal installation path](docs/INSTALL.md#start-a-local-project). Computer Use, Mac permissions, phone access and connected apps in the steps below are optional enhancements, not prerequisites for local work.

### 1 Get the Mac app for Codex

On your MacBook, [download OpenAI's desktop app](https://learn.chatgpt.com/docs/app), sign in, and select **Codex**. The download is called **ChatGPT**, with Codex inside it.

### 2 Choose your plan

AutoBot is free, but regular use will likely need a [paid ChatGPT plan](https://learn.chatgpt.com/docs/pricing); choose one that fits your needs.

### 3 Let it use your Mac

In **Plugins > Computer Use**, choose **Install** or **Enable** and turn on its server and skill switches. In your Mac's **System Settings > Privacy & Security**, enable the named OpenAI app or helper for:

- **Screen Recording** or **Screen & System Audio Recording** to see your screen.
- **Accessibility** to click and type.
- **Microphone** to talk with you.
- **Automation**, when requested, to work with the named app.
- **Files and Folders**, when requested, to use the folders you select.

Stay at your MacBook and plan for at least three permission-related app restarts during first setup; the number varies. Reopen the app after each prompt and continue.

### 4 Set your everyday preferences

Open **Settings** with **Command + comma** and choose these [preferences](https://learn.chatgpt.com/docs/reference/settings):

- **General > Prevent sleep while running: On.** Keep the MacBook plugged in, online, and open for remote work.
- **Notifications: On** for finished tasks and questions.
- **General > Permissions:** enable your choice, then select it below the message box. **Full access** allows broad file and internet actions; **Approve for me** (Auto-review) reviews requests automatically; **Ask for approval** brings requests to you.
- **Computer Use:** choose your apps; **Always allow** lets it reuse them.
- **Model menu:** try **Sol**, **Max** reasoning, and **Fast off**; change these anytime.

### 5 Download AutoBot

Open the [AutoBot release](https://github.com/demeyer1/Autobot/releases/tag/v0.4.0) and download **AutoAssist-v0.4.0.zip**, **AutoAssist-v0.4.0.zip.sha256**, and **AutoAssist-v0.4.0.manifest.sha256**. Keep them together and double-click the ZIP to open the download. The [install guide](docs/INSTALL.md#download-and-install) shows both verification commands.

### 6 Start inside a project

Create a **local project** called **AutoBot** in Codex, choose the downloaded **AutoAssist** folder, and start a task there. Paste: “Install AutoBot from https://github.com/demeyer1/Autobot using INSTALL_FOR_AI.md, including required support software from official sources, then guide setup.”

### 7 Point the project at your installed AutoBot

After installation, choose **Edit project > Add folder**, select **AutoAssist** in your Mac's home folder, and choose **Make primary**. Start a fresh task there: “Run first-time setup for this installed folder.”

### 8 Connect your phone

Install the **ChatGPT mobile app**, sign in to the same account and workspace, and on your Mac open **Settings > Connections > Control this Mac or PC > Set up**. Scan the QR code, finish verification, and open **Remote** on your phone.

### 9 Add Chrome

Open **Settings > Computer Use > Chrome > Install** and add the [ChatGPT extension](https://learn.chatgpt.com/docs/chrome-extension) to your chosen Chrome profile. Return to settings and check for **Manage**.

### 10 Connect your everyday apps

Tell AutoBot, “Connect and test my email, calendar, Slack, and iMessage,” then sign in to your chosen accounts, including **Messages on your Mac**. Use available plugins for reading and Computer Use in the signed-in apps for sending.

### 11 Try your first task

On your phone, open **Remote > AutoBot** and ask, “Make and save tomorrow's to-do list.” Open the result, then try voice.

### Three tips and tricks

1. **Give it a useful Chrome profile.** Choose one with the logins, passwords, and autofill you want it to use, and ask it to connect your usual apps.
2. **Teach it how you sound.** Share a few example messages, correct its drafts, and save separate styles for customers, teammates, and friends.
3. **Explain your boundaries.** Explain what belongs to work, personal life, or both, which accounts to use, and when each tone applies.

### Privacy and safety

- **Keep sensitive work in your hands.** Require your approval for private or sensitive access, sharing, and changes, plus a standalone third-party authenticator app on a separate device AutoBot cannot access, mirror, or sync; SMS or iMessage alone doesn't meet that boundary.
- **Make the challenge real.** A saved login can bypass a new sign-in challenge, and AutoBot doesn't add one to every action; use services that require fresh verification for sensitive actions, or keep those accounts disconnected and handle them yourself.
- **Choose what stays separate.** Keep highly sensitive files and accounts outside AutoBot's connected folders and Chrome profile, and store recovery codes on the separate device or offline.
- **Choose where your data goes.** Review ChatGPT's data controls and connected services before adding private material, and keep a backup of your workspace; a local folder doesn't mean every request stays on your Mac.

### If you need a hand later

- **Setup paused:** reopen the same project and say, “Continue first-time setup from where we left off.”
- **Something isn't working:** say, “Check my AutoBot setup and help me fix what's missing.”
- **Remote is missing:** update both apps and check that your phone and Mac use the same account and workspace.
- **Update or remove it:** say, “Help me update AutoBot,” or “Remove AutoBot and keep my files recoverable.”

Setup references: [Mac permissions](https://learn.chatgpt.com/docs/computer-use), [permission choices](https://learn.chatgpt.com/docs/permission-modes), [phone pairing](https://learn.chatgpt.com/docs/remote-connections), and [MFA guidance](https://www.cisa.gov/audiences/small-and-medium-businesses/secure-your-business/require-multifactor-authentication).

<details>
<summary>For ChatGPT: automated installation</summary>

If the user asks you to install this repository, read [INSTALL_FOR_AI.md](INSTALL_FOR_AI.md) first. It contains the commands, local project setup, verification and resume instructions.

The user can start with: “Go to https://github.com/demeyer1/Autobot and install AutoBot in a new local project, following INSTALL_FOR_AI.md.”

</details>
