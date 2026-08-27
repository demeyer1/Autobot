# Security

AutoAssist adds local operating controls around native ChatGPT. It does not replace the ChatGPT sandbox, macOS security, account authentication, or a third-party application's own safeguards.

Version `0.1.0` is pre-release, single-user software for a Mac. It has not been independently certified as a multi-tenant security system or compliance control.

## Security goals

AutoAssist is designed to reduce these practical failure modes:

- private, family/friends, and work context crossing without a current need;
- an agent treating third-party text as permission or policy;
- an unfinished task being silently forgotten after a session interruption;
- a worker certifying its own output without a fresh check;
- a wrong account, recipient, destination, or browser profile being used;
- an ambiguous external result being retried into a duplicate;
- a connector forcing recipient-visible AI attribution;
- credentials or personal identifiers being embedded in a release package.

## Local protections

The current package provides:

- owner-only privacy-zone directories;
- owner-only install state, objective state, evidence, profile configuration, and LaunchAgent definition;
- atomic local state writes;
- objective-level locks;
- stage-ordered evidence with SHA-256 integrity checks;
- rejection of symlink evidence and evidence over 25 MiB;
- producer and validator label separation;
- a one-minute liveness heartbeat and a stalled-objective marker;
- installer refusal for broad, outside-home, or unmanaged destinations;
- a release allowlist and privacy scan;
- a recoverable uninstall path that moves the managed root to Trash.

These are meaningful process and filesystem protections. They are not cryptographic isolation from another process running as the same macOS user.

## Native permission boundaries

AutoAssist does not grant macOS or ChatGPT permissions.

The user controls:

- the local Project folder;
- the ChatGPT sandbox and reviewer mode;
- microphone access for Voice;
- Screen & System Audio Recording for appshots;
- Screen Recording and Accessibility for Computer Use;
- Computer Use per-app approvals;
- optional Locked use;
- protected-folder access;
- account authentication, MFA, and security enrollment.

Start with **Ask for approval**. Full access is not the AutoAssist default because it materially increases the risk of data loss, leakage, and unexpected behavior. See [Permissions](docs/PERMISSIONS.md) and OpenAI's [permission mode documentation](https://learn.chatgpt.com/docs/permission-modes).

## Prompt injection and authority

The operating contract treats instructions retrieved from a document, webpage, email, chat, ticket, connector, plugin, MCP server, or API as untrusted content. It directs the active workflow not to let that content:

- expand the user's instruction;
- change the recipient or destination;
- authorize a send, purchase, publication, credential action, or security change;
- cross a privacy zone;
- declare their own task complete;
- override `AGENTS.md` or higher-priority policy.

When retrieved content conflicts with the user's current objective or asks for a consequential action, the operating contract requires the workflow to stop at the boundary and preserve the exact resume point.

This is a model and process control, not a complete prompt-injection guarantee. The model can still be influenced by malicious content. Deterministic destination checks, least-privilege tool access, and user review remain necessary.

## External-action security

The operating contract treats connectors, apps, MCP tools, APIs, and browser integrations as read-only unless a destination-specific adapter proves the same clean-write properties.

Recipient-visible or account-changing writes normally use the signed-in first-party interface through native ChatGPT Computer Use. Every live write requires:

1. Current user authority for the exact account, recipient, destination, and scope.
2. Rendered preflight of the first-party app, profile, account, destination, and final visible content.
3. No AI or ChatGPT attribution in editable recipient-visible content.
4. A route that does not force a non-removable attribution label.
5. Rendered postflight showing the intended mutation, no duplicate, and no failure state.

If the result is ambiguous, the operating contract requires the active ChatGPT workflow to reread the destination before retrying. If a clean route is unavailable, the action remains incomplete.

This is a fail-closed operating rule. It cannot remove immutable platform metadata, bypass a platform disclosure, or guarantee that a third-party UI will not change.

## Completion integrity

AutoAssist separates production from validation.

The local runtime enforces:

- five ordered stages;
- evidence copied into local objective state;
- evidence SHA-256 verification;
- a validator label different from the producer label;
- terminal state only after all stages validate.

The operating contract requires an actual independent role and fresh destination evidence. The runtime does not cryptographically prove that two labels correspond to separate people, agents, or processes. A malicious same-user process could alter local files, and weak or stale evidence can still produce a bad judgment if the validator does not follow the contract.

