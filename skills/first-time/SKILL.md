---
name: first-time
description: Actively install, configure, resume, or repair AutoAssist on macOS and verify its first useful local task. Invoke automatically before substantive AutoAssist work when first-use validation is incomplete, and when the user asks for setup or reconfiguration. Skip setup questions when the current installation and completion marker already validate.
---

# AutoAssist First Time

Act as the setup operator. Execute every safe supported action, inspect its result, checkpoint it, and continue. Hand control to the user only for a freshly observed credential, security, permission, target-app approval, or manual primary-Project step. Base installation, privacy initialization, doctor, repair and uninstall require no optional account or Node. Advanced objectives and the local smoke require Node 22 or newer.

On a new Mac, the user first completes the minimal bootstrap in the install guide: verify and extract the release, run `Install.command`, add the installed folder as the primary local Project, and invoke this skill in a fresh task. Computer Use cannot bootstrap itself. After invocation, take over all supported safe actions and skip every prerequisite that current readback already proves.

## First-use gate

1. State the short plan and keep the user's original task as the final phase. Resolve the exact release source or managed installation from the current working context or explicit root. Never search protected folders. Read [the active operator walkthrough](references/operator-walkthrough.md) and [the first-use workflow](references/setup-workflow.md) before changing setup state. The latter defines the completion-marker schema and marker readback sequence.
2. For a managed installation, run the progress helper's `show`, doctor, and completion validation. If the marker validates and reconfiguration was not requested, reconcile generated status once and return to the original task without asking setup questions.
3. For release media, require and verify the matching checksum companion from the same official release before running `Install.command` or `install.sh` through the local shell execution tool. A missing companion blocks installation. Do not pretend Computer Use can control Terminal or ChatGPT/Codex. If the installed folder must become the primary local Project, persist the exact manual handoff and resume in a fresh task there.
4. On resume, revalidate the root, receipt, current project, configuration hash and claimed output for the recorded stage. Skip only actions whose current evidence still matches. Resume the earliest unfinished phase without duplicating installation, configuration or smoke objectives.

## Non-negotiable boundaries

- Setup may create or update owner-only files inside the exact AutoAssist root. It may not write to an external service, global skill or another installation.
- Never request, read, transcribe, store, or enter a password, passkey, recovery key, authentication code, browser cookie, token, private key, or other credential.
- Never click or approve a macOS privacy, Accessibility, Screen Recording, microphone, Automation, Keychain, plug-in, target-app, or security-consent prompt. Stop before the control and let the user act in the first-party UI.
- Never probe Desktop, Documents, Downloads, Photos, iCloud, external volumes, another user's home, or another protected location to test access.
- Use supported local filesystem and shell tools directly. Use foreground Computer Use only for a supported target app or Finder when available and authorized. It cannot automate ChatGPT/Codex, Terminal, authentication, administrator controls or macOS privacy/security prompts.
- Do not use connectors, apps, APIs, MCP tools, or browser integrations for external writes. The setup smoke objective is local and records `external_mutation=false`.
- Never ingest raw messages during first-time setup. Tone learning is opt-in, isolated per channel and audience, and stores only user-approved aggregate patterns.
- Treat `SHARED` as explicit opt-in. Never copy material into it automatically.
- AutoAssist can prevent its own attribution and block known forced-label routes; it must not claim to remove a platform disclosure outside editable content.

## Defaults and decisions

Inspect existing configuration before asking anything. Preserve valid choices and unrelated user files. A new setup starts local-only with `PRIVATE` active, `SHARED` disabled, tone learning disabled, raw retention disabled, connectors read-only, external writes fail-closed, and no optional account or capability enabled. Use `not-configured` for an unknown nonsecret account/browser/profile label; never fabricate one.

Ask only when the user requested an option that cannot be inferred safely. Read [dedicated Mac, sign-in and permissions](references/macos-and-sign-in.md) before a user-present handoff and [privacy and communications](references/privacy-and-communications.md) before enabling another zone or tone profile. Optional features remain optional.

## Local configuration

Before writing configuration, read [references/configuration.md](references/configuration.md). Use a restrictive umask, atomic local writes, directory mode `700`, and sensitive file mode `600`. Store only documented labels and states. Record observed native availability separately from a permission state the user confirmed. A shell result, synthetic fixture, marker or receipt does not prove a native UI capability.

Initialize the four zone folders with:

```bash
<root>/runtime/bin/autoassist initialize-zones
```

Use `scripts/walkthrough-progress.sh --root <root> --account-home <account-home> show` at entry and `record` after each observed transition. Its accepted enums and exact command examples are printed by `walkthrough-progress.sh --help`; use `independent-review/ready-for-review/local-smoke-readback` only after the smoke objective is freshly read back. It stores only typed resume metadata and cannot certify setup. For a user-only gate, record `waiting-user` only after a fresh readable prompt identifies the exact action. For an unavailable optional feature, record `pending-capability` and continue every safe local phase.

The checkpoint is the earliest unresolved cursor. Later local work may be recovered from its validated artifacts, but it must not overwrite an earlier user or capability gate. Clear that cursor only after fresh readback at the blocked phase.

## Verification and finish

1. Run doctor with the explicit account home. A healthy base with unavailable runtime is useful but cannot run the advanced smoke or scheduler.
2. Validate local configuration. With Node 22 or newer, run `validate-setup.sh --smoke` once and checkpoint its objective ID. Without Node, preserve a precise runtime prerequisite without downloading or changing a shared toolchain.
3. Write pending generated status and obtain a separate read-only review of current files, doctor output, smoke state, modes and absence of secrets/raw messages. Producer labels or self-review do not qualify.
4. After independent acceptance, read [the marker schema and seal sequence](references/setup-workflow.md#5-seal-and-reread), then write the existing `.install-state/first-time-complete` marker atomically with mode `600`. Rerun validation with `--require-marker`, reconcile complete status, and read both generated surfaces.
5. Record walkthrough `complete` only with `marker-readback`. Report basic and advanced readiness, observed native capabilities, permission states, unresolved manual steps and the first harmless local result. Then return to the user's original task.

Do not claim first-time setup complete while doctor, deterministic validation, independent review, or marker readback remains pending.
