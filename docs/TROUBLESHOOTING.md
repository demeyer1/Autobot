# Troubleshooting

Start with the local health check:

```zsh
cd ~/AutoAssist
./runtime/bin/autoassist doctor
```

Use the first failing line below.

## The installer reports an incomplete release

Symptoms can include:

- `This is not a complete AutoAssist release.`
- `Release allowlist entry is missing`
- a privacy-scan failure for an unfinished scaffold marker

Do not create the missing file by hand. Delete that extracted copy and obtain the current official release ZIP. A release is not valid unless its manifest, privacy scan, tests, and package checks all pass against the same candidate.

## The installer refuses the destination

The installer intentionally refuses:

- `/`;
- the selected home root itself;
- a destination outside that home root;
- an existing destination that is not marked as a managed AutoAssist installation.

Choose a new child directory such as `~/AutoAssist`. Do not rename an unrelated folder to satisfy the managed marker check.

An existing managed installation uses the update path. Files in `config/immutable-manifest.txt`, including product policies, documentation, runtime, scripts, skill, tests, and templates, are replaced. `PROJECTS.md`, `00_CONTEXT/MEMORY.md`, and `00_CONTEXT/ISSUES/issues.json` are created only when missing.

Existing privacy-zone contents, user initiative folders, non-README inbox and output contents, `config/profile.conf`, runtime state, and the three seed files above are preserved by the current update path. Back up important data before a pre-release update and stop if the installer reports an unmanaged destination.

## A different `first-time` skill already exists

The installer fails closed when `~/.codex/skills/first-time` exists and is not marked as an AutoAssist-managed skill.

Review that folder. If it belongs to another workflow, preserve and rename it before installing. Do not delete a skill you do not recognize merely to make the installer pass.

## `doctor` cannot find the ChatGPT desktop app

AutoAssist checks the standard system and user Applications folders.

