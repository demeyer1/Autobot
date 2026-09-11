---
name: first-time
description: Perform AutoAssist's mandatory first-use setup or repair an incomplete setup on a dedicated macOS laptop. Invoke automatically before the first substantive AutoAssist task when `.install-state/first-time-complete` is absent or setup validation fails; also use when the user asks to initialize or reconfigure AutoAssist. Do not invoke for ordinary work after first-use setup validates.
---

# AutoAssist First Time

Establish a safe, usable local AutoAssist installation without taking over authentication, macOS consent, or external accounts. Base installation, privacy-zone initialization, doctor, repair, and uninstall do not require Node or a ChatGPT sign-in. Advanced objective, evidence, and scheduler operations require a discovered Node 22 or newer runtime.

## First-use gate

1. Resolve the AutoAssist root from the current local project or an explicit `--root`. Never search protected folders to find it. The installed project-local copy is `<root>/.agents/skills/first-time`; an unrelated global skill is not installation evidence.
2. If `.install-state/first-time-complete` exists, run `skills/first-time/scripts/validate-setup.sh --root <root> --account-home <account-home>`. If it passes and the user did not request reconfiguration, run `skills/first-time/scripts/write-status.sh --root <root> --account-home <account-home> --state complete` to repair any stale generated status, report that setup is healthy, and return to the original task.
3. Otherwise, complete this skill before substantive AutoAssist work. Read [references/setup-workflow.md](references/setup-workflow.md) before changing local setup state.

## Non-negotiable boundaries

- Setup may create or update owner-only files inside the AutoAssist root and its installed skill directory. It may not write to any external service.
- Never request, read, transcribe, store, or enter a password, passkey, recovery key, authentication code, browser cookie, token, private key, or other credential.
- Never click or approve a macOS privacy, Accessibility, Screen Recording, microphone, Automation, Keychain, browser-extension, or security-consent prompt. Explain the exact least-privilege need and let the user act in the first-party UI.
- Never probe Desktop, Documents, Downloads, Photos, iCloud, external volumes, another user's home, or another protected location to test access.
- Do not use connectors, apps, APIs, MCP tools, or browser integrations for writes. The setup smoke objective is local and explicitly records `external_mutation=false`.
- Never ingest raw messages during first-time setup. Tone learning is opt-in, isolated per channel and audience, and stores only user-approved aggregate patterns.
- Treat `SHARED` as explicit opt-in. Never copy material into it automatically.
- AutoAssist can prevent its own attribution and block known forced-label routes; it must not claim to remove a platform disclosure outside editable content.

## Setup decisions

Collect only decisions that affect configuration. Explain safe defaults, then let the user choose:

- dedicated-laptop readiness and whether stronger isolation needs separate macOS accounts;
- ChatGPT sign-in route: already signed in, native/OS SSO, or browser SSO;
- non-secret labels for the ChatGPT account, browser, profile, and usual destination;
- active privacy zones and whether `SHARED` is enabled;
- opt-in communication profiles, separately by channel and audience;
- which optional macOS capabilities the user intends to use.

Read [references/macos-and-sign-in.md](references/macos-and-sign-in.md) for the readiness, SSO, and permission handoff. Read [references/privacy-and-communications.md](references/privacy-and-communications.md) before configuring zones or tone learning.

## Local configuration

Before writing configuration, read [references/configuration.md](references/configuration.md). Use a restrictive umask, atomic local writes, directory mode `700`, and sensitive file mode `600`. Store labels and status values only, never secrets or raw correspondence. Every requested capability must bind to a resolved permission state; `required-later` cannot pass for a capability selected for immediate use.

Initialize the four zone folders with:

```bash
<root>/runtime/bin/autoassist initialize-zones
```

Configure external actions as fail-closed first-party rendered writes, connectors as read-only, raw-message retention as disabled, and native ChatGPT Goal pairing as required for work that must survive the session. Do not create an external write or a live communication while testing setup.

## Verification and finish

1. Run `AUTOASSIST_ACCOUNT_HOME=<account-home> <root>/runtime/bin/autoassist doctor --quiet`, scoping that variable to the doctor process only. A healthy base installation with `runtime-unavailable` is a valid distinct state. Do not configure a scheduler until runtime status is `available`.
2. When runtime is available, run `skills/first-time/scripts/validate-setup.sh --root <root> --account-home <account-home> --smoke`. The smoke creates one local objective, exercises all five ordered stages with distinct producer and validator labels, and performs no external mutation. If runtime is unavailable, leave advanced setup incomplete and report the Node 22+ prerequisite without downloading or changing a shared Node installation. Genuine reviewer independence remains a host-provenance and operating-contract requirement; unequal caller-supplied labels alone do not prove it.
3. Run `skills/first-time/scripts/write-status.sh --root <root> --account-home <account-home> --state pending`, then have a separate read-only agent or validator inspect the configuration, doctor result, smoke objective, file modes, and absence of secrets or raw messages. A producer may not certify its own setup.
4. Only after that pass, atomically write `.install-state/first-time-complete` with the setup version, completion time, validator label, setup-config hash, and smoke-objective ID. Use mode `600`.
5. Rerun `validate-setup.sh --root <root> --account-home <account-home> --require-marker`, then run `write-status.sh --root <root> --account-home <account-home> --state complete`. The status writer validates the current marker again and atomically reconciles only the generated first-time status file and its one command-center entry.
6. Read back both status surfaces, then report the exact installed root, account/browser labels, enabled zones and tone profiles, permission statuses, smoke result, and any user-only step still pending.

Do not claim first-time setup complete while doctor, deterministic validation, independent review, or marker readback remains pending.
