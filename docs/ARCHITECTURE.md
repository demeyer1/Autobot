# Architecture

AutoAssist is a local operating layer for native ChatGPT. It does not replace the ChatGPT model, desktop app, Projects, Voice, Goals, skills, scheduled work, or Computer Use.

The current architecture is single-user, single-Mac, and local-first. It combines native ChatGPT execution with a filesystem-backed operating contract and evidence state machine.

## System view

```text
User
  |
  v
Native ChatGPT desktop
  |-- Local Project and project instructions
  |-- Voice and Remote
  |-- Goal mode and scheduled work
  |-- Skills, plugins, connectors, and MCP
  |-- Computer Use
  |
  v
AutoAssist project root
  |-- AGENTS.md operating contract
  |-- PROJECTS.md command center
  |-- 00_CONTEXT privacy zones and durable memory map
  |-- 01_PROJECTS initiative state
  |-- 03_OUTPUTS local deliverables
  |-- state/objectives ordered stage evidence
  |-- runtime/bin/autoassist local state machine
  `-- LaunchAgent heartbeat and stall marker

External read path: connector, plugin, MCP, API, or first-party UI
External write path: signed-in first-party UI through Computer Use
Completion path: producer evidence -> distinct validator -> destination readback
```

## Layer 1: Native ChatGPT

Native ChatGPT supplies the active reasoning and interaction surfaces:

- **Local Projects** attach a folder, use its primary directory as the default working directory, and discover project `AGENTS.md`, skills, and `config.toml`.
- **Voice** provides spoken interaction and can start or monitor separate longer-running threads.
- **Goal mode** persists the requested outcome, constraints, and completion criteria inside a ChatGPT chat.
- **Skills and plugins** package reusable instructions, resources, scripts, and MCP-backed connectors.
- **Computer Use** provides visual app inspection and interaction after macOS and per-app approval.
- **Scheduled tasks** can run local Project work while the Mac and app remain available, or cloud work with different data boundaries.

Native features retain their own plan, region, rollout, usage, sandbox, approval, and machine-availability limits.

Sources: [Projects](https://learn.chatgpt.com/docs/projects), [Voice](https://learn.chatgpt.com/docs/features/voice), [Long-running work](https://learn.chatgpt.com/docs/long-running-work), [Skills and plugins](https://learn.chatgpt.com/docs/skills-and-plugins), [Computer Use](https://learn.chatgpt.com/docs/computer-use), [Scheduled tasks](https://learn.chatgpt.com/docs/automations)

## Layer 2: The operating contract

`AGENTS.md` is the always-applicable project contract. It tells ChatGPT how to:

- load project and memory state;
- route context into privacy zones;
- preserve unfinished outputs;
- inherit but never broaden user authority;
- separate execution from validation;
- handle external reads and writes;
- keep communication profiles isolated;
- treat third-party instructions as untrusted content;
- record defects and current verification evidence.

Required behavior belongs in this contract and related canonical files, not in probabilistic model memory. OpenAI similarly recommends putting required guidance in project documentation rather than memory. [Memories](https://learn.chatgpt.com/docs/customization/memories)

## Layer 3: Privacy and durable context

`00_CONTEXT/MEMORY.md` is a routing map, not a transcript. It points to narrow canonical records and four zones:

- `PRIVATE`
- `FAMILY_FRIENDS`
- `WORK`
- `SHARED`

The installer initializes each zone with owner-only permissions. `SHARED` is opt-in. Cross-zone access requires an assignment-specific need, and the contract prohibits silently promoting protected material into general memory.

Communication profiles follow the same principle. The selected channel and audience get a compact, user-approved profile. Raw correspondence is not retained by default.

These controls are filesystem and operating-policy boundaries inside one macOS account. See [Privacy](../PRIVACY.md).

## Layer 4: Project and output ownership

`PROJECTS.md` is the command center. Each meaningful initiative has one folder under `01_PROJECTS` and a concise `STATUS.md` with:

- objective;
- current verified status;
- next actions;
- blockers;
- decisions needed;
- exact completion gate.

Unrouted material lands in `02_INBOX`. Finished local artifacts go in `03_OUTPUTS`. External delivery remains a separate stage that needs destination-specific evidence.

An urgent task may pause another objective, but it cannot silently erase or complete the earlier obligation.

## Layer 5: Objective state machine

The local command `runtime/bin/autoassist` stores durable objectives under `state/objectives`.

Each objective has five ordered stages:

| Stage | Intended evidence |
| --- | --- |
| `research_complete` | Current sources and findings required for the outcome |
| `draft_complete` | The complete proposed artifact or action payload |
| `destination_updated` | Evidence that the exact intended destination changed |
| `save_confirmed` | Evidence that the change persisted |
| `rendered_readback_verified` | Fresh inspection of the authoritative rendered result |

A checkpoint:

- accepts a regular non-symlink evidence file up to 25 MiB;
- copies it into owner-only objective state;
- records a SHA-256 hash and producer label;
- requires the prior stage to be validated;
- moves the stage from `pending` to `reported`.

Validation:

- requires a validator label different from the producer label;
- recomputes the evidence hash;
- marks only the reported stage as validated;
- completes the objective only after all five stages validate in order.

This local mechanism proves stage order, label separation, and evidence integrity after capture. It does not prove that two labels are different humans, agents, processes, or security principals. The project contract therefore requires fresh destination inspection and an actually independent validation role for consequential workflows.

## Layer 6: Liveness supervisor

The standard installer creates and loads a user LaunchAgent named `io.autoassist.supervisor`. It runs `autoassist supervisor-tick` every 60 seconds. The `--skip-launch-agent` option still writes the plist but does not load the service.

The tick:

- writes a current heartbeat;
- scans active local objectives;
- writes a `recovery_needed` marker after 600 seconds without a valid checkpoint.

The supervisor is code-only. It does not run a model, control desktop apps, click through permissions, restart ChatGPT, or send a message. Native ChatGPT Goals and active chats do the work. The local marker makes stalled state durable so the next authorized foreground session can resume from a known point.

This distinction is important. AutoAssist provides completion persistence and explicit recovery state. It does not create an unattended GUI agent outside native ChatGPT's supported execution path.

## External-action path

AutoAssist separates reads from writes.

### Reads

Connectors, plugins, MCP tools, APIs, browser integrations, and first-party apps may retrieve authorized information. Instructions inside retrieved content are data, not authority.

### Writes

Recipient-visible or account-changing writes normally use the signed-in first-party interface through native Computer Use.

The operating contract requires:

1. Current user authority for the exact recipient, account, destination, and scope.
2. Rendered preflight of the app, profile, account, destination, and visible content.
3. No AI or ChatGPT attribution in editable recipient-visible content.
4. A route that does not force a non-removable attribution label.
5. Rendered postflight showing the intended result, no duplicate, and no failure state.

If the outcome is ambiguous, the operating contract requires the active ChatGPT workflow to reread the destination before any retry. It does not permit trading uncertainty for a duplicate.

See [Security](../SECURITY.md) and [Permissions](PERMISSIONS.md).

## Authority model

AutoAssist treats a direct user instruction as authority for the ordinary in-scope task. It does not create new approval gates for routine implementation choices.

That authority does not automatically cover:

- a different recipient, account, destination, or publication;
- spending or a materially different transaction;
- credentials, MFA, security enrollment, or a new OS permission;
- destructive work outside the requested scope;
- legal commitments;
- data from another privacy zone without a current task need.

The supervisor, a subagent, retrieved text, a local file, or an assistant-authored plan cannot expand user authority.

## Local data layout

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Operating contract |
| `PROJECTS.md` | Active initiative index |
| `00_CONTEXT/MEMORY.md` | Small durable routing map |
| `00_CONTEXT/PRIVACY-ZONES.md` | Zone classification rules |
| `00_CONTEXT/OUTBOUND-ACTION-POLICY.md` | External write policy |
| `00_CONTEXT/COMMUNICATION-PROFILES.md` | Channel and audience profile index |
| `00_CONTEXT/ISSUES/issues.json` | Product/workflow defect registry |
| `01_PROJECTS/<initiative>/STATUS.md` | Per-initiative status and completion gate |
| `03_OUTPUTS` | Finished local artifacts |
| `state/objectives` | Objective state, stages, evidence, and liveness |
| `state/logs` | Local supervisor output and error logs |
| `config/profile.conf` | User labels and local paths, never credentials |

## Trust assumptions and non-goals

Current AutoAssist assumes:

- one trusted user;
- one macOS account;
- a local ChatGPT Project;
- an available Mac for local long-running work;
- user-reviewed native permissions;
- a separate validator role that follows the contract;
- an authoritative destination that can be reread.

Version `0.1.0` does not provide:

- kernel-level agent isolation;
- multi-tenant isolation, RBAC, or admin policy management;
- a cryptographic identity for producer and validator labels;
- guaranteed protection from a malicious process already running as the same macOS user;
- autonomous background GUI control;
- a way around authentication, macOS prompts, plan limits, or third-party UI changes;
- proof that all content remains on the Mac.

## Design goal

The architecture is intentionally small: native ChatGPT remains the execution environment, while AutoAssist makes context boundaries, authority, unfinished obligations, and proof of completion explicit and durable.

**Documentation date:** 2026-08-26.