1. Install the current app from the official [ChatGPT desktop page](https://learn.chatgpt.com/docs/app).
2. Open it and sign in.
3. Rerun `./runtime/bin/autoassist doctor`.

The current download link is labeled for Apple silicon. OpenAI's documentation reviewed for this release does not publish a minimum macOS version.

## ChatGPT does not load the project instructions

1. Confirm `~/AutoAssist` is the **primary folder** of a local ChatGPT Project.
2. Confirm `AGENTS.md`, `PROJECTS.md`, and `00_CONTEXT/MEMORY.md` exist at the project root.
3. Start a new chat in that Project.
4. Ask ChatGPT to summarize the active project instructions before substantive work.

Secondary folders are searchable and editable, but ChatGPT does not automatically discover project files from them. [Projects](https://learn.chatgpt.com/docs/projects)

## ChatGPT cannot find the `first-time` skill

Check:

```zsh
test -f ~/.codex/skills/first-time/SKILL.md && echo present
```

Then:

1. Confirm `doctor` reports `installed first-time skill` as `PASS`.
2. Start a new Project chat so skill discovery gets a fresh context.
3. Ask explicitly for the `first-time` skill.

Skills use progressive disclosure. A large skill catalog may shorten or omit some descriptions from the initial context, while the complete skill file is read after selection. [Build skills](https://learn.chatgpt.com/docs/build-skills)

If the skill still contains an unfinished marker or cannot validate, stop and obtain a complete release. Do not invent first-time identity or privacy settings.

## Computer Use can see an app but cannot click or type

Screen Recording permits visibility. Accessibility permits interaction. They are separate macOS grants.

Open macOS System Settings and review the current entries for the named Computer Use process. Then check ChatGPT **Settings > Computer Use** for app access. Do not grant a broader permission than the task needs.

Source: [Computer Use](https://learn.chatgpt.com/docs/computer-use)

## Computer Use can click but cannot see the app

Review Screen Recording for the named Computer Use process. If the app approval exists but the screen is blank, do not blindly click coordinates. Stop, restore visibility, then reread the exact app, account, and destination before continuing.

## Computer Use asks again after “Always allow”

“Always allow” applies to app access, not every sensitive or disruptive action. macOS permissions, ChatGPT app approvals, and action-time safeguards remain separate. This can be expected behavior. [Computer Use](https://learn.chatgpt.com/docs/computer-use)

## A macOS protected folder prompts unexpectedly

Desktop, Downloads, Music, and other protected locations can require additional access.

Do not probe more protected folders. Move the AutoAssist installation or staging path only when you know the exact source and destination and are authorized to move that data. Prefer `~/AutoAssist` or another deliberately selected user folder.

Source: [OpenAI troubleshooting](https://learn.chatgpt.com/docs/reference/troubleshooting)

## Voice is unavailable

Check all of the following:

- the signed-in plan and workspace support Voice;
- rollout is available for the account;
- microphone access is granted;
- no other desktop Voice chat is active;
- the new task was started in Voice mode rather than ordinary chat dictation;
- the rolling five-hour Voice allowance and Codex usage budget are available.

Source: [ChatGPT Voice](https://learn.chatgpt.com/docs/features/voice)

## Voice screen context shows more text than expected

An appshot can include accessible text from the frontmost window, including text that is off-screen. Review the appshot before adding it. Disable screen context when the task does not need it.

Appshots added to a conversation are stored locally in the session file. [Appshots](https://learn.chatgpt.com/docs/appshots)

## A local Goal stopped when the Mac slept

Local long-running work needs the Mac and workspace to remain available.

1. Resume the Goal in its original chat.
2. Review the exact current objective and remaining stage.
3. Enable **Prevent sleep while running** when appropriate.
4. Avoid two chats changing the same files. Use a worktree when parallel edits are necessary.

Source: [Long-running work](https://learn.chatgpt.com/docs/long-running-work)

## A scheduled local task did not run

Desktop scheduled tasks that use a local Project require the computer and app to remain running. Web scheduled tasks run in a separate cloud environment and do not inherit direct local-folder access.

Source: [Scheduled tasks](https://learn.chatgpt.com/docs/automations)

## The AutoAssist supervisor is missing or stale

Inspect the definition:

```zsh
plutil -lint ~/Library/LaunchAgents/io.autoassist.supervisor.plist
```

Inspect the loaded service:

```zsh
launchctl print "gui/$(id -u)/io.autoassist.supervisor"
```

Inspect local logs:

```zsh
tail -n 50 ~/AutoAssist/state/logs/supervisor.out.log
tail -n 50 ~/AutoAssist/state/logs/supervisor.err.log
```

The supervisor should write a heartbeat every minute. It marks an active objective `recovery_needed` after 600 seconds without a valid checkpoint. It does not restart ChatGPT, run a model, or control apps in the background.

If the LaunchAgent was intentionally skipped during installation, its plist is still written. `doctor` checks that definition and can pass even when the service is not loaded. Use the `launchctl print` command above to verify live supervisor state.

## An objective is marked for recovery

List current state:

```zsh
./runtime/bin/autoassist objective-status
```

Inspect the objective's `recovery_needed` marker under `state/objectives/<objective-id>`. Resume the corresponding native ChatGPT Goal or Project chat, state the last verified stage, and take the smallest authorized action that can produce new evidence.

Do not mark the objective complete merely to clear the stall marker.

## A checkpoint is rejected

Common causes:

- unknown or malformed objective ID;
- unknown stage name;
- prior stage is not validated;
- stage is not `pending`;
- evidence is a symlink or not a regular file;
- evidence exceeds 25 MiB;
- another process holds the objective lock.

Use exact stage names:

```text
research_complete
draft_complete
destination_updated
save_confirmed
rendered_readback_verified
```

Do not bypass the order by editing state files manually.

## Validation is rejected

Validation requires:

- a `reported` stage;
- a validator label different from the producer label;
- an unchanged evidence hash;
- the exact objective and stage.

A different label alone is not meaningful independent review. The validator must inspect fresh evidence and, for an external action, the authoritative destination.

## The operating contract stops an external write route

This can be correct behavior. The operating contract requires the active ChatGPT workflow to stop when:

- the exact account, recipient, destination, or visible content cannot be verified;
- the route forces non-removable AI or ChatGPT attribution;
- the first-party app is unavailable for a recipient-visible write;
- the result is ambiguous and a retry could create a duplicate;
- the task reaches an authentication, permission, or authority boundary.

Resolve the specific boundary. Do not switch accounts, profiles, recipients, or delivery routes merely to make the action succeed.

## A clean release-candidate `privacy-scan` reports a finding

The privacy scan is a release gate for an unconfigured candidate tree. It is not intended for a populated installation, where the receipt, profile path, privacy-zone records, or other legitimate user content can match its detectors.

Finding output is intentionally redacted. It never prints the release root, a relative filename, or matched content. A `file=allowlist-NNNNNN` identifier maps to the Nth nonblank, noncomment entry in `config/release-allowlist.txt`; that committed list is the safe diagnostic map for expected release files. A fallback `file=item-NNNNNN` identifies the same item on every byte-sorted traversal, but means the path is not mapped by the release allowlist. Rebuild the candidate from the allowlist instead of publishing a local path map. Use the reported line number to inspect the file locally, and do not paste the line or an originating-user path into a bug report.

The scan checks for:

- absolute macOS user paths;
- email addresses and phone-like values;
- private-key material and obvious embedded secrets;
- unfinished scaffold markers;
- symlinks;
- common credential files;
- malformed checksum or tree-manifest records.

Checksum files use one strict grammar: 64 lowercase hexadecimal characters, two spaces, then a safe basename or relative release path. The digest field is integrity metadata and is not run through phone or free-text detectors. The filename or path field is still structurally validated and privacy-scanned.

Remove or parameterize the sensitive release content. Do not suppress the detector just to make the release green. The scan excludes runtime state and release-output directories, but it is still a bounded pattern scan rather than a complete privacy proof.

Specifically, the scanner prunes only the top-level `dist`, `.release`, and `state` directories without enumerating their contents. Those locations can contain generated artifacts or configured-user state and are never evidence that a package is safe. The packager constructs a fresh tree from `config/release-allowlist.txt`, checks its exact path set, and scans that staged tree, the unpacked archive, and generated checksum metadata directly.

If you ran it against a configured user workspace, do not delete legitimate records merely to make that workspace pass a release gate. Build releases only from the clean source tree.

## Uninstall or restore

Run:

```zsh
~/AutoAssist/uninstall.sh
```

The managed installation is moved to a timestamped folder in Trash. Restore it from Trash if needed before emptying Trash.

The current uninstaller leaves `~/.codex/skills/first-time` and `~/Library/LaunchAgents/io.autoassist.supervisor.plist` behind. Review those exact AutoAssist-managed files separately before removing them.

Uninstalling AutoAssist does not by itself revoke macOS privacy grants, ChatGPT app approvals, or attached Project sources. Review those settings separately. See [Install](INSTALL.md) and [Permissions](PERMISSIONS.md).

## Before sharing logs

Logs, objective titles, stage evidence, profile labels, and project paths can contain private information. Remove sensitive content before sharing a diagnostic. Never publish credentials, authentication codes, private family details, work-confidential data, or raw communication archives.

**Documentation date:** 2026-08-26.
