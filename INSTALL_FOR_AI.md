# AutoBot installation instructions for AI

**Everything in this file is intended for ChatGPT or another AI to automate installation. The short human guide is at the end of the [README](README.md#setup-and-installation).**

Use this guide when the user gives you the repository URL and asks to install AutoBot in a new project. Work through installation, project setup and verification, carrying forward the user's original request.

## Prompt to start installation

“Go to https://github.com/demeyer1/Autobot and install AutoBot in a new local project, following INSTALL_FOR_AI.md. Run installation and first-time setup, including required support software from official sources, and bring me in for choices or app steps that need me.”

## 1 Use the right environment

Confirm that you have local filesystem and shell access on the user's Mac. If you are in a web or cloud environment, guide the user to the [Mac app](https://learn.chatgpt.com/docs/app), have them select Codex, and continue locally.

If the user already created an AutoBot local project for this installation, use it. Otherwise, create a separate setup folder in an accessible location, then create a local project called AutoBot through supported project controls when available, or guide the user to create it and select that setup folder.

A folder on disk is not by itself a native project. Confirm the selected local project and working folder before continuing; keep unrelated projects and the eventual installed folder separate.

For a fresh installation, use the setup project as the download workspace and the user's home-folder AutoAssist as the default installation destination. Let the installer create the destination.

For an update or repair, use a separate accessible setup folder outside the installed root, even when the current project points at that installation. Confirm that the download workspace and release source do not overlap the destination before continuing.

## 2 Download and verify the release

Run this block with the local shell tool using /bin/zsh, from the separate setup folder selected above. It downloads the packaged v0.3.0 release, checks its checksum, extracts it and prints the source folder to use next.

```zsh
set -euo pipefail
umask 077
AUTOBOT_STAGE="$(mktemp -d "$PWD/.autobot-install.XXXXXX")"
cd "$AUTOBOT_STAGE"
AUTOBOT_RELEASE="https://github.com/demeyer1/Autobot/releases/download/v0.3.0"
curl --fail --location --show-error \
  "$AUTOBOT_RELEASE/AutoAssist-v0.3.0.zip" \
  --output AutoAssist-v0.3.0.zip
curl --fail --location --show-error \
  "$AUTOBOT_RELEASE/AutoAssist-v0.3.0.zip.sha256" \
  --output AutoAssist-v0.3.0.zip.sha256
shasum -a 256 -c AutoAssist-v0.3.0.zip.sha256
ditto -x -k AutoAssist-v0.3.0.zip .
printf 'Release source: %s/AutoAssist\n' "$AUTOBOT_STAGE"
```

Continue after the checksum reports OK; if it fails, retrieve a fresh matching ZIP and checksum before running the installer. Use the release asset, not GitHub's automatic source-code ZIP; keep the verified download for a restart or retry.

## 3 Read the installer and install

Set the shell tool's working directory to the exact Release source printed above, then read AGENTS.md, README.md, docs/INSTALL.md, skills/first-time/SKILL.md and install.sh. Use the packaged installer and first-time skill for this version; this guide supplies the project-first route and the README supplies the human app steps. Use the existing-installation branch below if the destination already exists.

For a fresh installation, run this block in /bin/zsh from that release source folder:

```zsh
set -euo pipefail
AUTOBOT_DEST="$HOME/AutoAssist"
if [[ -e "$AUTOBOT_DEST" || -L "$AUTOBOT_DEST" ]]; then
  printf 'Destination exists; use the existing-installation branch.\n' >&2
  exit 1
fi
./install.sh --destination "$AUTOBOT_DEST"
"$AUTOBOT_DEST/runtime/bin/autoassist" doctor --json
"$AUTOBOT_DEST/runtime/bin/autoassist" version
```

Read the receipt at .install-state/receipt.json in the installed folder and confirm its root, account_home and version match this installation. A healthy base install and an available advanced runtime are separate results; Node.js 22 or newer is needed for advanced commands and the setup smoke test.

If Node is missing, use an available supported local runtime or guide installation from the official Node.js distribution, then rerun doctor. Keep the completed base installation and resume from it.

## 4 Continue inside the installed project

Give the user this handoff: “Choose Edit project > Add folder, select AutoAssist in your home folder, and choose Make primary. Start a fresh task there and paste the prompt below.”

“Run first-time setup for this installed AutoBot folder using its project-local first-time skill. Continue from verified progress, test the setup, and tell me what's ready and what still needs me.”

In that fresh task, confirm the working folder, read its AGENTS.md and .agents/skills/first-time/SKILL.md, and follow the skill's referenced walkthrough and configuration instructions. Use the installed skill to configure and resume setup; the commands below are checkpoints, not a replacement for that workflow.

```zsh
cd "$HOME/AutoAssist"
./skills/first-time/scripts/walkthrough-progress.sh \
  --root "$PWD" --account-home "$HOME" show
./runtime/bin/autoassist doctor --json
```

Use the actual installed root and receipt-bound account home in every command when the user chose a different destination. Preserve existing choices and resume the earliest unfinished step instead of repeating completed work.

## 5 Verify setup and finish

Run the following checks with the shell tool's working directory set to the installed AutoAssist folder. After the skill has written the configuration and a supported Node runtime is available, run its smoke check once and retain the reported objective ID:

```zsh
./skills/first-time/scripts/validate-setup.sh \
  --root "$PWD" --account-home "$HOME" --smoke
```

Complete the skill's independent review and completion-marker steps, then verify the marker:

```zsh
./skills/first-time/scripts/validate-setup.sh \
  --root "$PWD" --account-home "$HOME" --require-marker
```

Guide the user through the Mac permissions, Codex settings, phone pairing, Chrome extension and chosen app connections in the [README setup guide](README.md#setup-and-installation), and verify each requested feature separately. Let the user handle account sign-ins, permission grants and app restarts, save the resume point, and continue when they return.

Finish with the installed folder and version, the checks that passed, any remaining user step, and one saved local result the user can open. A successful install command does not by itself prove phone access, app connections or first-time setup is finished.

## Existing installation or interrupted setup

If the destination is already managed, read its receipt and run doctor before deciding whether it needs setup, repair or an update. Resume a healthy installation; use instructions matching an installed version newer than v0.3.0, and preserve an unrelated existing folder while resolving a different destination with the user.

For an intended update, first finish or stop writers in that AutoBot installation, then run the command below from the newly verified release source outside the installed root. The flag asserts that the target is idle; it does not stop running work for you.

```zsh
./install.sh --destination "$HOME/AutoAssist" --target-quiescent
```

Use --repair with the same verified release for a repair, or the documented --rollback path when restoring a retained version is the user's intended action. Preserve user files, customization conflicts and recovery journals, then rerun doctor and the setup validation that applies.

## Source references

[AutoBot v0.3.0 release](https://github.com/demeyer1/Autobot/releases/tag/v0.3.0), [installation guide](https://github.com/demeyer1/Autobot/blob/v0.3.0/docs/INSTALL.md), [first-time skill](https://github.com/demeyer1/Autobot/blob/v0.3.0/skills/first-time/SKILL.md), [local projects](https://learn.chatgpt.com/docs/projects), and [official Node.js download](https://nodejs.org/en/download).
