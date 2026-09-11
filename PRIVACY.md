# Privacy

AutoAssist separates context by relationship and purpose. Its default zones are `PRIVATE`, `FAMILY_FRIENDS`, `WORK`, and opt-in `SHARED`.

The goal is straightforward: family and friend context should not silently enter work, work context should not flatten personal communication, and sensitive personal material should not become general-purpose memory.

## Privacy zones

| Zone | Intended use | Cross-zone rule |
| --- | --- | --- |
| `PRIVATE` | Sensitive personal facts, preferences, health, finances, and private plans | Never shared automatically |
| `FAMILY_FRIENDS` | Personal relationships, events, logistics, and authorized communication patterns | Never used for work without an explicit current need |
| `WORK` | Organizations, projects, teammates, customers, vendors, and professional communication patterns | Never used for personal communication unless explicitly relevant |
| `SHARED` | The minimum facts the user deliberately makes reusable across zones | Opt-in only, with provenance |

AutoAssist defaults to the narrowest zone that supports the current assignment. A zone label is not permission to read every file in that zone. If a fact legitimately spans zones, store separate scoped records or put only the minimum explicitly reusable fact in `SHARED`.

## What the installer creates

The local installer creates each privacy-zone directory with owner-only permissions. Objective state, evidence, profile configuration, and install receipts are also stored with restrictive user permissions.

The default installation is under `~/AutoAssist`. A custom destination must pass the installer's safe-path and ownership checks. Use a deliberately selected child directory; do not move unrelated private content to satisfy installation checks.

Folder permissions inside one logged-in macOS account are not equivalent to:

- a separate macOS user account;
- a container or virtual machine;
- encrypted per-zone storage;
- a separate computer;
- a kernel-enforced boundary between agents or processes.

Use separate macOS accounts or dedicated machines when the trust domains require stronger isolation.

## What AutoAssist stores

AutoAssist can store:

- a small durable memory routing map;
- user-approved canonical facts in the narrowest privacy zone;
- initiative status and next actions;
- compact session deltas and corrections;
- local objective titles, stage state, producer and validator labels, timestamps, and evidence copies;
- local heartbeat and supervisor logs;
- account, browser, and profile **labels** used to verify an execution context;
- compact communication-style observations approved by the user.

AutoAssist should not store:

- passwords;
- MFA or authentication codes;
- payment-card data;
- government identifiers;
- private keys or recovery codes;
- raw message archives by default;
- private chain-of-thought;
- unrelated third-party private information;
- content from another zone merely because it might be useful later.

`config/profile.conf` is for labels and paths, not secrets.

## Communication profiles

Tone learning is opt-in and separated by channel and audience. A work-external email profile, work-internal chat profile, and family/friends text profile remain distinct.

The default is to store a bounded aggregate of formality, directness, warmth, brevity, emoji frequency, greeting style, and closing style. Raw correspondence is not retained unless the user explicitly chooses to preserve an example.

A tone profile affects wording only. It does not authorize a recipient, channel, destination, send, post, or account change.

## Local files and ChatGPT processing

The AutoAssist workspace is stored locally. That does not mean all content always remains on the Mac.

Content can be processed by OpenAI or another connected service when the user:

- places it in a ChatGPT conversation;
- attaches or uploads it to a ChatGPT Project;
- exposes it through Voice screen context or an appshot;
- retrieves or sends it through a connected app, connector, or MCP server;
- uses cloud Work or another cloud task surface;
- includes it in model context from a local Project.

