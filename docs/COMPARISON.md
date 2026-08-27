# AutoAssist and OpenClaw

AutoAssist and OpenClaw solve overlapping problems with different product boundaries.

This comparison treats **AutoAssist plus native ChatGPT** as the product. ChatGPT supplies Projects, Voice, Goals, skills, notifications, scheduled work, and Computer Use. AutoAssist adds the local context, policy, evidence, and completion layer.

OpenClaw is a separate, feature-broad agent gateway with channels, nodes, durable tasks, audit tooling, its own macOS voice layer, and official Codex integrations. It is not accurate to say that OpenClaw cannot use Codex or native ChatGPT Computer Use.

## Ranked fit for the AutoAssist product goal

This is a product-shape ranking, not a universal OSS leaderboard. It weights native ChatGPT Projects and Voice, relationship-purpose privacy zones, fail-closed first-party/no-attribution writes, independent authoritative destination validation, durable follow-through inside user authority, and per-channel tone isolation.

| Rank | Product | Best documented fit | Why it follows AutoAssist on this target |
| --- | --- | --- | --- |
| 1 | **AutoAssist + native ChatGPT** | Native ChatGPT user experience plus the complete local operating contract evaluated here | It is designed around all six target controls. Current limits remain pre-release, single-user, same-Mac procedural isolation, and label-based local validator separation. |
| 2 | [OpenClaw](https://github.com/openclaw/openclaw) | Standalone gateway breadth, channels, nodes, durable tasks, audit, Voice Wake, and official Codex/Computer Use integrations | Separate Gateway/control plane. The primary docs reviewed do not require AutoAssist's exact relationship-purpose zone model or separate rendered destination validator for every external completion. |
| 3 | [Row-Bot](https://github.com/siddsachar/row-bot) | Local-first desktop assistant with deep memory, Goal Mode, bounded parent-led agents, durable checkpoints, exactly-once completion controls, realtime voice, channels, and broad tools | Separate app and native surfaces of its own. ChatGPT/Codex is a provider path, not the native ChatGPT Project and Voice product surface. |
| 4 | [Hermes Agent](https://github.com/NousResearch/hermes-agent) | Self-improving skills, durable memory, session search, subagents, cron, model choice, and messaging channels | Separate terminal/gateway experience. Its README documents voice-memo transcription rather than native ChatGPT Voice orchestration, and no exact equivalent of the AutoAssist write/validation bundle was found in the reviewed primary docs. |
| 5 | [OwnPilot](https://github.com/ownpilot/ownpilot) | Self-hosted personal platform with agents, crews, persistent memory, MCP client/server, browser automation, audit, 250+ tools, and voice input/output | Separate server/web platform and broader infrastructure footprint. Its reviewed README does not specify the same first-party no-attribution route plus required independent rendered destination readback. |

The earlier HQ-replacement evaluation used a different baseline and its scores are not reused here. A ranking centered on maximum channel breadth, independent self-hosting, model portability, or always-on gateway operation could put one of the alternatives first.

### Primary evidence for ranks 3 through 5

- [Row-Bot official repository](https://github.com/siddsachar/row-bot): local-first desktop architecture, durable memory, Goal Mode, child-agent orchestration, checkpoints, exactly-once completion, realtime voice, messaging channels, provider routing, skills, tools, and desktop installers.
- [Hermes Agent official repository](https://github.com/NousResearch/hermes-agent): self-improving skills and memory, cross-session search, multi-channel gateway, scheduled work, isolated subagents, provider choice, and voice-memo transcription.
- [OwnPilot official repository](https://github.com/ownpilot/ownpilot): self-hosted platform, autonomous and crew agents, persistent memory, MCP client/server, browser agent, tool audit, voice pipeline, and broad built-in tools.

The detailed comparison below focuses on OpenClaw because it is the highest-ranked standalone alternative for this target and now has official Codex supervision and native ChatGPT Computer Use integration.

## At a glance

| Dimension | AutoAssist + native ChatGPT | OpenClaw |
| --- | --- | --- |
| Primary experience | Native ChatGPT desktop, Projects, Voice, Work, and Codex | Separate Gateway, agents, clients, channels, nodes, and plugins |
| Project context | Local ChatGPT Project with auto-discovered `AGENTS.md`, skills, and `config.toml` | OpenClaw workspaces, sessions, memory files, Gateway configuration, and plugins |
| Voice | Native ChatGPT Voice can start and monitor separate long-running threads and use Remote on paired iOS | Its own macOS Voice Wake, push-to-talk, and Talk Mode |
| Long-running work | Native Goals plus local AutoAssist objective, stage, evidence, liveness, and recovery state | Durable SQLite tasks, sweeper/reconciliation, delivery state, and cron |
| Computer Use | Native ChatGPT Computer Use with an AutoAssist first-party-write and rendered-readback policy | Official plugin can use the same native ChatGPT/Codex Computer Use server |
| Memory | Project context and optional Codex memory plus AutoAssist canonical records, provenance, and privacy zones | Markdown memory, daily notes, optional DREAMS, and search |
| Privacy model | Explicit `PRIVATE`, `FAMILY_FRIENDS`, `WORK`, and opt-in `SHARED` retrieval policy | Workspace/filesystem separation and documented security controls |
| External writes | Fail-closed first-party UI route with preflight and rendered postflight | Shared outbound boundary and metadata audit, with documented bypass coverage limits for some direct/plugin paths |
| Completion | Distinct producer and validator labels, ordered evidence stages, and required authoritative destination readback | Durable task lifecycle, delivery state, and audit metadata |
| Tone profiles | Separate opt-in profiles by channel and audience, using compact patterns rather than raw archives by default | Persona and workspace instructions; no equivalent channel-specific learning and exclusion policy was found in the primary docs reviewed for this release |
| Deployment | ZIP into a native ChatGPT local Project, with a guided under-30-minute target | Installer plus runtime, model authentication, Gateway, agent, channel, and optional Codex setup |

## Where AutoAssist is deliberately different

### ChatGPT stays the interface

AutoAssist does not ask the user to adopt a second agent control plane. The local Project is the workspace, Voice is the conversational surface, Goal mode carries long-running work, skills package repeatable workflows, and Computer Use handles visual app interaction.

OpenClaw now has official Codex supervision, Codex harness, and native Computer Use plugins. The distinction is product shape and default workflow, not basic compatibility.

Sources: [ChatGPT Projects](https://learn.chatgpt.com/docs/projects), [ChatGPT Voice](https://learn.chatgpt.com/docs/features/voice), [OpenClaw Codex supervision](https://github.com/openclaw/openclaw/blob/main/docs/plugins/codex-supervision.md), [OpenClaw Computer Use](https://github.com/openclaw/openclaw/blob/main/docs/plugins/codex-computer-use.md)

### Privacy follows relationship and purpose

AutoAssist gives personal, family and friends, work, and deliberately shared context separate canonical zones. Ordinary work must read only the zone relevant to the current assignment. Cross-zone reuse is explicit and minimal.

This is a policy and folder-permission boundary within one macOS account. It is not stronger than a separate OS account, container, or machine. OpenClaw also documents its filesystem as a trust boundary and recommends separate OS users or hosts for strict isolation.

Sources: [AutoAssist Privacy](../PRIVACY.md), [OpenClaw memory](https://github.com/openclaw/openclaw/blob/main/docs/concepts/memory.md)

### Completion needs an independent check

An AutoAssist worker can report evidence but cannot certify the same stage using the same identity label. Stages advance in order. For an external artifact or action, the operating contract requires the validator to inspect the authoritative destination instead of accepting a tool call, open editor, or generic saved indicator.

The current local runtime enforces label separation, stage order, and evidence hashes. It does not create a hardware trust boundary or prove that a label corresponds to a separate human. The quality of the result still depends on fresh, authoritative readback.

OpenClaw documents durable task records, stale/lost detection, delivery state, and a metadata audit ledger. In the primary sources reviewed here, AutoAssist did not find a documented OpenClaw requirement that every external completion be certified by a distinct validator after authoritative destination readback. That is a documentation finding, not proof that a custom OpenClaw workflow cannot add it.

Sources: [OpenClaw tasks](https://github.com/openclaw/openclaw/blob/main/docs/automation/tasks.md), [OpenClaw audit](https://github.com/openclaw/openclaw/blob/main/docs/cli/audit.md), [AutoAssist Architecture](ARCHITECTURE.md)

### External actions fail closed

AutoAssist uses connectors and structured tools for authorized reads. Recipient-visible writes normally go through the signed-in first-party interface in native Computer Use. The operating contract requires the active ChatGPT workflow to check the exact account, destination, and visible content before action, then check the rendered result for the intended change, duplicates, failure state, and unwanted AI attribution.

If the route forces a non-removable label or the destination cannot be verified, the operating contract requires the active ChatGPT workflow to leave the task incomplete. This does not remove immutable platform metadata or bypass OpenAI and macOS approvals.

OpenClaw has a meaningful outbound audit boundary. Its own audit documentation notes that plugin-local or direct-send paths may bypass that boundary and that the absence of an audit row does not prove no message was sent.

Sources: [AutoAssist Security](../SECURITY.md), [OpenClaw audit](https://github.com/openclaw/openclaw/blob/main/docs/cli/audit.md), [ChatGPT Computer Use](https://learn.chatgpt.com/docs/computer-use)

### Tone remains channel-specific

AutoAssist separates communication profiles by channel and audience. The package supports profiles such as work-external email, work-internal chat, and family/friends text. It learns only from samples the user authorizes, keeps compact derived patterns by default, and does not treat writing style as permission to send.

The profile model is included in `00_CONTEXT/COMMUNICATION-PROFILES.md`. Channel-specific collection and deterministic checking depend on the corresponding installed workflow. The pre-release package does not claim automatic learning across every channel.

## Where OpenClaw documents broader coverage

- A standalone multi-channel Gateway and node runtime. [Repository](https://github.com/openclaw/openclaw)
- Its own macOS Voice Wake, push-to-talk, and Talk Mode. Voice Wake currently requires macOS 26+ and local Apple Speech language support. [Voice Wake](https://github.com/openclaw/openclaw/blob/main/docs/platforms/mac/voicewake.md)
- Durable shared tasks with restart survival, sweep/reconciliation, and delivery state. [Tasks](https://github.com/openclaw/openclaw/blob/main/docs/automation/tasks.md)
- Persistent cron execution and logs. [Cron](https://github.com/openclaw/openclaw/blob/main/docs/automation/cron-jobs.md)
- Published Gateway security guidance and a metadata-only audit ledger. [Security](https://github.com/openclaw/openclaw/blob/main/docs/gateway/security/index.md), [Audit](https://github.com/openclaw/openclaw/blob/main/docs/cli/audit.md)
- Official installer, onboarding, model authentication, and Codex plugin flows. [Installer](https://github.com/openclaw/openclaw/blob/main/docs/install/installer.md), [Onboarding](https://github.com/openclaw/openclaw/blob/main/docs/start/onboarding.md), [Codex harness](https://github.com/openclaw/openclaw/blob/main/docs/plugins/codex-harness.md)

## Choosing based on product shape

AutoAssist is built for a user who wants native ChatGPT Projects and Voice to remain the center of the experience, with local privacy routing and stricter completion and external-action rules.

OpenClaw documents a broader standalone runtime for users who need many channels, nodes, an independent Gateway, or its own always-on macOS voice layer.

Neither architecture eliminates model errors, prompt injection, permissions, authentication, host availability, usage limits, or third-party platform behavior.

## Claim boundaries

AutoAssist does not claim that it is:

- more secure than OpenClaw in every deployment;
- cryptographically isolated inside one macOS account;
- guaranteed to keep all content off OpenAI systems;
- able to remove immutable third-party attribution;
- able to force work through authentication, permission, or user-decision gates;
- already verified as a sub-30-minute install on every supported Mac;
- a general automatic tone-learning engine for every channel;
- a multi-tenant service or enterprise RBAC system.

## Primary sources

### OpenAI

- [ChatGPT desktop app](https://learn.chatgpt.com/docs/app)
- [Projects](https://learn.chatgpt.com/docs/projects)
- [Voice](https://learn.chatgpt.com/docs/features/voice)
- [Long-running work](https://learn.chatgpt.com/docs/long-running-work)
- [Computer Use](https://learn.chatgpt.com/docs/computer-use)
- [Permission modes](https://learn.chatgpt.com/docs/permission-modes)
- [Skills and plugins](https://learn.chatgpt.com/docs/skills-and-plugins)
- [Scheduled tasks](https://learn.chatgpt.com/docs/automations)
- [Memories](https://learn.chatgpt.com/docs/customization/memories)

### OpenClaw

- [Official repository](https://github.com/openclaw/openclaw)
- [Installer](https://github.com/openclaw/openclaw/blob/main/docs/install/installer.md)
- [Onboarding](https://github.com/openclaw/openclaw/blob/main/docs/start/onboarding.md)
- [Codex supervision](https://github.com/openclaw/openclaw/blob/main/docs/plugins/codex-supervision.md)
- [Codex harness](https://github.com/openclaw/openclaw/blob/main/docs/plugins/codex-harness.md)
- [Native Codex Computer Use integration](https://github.com/openclaw/openclaw/blob/main/docs/plugins/codex-computer-use.md)
- [macOS Voice Wake](https://github.com/openclaw/openclaw/blob/main/docs/platforms/mac/voicewake.md)
- [Memory](https://github.com/openclaw/openclaw/blob/main/docs/concepts/memory.md)
- [Durable tasks](https://github.com/openclaw/openclaw/blob/main/docs/automation/tasks.md)
- [Cron jobs](https://github.com/openclaw/openclaw/blob/main/docs/automation/cron-jobs.md)
- [Audit](https://github.com/openclaw/openclaw/blob/main/docs/cli/audit.md)
- [Gateway security](https://github.com/openclaw/openclaw/blob/main/docs/gateway/security/index.md)

**Evidence date:** 2026-08-26. Product behavior can change. Follow the linked primary documentation for the current version.