For external effects, the authoritative destination readback is the strongest evidence. A tool call, generated artifact, open editor, generic saved indicator, log entry, or worker claim is not enough.

## Liveness and background work

The AutoAssist LaunchAgent is code-only. It records a heartbeat and marks active objectives that have no valid checkpoint for 600 seconds.

It does not:

- control GUI applications;
- hold or enter credentials;
- approve macOS prompts;
- run a model;
- restart ChatGPT;
- send completion messages;
- expand the user's authority.

Native ChatGPT Goal mode and scheduled tasks remain subject to the Mac, app, workspace, plan, sandbox, and approval state. [Long-running work](https://learn.chatgpt.com/docs/long-running-work), [Scheduled tasks](https://learn.chatgpt.com/docs/automations)

## Credentials and secrets

Do not put credentials in AutoAssist.

Keep passwords, MFA codes, recovery codes, payment data, and private keys in the operating system or the signed-in first-party application. `config/profile.conf` stores labels and paths only.

The release privacy scan searches for common private-key markers, obvious embedded secrets, email addresses, phone-like values, absolute macOS user paths, symlinks, scaffold markers, and common credential files. This scan is bounded and can have false negatives or false positives. It does not replace human review or a dedicated secret scanner.

## Installation security

The installer is local and does not require `sudo`. It writes only to:

- the selected AutoAssist destination under the user's home root;
- `~/.codex/skills/first-time`;
- `~/Library/LaunchAgents/io.autoassist.supervisor.plist`;
- local AutoAssist state and logs.

The installer refuses an existing unmanaged destination and a non-AutoAssist skill collision. Use only an official release ZIP whose checksum and release checks match the published candidate.

The installer has a separate managed-update path. It replaces the operating contract, product policies, documentation, runtime, scripts, skill, tests, and other paths named in `config/immutable-manifest.txt`. It creates `PROJECTS.md`, `00_CONTEXT/MEMORY.md`, and `00_CONTEXT/ISSUES/issues.json` only when missing.

Existing zone contents, user project folders, non-README inbox and output contents, `config/profile.conf`, runtime state, and those three seed files are preserved. The automated reinstall test checks sentinel hashes across those areas. Back up important data before a pre-release update because the bounded test cannot cover every future schema or manual customization.

## Stronger isolation

For materially different trust domains, use a separate macOS user account or separate dedicated machine. AutoAssist's privacy zones do not replace OS account separation.

If Computer Use is enabled, grant access only to required apps. Optional Locked use is a native ChatGPT feature with its own Apple authorization plug-in and security behavior. It is not required by AutoAssist. [Computer Use](https://learn.chatgpt.com/docs/computer-use)

## Known limitations

AutoAssist does not currently provide:

- kernel, container, VM, or hardware isolation;
- encrypted per-zone storage;
- cryptographic producer and validator identity;
- multi-user RBAC or enterprise admin controls;
- protection from a malicious process already running as the same macOS user;
- guaranteed continuity through power loss, logout, app termination, or plan exhaustion;
- guaranteed detection of every secret or personal identifier;
- guaranteed absence of third-party metadata or disclosure;
- automatic security updates;
- independent penetration-test or compliance certification evidence.

## Reporting a security concern

Do not put credentials, authentication codes, private family information, confidential work data, or exploit details into a public issue.

Use the repository's private security-reporting channel when it is published. Until then, contact the maintainer through an existing private channel and include:

- affected version;
- exact component and path;
- minimal reproduction steps;
- expected and observed behavior;
- whether any external action, data exposure, or user-data change occurred;
- the smallest redacted evidence needed to reproduce the issue.

Do not test a report against someone else's account, data, device, or external service.

## Sources

- [Permission modes](https://learn.chatgpt.com/docs/permission-modes)
- [Computer Use](https://learn.chatgpt.com/docs/computer-use)
- [Projects](https://learn.chatgpt.com/docs/projects)
- [Voice](https://learn.chatgpt.com/docs/features/voice)
- [Appshots](https://learn.chatgpt.com/docs/appshots)
- [Long-running work](https://learn.chatgpt.com/docs/long-running-work)
- [Scheduled tasks](https://learn.chatgpt.com/docs/automations)
- [ChatGPT Work cloud security](https://learn.chatgpt.com/docs/enterprise/chatgpt-work-cloud-security)

**Documentation date:** 2026-08-26.
