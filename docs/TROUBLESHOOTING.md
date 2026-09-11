# Troubleshooting

Start with `~/AutoAssist/runtime/bin/autoassist doctor --json`. The check is read-only. Installation integrity, runtime availability, first-time setup and service configuration are separate results.

## Incomplete or altered download

Use the ZIP, manifest and checksum from the same release. Follow [Install](INSTALL.md) to verify the checksum before extraction. A missing release file, unsafe path or invalid manifest stops installation. Obtain a fresh official archive instead of inventing the missing file.

## Destination refused

The installer needs a safe absolute child of the selected account home. It rejects symlinks, unrelated existing directories and unsafe ownership. It defaults to `~/AutoAssist`. Do not relabel an unrelated folder as managed.

## Upgrade or repair conflict

Updates compare the original shipped bytes, current installed bytes and incoming bytes. User seeds and state remain user-owned. A customized product file can be retained when the incoming version has not changed it; overlapping changes require a deliberate merge before retry. This applies to `AGENTS.md` and policy files as well as code.

Stop writers to this installation before using `--target-quiescent`. This assertion does not stop other processes for you. The transaction checks for unexpected changes and refuses an unsafe handoff. Keep the existing installation and conflict evidence until the merge is resolved. See [Install](INSTALL.md) for repair and rollback commands.

## An unrelated global first-time skill exists

The primary setup skill belongs to this installation at `.agents/skills/first-time`. An unrelated global skill is preserved and does not prevent the base installation. Open the installed folder as the primary local Project, start a fresh task and request the project-local first-time skill.

## Runtime unavailable

The base workspace installs without Node or a signed-in app. Advanced durable state requires Node 22 or newer. Install a supported [Node LTS release](https://nodejs.org/en/download), then rerun doctor and the installer as described in [Install](INSTALL.md). A missing runtime does not arm a broken supervisor. No npm dependency or model API key is needed.

## Instructions or skill not discovered

Open the installed `AutoAssist` folder as the **primary folder** of a supported native local Project. Confirm `AGENTS.md` and `.agents/skills/first-time/SKILL.md` exist. Start a fresh task and ask which instructions were loaded. A secondary folder or web Project does not provide the same local discovery behavior. [Local Projects](https://learn.chatgpt.com/docs/projects)

Computer Use cannot click ChatGPT/Codex's own Project controls or operate Terminal. Use **Edit project > Add folder > Make primary** yourself, then resume in a fresh local task. Do not mark that step confirmed from a shell path alone.

## First-time walkthrough was interrupted

Run `./skills/first-time/scripts/walkthrough-progress.sh --root <root> --account-home <account-home> show`. The record is a nonsecret resume cursor, not completion proof. Revalidate the receipt, configuration, doctor result and any local smoke before advancing. If an action completed before the checkpoint write, use its current artifact instead of repeating it. A later local action never clears an earlier native Project, identity, permission or capability gate; clear the earlier gate only after fresh readback at that phase.

Setup is complete only when `validate-setup.sh --require-marker` succeeds and the generated first-time status reads current. If Computer Use or Node is unavailable, report that capability separately and continue only the unaffected local steps.

## Optional supervisor not running

Doctor reports the saved service configuration; that alone does not prove a live launch. The instance-specific service label and plist path are in `.install-state/receipt.json`. Inspect that exact label with `launchctl print gui/USER_ID/SERVICE_LABEL`, substituting your numeric user ID and receipt label. Inspect `state/logs` and the current core status for fresh activity.

The local tick records liveness and recovery needs. It does not launch a model, resume a native Goal, click an app or send messages. A deliberately skipped service remains skipped. Native app schedules have separate availability requirements. [Schedules](https://learn.chatgpt.com/docs/automations)

## Work needs recovery or validation is rejected

Use `./runtime/bin/autoassist core status` and [the CLI reference](CLI-REFERENCE.md). Preserve the current intent, attempt and exact output target. Changed target bytes, incomplete requirement coverage, stale evidence, an expired owner or an unchanged repeated failure can require new evidence or recovery.

Do not edit the state store to clear a failure. A different reviewer label is only a local consistency check; arrange a separate reviewer who actually inspects the current artifact and destination. Legacy v0.1 objectives require the explicit import path before advancing.

## An external action is uncertain

Preserve the browser, profile, account and destination. Reopen the destination and reconcile whether the action happened before retrying. Do not infer a security challenge from a spinner or blank capture. If a readable prompt requires authentication or a new OS grant, resolve that specific boundary. See [Permissions](PERMISSIONS.md).

## Release privacy scan fails

The release scanner is for a clean source tree, not a populated installation. It checks every entry against the exact allowlist and rejects unexpected state, generated output, credentials, unsafe paths and suspicious text. It does not skip a directory because its name is familiar.

Media requires a current private review receipt bound to its exact bytes. Pattern checks cannot establish semantic privacy on their own. Keep the receipt and diagnostic details private, remove sensitive material at its source and rebuild into a new output directory. See [Privacy](../PRIVACY.md).

## Uninstall or restore

Use the installed `uninstall.sh` with the same selected home and destination, if customized. It moves the managed folder into the selected home's Trash and handles only receipt-bound resources. Preserve the returned restore location. It does not revoke app permissions or erase third-party data.

Before sharing logs, remove private titles, paths, recipients, credentials and evidence. Never upload a configured workspace as a release or diagnostic bundle.
