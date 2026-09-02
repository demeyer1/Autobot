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

## Top five for this product shape

This is a fit ranking for one specific goal: a personal operating layer centered on native ChatGPT Projects and Voice, with relationship-purpose privacy zones, fail-closed first-party writes, independent destination validation, durable follow-through, and channel-isolated tone profiles. It is not a claim that Autobot has the broadest agent ecosystem. A ranking centered on messaging channels, self-hosting, model choice, or an independent gateway would come out differently.

| Rank | Product shape | Why it ranks here | Main tradeoff |
| --- | --- | --- | --- |
| 1 | **Autobot + native ChatGPT** | Expressly built around the complete target: native Projects and Voice plus the local privacy, authority, external-write, tone-isolation, and completion contract described above. | Pre-release and single-user. Privacy and validator separation are procedural on one Mac, not cryptographic identities or OS isolation. |
| 2 | [**OpenClaw**](https://github.com/openclaw/openclaw) | The strongest standalone gateway fit, with broad channels, nodes, durable tasks, audit tooling, Voice Wake, Codex supervision, and native ChatGPT Computer Use integration. | Adds a separate Gateway and voice/control layer. Its reviewed docs do not specify Autobot's exact relationship-purpose zones and required independent rendered destination validation for every external completion. |
| 3 | [**Row-Bot**](https://github.com/siddsachar/row-bot) | A broad local-first desktop assistant with durable memory, Goal Mode, parent-led agents, checkpoints, exactly-once completion controls, realtime voice, channels, skills, and ChatGPT/Codex provider support. | Uses its own desktop, goal, voice, channel, and Computer Use surfaces rather than native ChatGPT Projects and Voice as the product interface. |
| 4 | [**Hermes Agent**](https://github.com/NousResearch/hermes-agent) | Strong self-improving skills and memory, session search, subagents, scheduled automation, model choice, and a multi-channel messaging gateway. | Primarily a terminal and messaging-gateway product. Its documented voice path emphasizes voice-memo transcription rather than native ChatGPT Voice task orchestration. |
| 5 | [**OwnPilot**](https://github.com/ownpilot/ownpilot) | A substantial self-hosted personal assistant with persistent memory, autonomous agents, crews, 250+ tools, MCP client and server support, browser automation, audit logs, and a voice pipeline. | A separate server and web platform with a larger infrastructure surface. The reviewed docs do not specify Autobot's exact first-party no-attribution write and independent destination-readback contract. |

The alternatives above are real products with strengths Autobot does not try to replace. The ordering is based on fit to this repository's published operating model, not the earlier replacement scores or a universal measure of product quality. See [the full comparison and primary sources](docs/COMPARISON.md).

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
