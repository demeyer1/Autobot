# Autobot

Autobot adds a local operating layer to native ChatGPT. You keep the ChatGPT desktop app, Projects, Voice, long-running work, skills, and Computer Use. Autobot adds durable context, privacy zones, unfinished-work tracking, independent completion checks, and stricter rules for external actions.

Autobot is an open-source product from its parent company, [Autonomous Production](https://autoprod.ai).

It is built for one person using a Mac, especially when family, friends, and work all need to stay useful without bleeding into one another.

Autobot is open source under the [MIT License](LICENSE).

## AssistantBench: #1

Autobot ChatGPT-HQ + GPT-5.6 Sol Ultra is ranked **#1** on the official AssistantBench test leaderboard at rendered verification. It scored **50.70% accuracy** with a **100.0% answer rate** across all 181 hidden-test tasks.

[![AssistantBench leaderboard showing Autobot in the top position at 50.70% accuracy](https://raw.githubusercontent.com/demeyer1/Autobot/main/docs/assistantbench-leaderboard-autoassist-number-one-2026-09-01.png)](https://huggingface.co/spaces/AssistantBench/leaderboard)

- Official score: **50.70% accuracy**
- Official position: **#1**
- Coverage: **181/181 hidden-test tasks**
- Answer rate: **100.0%**

The result was produced by Autobot's custom research harness and scored by the official AssistantBench hidden evaluator. [Open the live leaderboard](https://huggingface.co/spaces/AssistantBench/leaderboard). New submissions may require clicking the leaderboard's **Refresh** control before they appear.

<details>
<summary>Verification details</summary>

- Precision: **50.7%**
- Exact match: **27.1%**
- Easy accuracy: **88.0%**
- Medium accuracy: **67.7%**
- Hard accuracy: **39.7%**
- Missing or nonterminal answers: **0**
- Submission artifact SHA-256: `af99212a3c5b5045705fcd6f6b762642257447796ca85b6923e6f11906a97991`
- Submission identity SHA-256: `94d234df96c44c182c1d8a0309ce65f35b2c7cd6e011ea99d0e8880c4dce0085`

The first UI attempt exposed a path-safety problem in the model-name metadata. We fixed the metadata guard, reran the live collision and artifact checks, and submitted the unchanged verified 181-row artifact under the corrected model name. Hidden-test answers are not published.

</details>

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

## Target: ZIP to a working project in under 30 minutes

The setup is designed to fit inside 30 minutes on a supported Mac:

1. Install and sign in to the current [ChatGPT desktop app](https://learn.chatgpt.com/docs/app).
2. Download the Autobot ZIP from an official release and extract it.
3. Double-click `Install.command`. The default destination is `~/AutoAssist`.
4. Open `~/AutoAssist` as the primary folder of a new local ChatGPT Project.
5. Start a new chat and ask ChatGPT to run the `first-time` skill.
6. Choose the privacy zones and communication profiles you want, then grant only the macOS and per-app permissions required for your workflows.
7. Run `./runtime/bin/autoassist doctor` from the installed folder.

The local file installation is automated, and the package test fails if that local step takes 30 minutes or more in its isolated test environment. ChatGPT download time, account sign-in, plan availability, macOS permission prompts, and first-time choices can change the full setup time. Version `0.1.0` is pre-release, so a ZIP-to-ready claim still needs a clean-Mac timing receipt from the exact release candidate.

The current ChatGPT download page labels the macOS build for Apple silicon. OpenAI's documentation reviewed for this release does not publish a minimum macOS version, so check the [current app page](https://learn.chatgpt.com/docs/app) before installation.

Full instructions: [Install Autobot](docs/INSTALL.md)

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
./runtime/bin/autoassist objective-status
```

Run `./runtime/bin/autoassist help` for the complete local command list.

`privacy-scan` is a clean release-candidate check, not a post-install scan of a populated user workspace. Run it only before user configuration or against a separate clean release tree.

## Read next

- [Install](docs/INSTALL.md)
- [Permissions](docs/PERMISSIONS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)
- [Autobot and OpenClaw](docs/COMPARISON.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Current status

Autobot `0.1.0` is an early public release for a single user on a Mac. The package is not a multi-tenant service, an OS sandbox, a cryptographic privacy boundary, or a guarantee that every third-party action will succeed. Treat a downloadable ZIP as verified only when its checksum and manifest match the adjacent release artifacts and the packaged candidate passes the bundled release checks.

## License

Autobot is available under the [MIT License](LICENSE). Copyright (c) 2026 Autobot contributors.