Cloud and local Work have different boundaries. Cloud work does not inherit direct access to local files or browser sessions unless the user supplies or connects the content. Published data-use commitments also vary by plan. OpenAI states that Business, Enterprise, and Edu data is not used to train models by default; do not apply that statement to every consumer plan. [ChatGPT Work overview](https://learn.chatgpt.com/docs/enterprise/chatgpt-work-overview), [ChatGPT Work cloud security](https://learn.chatgpt.com/docs/enterprise/chatgpt-work-cloud-security)

Review current ChatGPT account and workspace data controls before placing sensitive material into model context.

## Voice and appshots

Voice requires microphone access. Optional screen context on macOS can require Screen & System Audio Recording and Accessibility.

An appshot can include:

- an image of the frontmost window;
- visible text;
- accessibility text that is off-screen.

After the user adds an appshot, ChatGPT stores it locally with the session as an attachment. Review an appshot before adding it and disable screen context when it is not needed. [Voice](https://learn.chatgpt.com/docs/features/voice), [Appshots](https://learn.chatgpt.com/docs/appshots)

## Memory

Required behavior lives in `AGENTS.md` and canonical project documents, not optional model memory.

OpenAI documents local Codex memory as optional and off by default. It can be disabled for individual chats, and background memory generation may be delayed or skipped near usage limits. AutoAssist does not rely on it as a privacy or enforcement boundary. [Memories](https://learn.chatgpt.com/docs/customization/memories)

## External actions

External reads and writes are separate paths.

Connected tools may retrieve and analyze authorized information. Recipient-visible writes normally use the signed-in first-party interface through Computer Use. The operating contract requires the active ChatGPT workflow to perform a rendered preflight and postflight and to leave the action incomplete if the route forces non-removable attribution or the result cannot be verified.

This policy reduces known wrong-destination, duplicate, and attribution risks. It cannot remove immutable metadata controlled by a third-party platform. See [Security](SECURITY.md).

## AutoAssist telemetry

The bundled local runtime and installer do not contain an AutoAssist telemetry uploader. They write local state, evidence, receipts, heartbeat files, and logs.

This statement does not describe or override telemetry, logging, retention, or data processing by ChatGPT, OpenAI, macOS, connected apps, model providers, or external services. Review each service's current policy separately.

## Retention and deletion

AutoAssist does not currently apply a universal automatic retention period to user context or objective evidence.

- Delete or archive canonical records when they are no longer needed.
- Preserve corrections and required audit evidence when an active objective depends on them.
- Remove attached sources and connected apps through the relevant ChatGPT settings.
- Revoke macOS permissions in System Settings.
- Use `uninstall.sh` to move a managed AutoAssist installation to Trash.

Moving the folder to Trash is recoverable deletion, not secure erasure. Emptying Trash does not revoke separate ChatGPT, app, or macOS permissions.

## Sharing and releases

Build and scan releases only from a clean, unconfigured source tree. Never package a populated user workspace. Against the clean candidate, run:

```zsh
./scripts/verify-release.sh /path/to/clean/AutoAssist --media-review /path/to/private/media-review.json
```

The release scan checks for absolute user paths, email addresses, phone-like values, private keys, obvious embedded secrets, symlinks, and common credential files.

The scanner checks the entire exact allowlisted tree, without silently skipping state or output directories. Every media file needs a private review receipt bound to its bytes. The packager repeats checks on archive entries and extracted content and emits a deterministic ZIP, manifest and checksum outside the source. A bounded pattern scan is not a complete privacy proof. Independent semantic review remains required. A configured installation contains legitimate paths, labels, and user data and is not expected to pass this clean-release gate.

## Known limits

AutoAssist does not claim:

- that private data never leaves the Mac;
- cryptographic or kernel isolation between zones;
- protection from a malicious process already running as the same macOS user;
- compliance with a legal or industry privacy framework;
- that a model will never infer a connection between facts intentionally placed in the same prompt;
- automatic deletion from ChatGPT, a connected service, backup, or third-party platform.

## Sources

- [ChatGPT Projects](https://learn.chatgpt.com/docs/projects)
- [ChatGPT Work overview](https://learn.chatgpt.com/docs/enterprise/chatgpt-work-overview)
- [ChatGPT Work cloud security](https://learn.chatgpt.com/docs/enterprise/chatgpt-work-cloud-security)
- [Voice](https://learn.chatgpt.com/docs/features/voice)
- [Appshots](https://learn.chatgpt.com/docs/appshots)
- [Memories](https://learn.chatgpt.com/docs/customization/memories)
- [Computer Use](https://learn.chatgpt.com/docs/computer-use)

**Documentation date:** 2026-09-10.
