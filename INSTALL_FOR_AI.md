# AutoBot installation instructions for AI

**This is the agent checklist for the [three-step guided setup](README.md#setup-and-installation). The user's first finish line is one saved local task; for phone-first use, complete step 6 to pair the phone with Remote and Voice.**

Use this guide when the user gives you the repository URL and asks to install AutoBot in a new local Project. Work through package verification, installation, project setup and one local result, carrying forward the user's original request.

## Prompt to start installation

“Install AutoBot from https://github.com/demeyer1/Autobot, following INSTALL_FOR_AI.md. Verify the v0.5.0 release ZIP and its manifest, install it, and guide me through selecting the installed folder as my local Project's primary folder. Include support software needed for first-time setup from official sources. Bring me in for any Mac or account step I need to do.”

## 1 Use the right environment

Confirm that you have local filesystem and shell access on the user's Mac. If you are in a web or cloud environment, guide the user to the [Mac app](https://learn.chatgpt.com/docs/app), have them select Codex, and continue locally.

If the user already created an AutoBot local project for this installation, use it. Otherwise, create a separate setup folder in an accessible location, then create a local project called AutoBot through supported project controls when available, or guide the user to create it and select that setup folder.

A folder on disk is not by itself a native Project. Confirm the selected local Project and working folder before continuing; keep unrelated Projects and the eventual installed folder separate.

For a fresh installation, use the setup project as the download workspace and the user's home-folder AutoAssist as the default installation destination. Let the installer create the destination.

For an update or repair, use a separate accessible setup folder outside the installed root, even when the current project points at that installation. Confirm that the download workspace and release source do not overlap the destination before continuing.

## 2 Download and verify the release

Run this block with the local shell tool using /bin/zsh, from the separate setup folder selected above. It downloads the packaged v0.5.0 release, checks its checksum, extracts it and prints the source folder to use next.

```zsh
set -euo pipefail
umask 077
AUTOBOT_STAGE="$(mktemp -d "$PWD/.autobot-install.XXXXXX")"
cd "$AUTOBOT_STAGE"
AUTOBOT_RELEASE="https://github.com/demeyer1/Autobot/releases/download/v0.5.0"
curl --fail --location --show-error \
  "$AUTOBOT_RELEASE/AutoAssist-v0.5.0.zip" \
  --output AutoAssist-v0.5.0.zip
curl --fail --location --show-error \
  "$AUTOBOT_RELEASE/AutoAssist-v0.5.0.zip.sha256" \
  --output AutoAssist-v0.5.0.zip.sha256
curl --fail --location --show-error \
  "$AUTOBOT_RELEASE/AutoAssist-v0.5.0.manifest.sha256" \
  --output AutoAssist-v0.5.0.manifest.sha256
shasum -a 256 -c AutoAssist-v0.5.0.zip.sha256
ditto -x -k AutoAssist-v0.5.0.zip .
cd AutoAssist
shasum -a 256 -c ../AutoAssist-v0.5.0.manifest.sha256
cd ..
printf 'Release source: %s/AutoAssist\n' "$AUTOBOT_STAGE"
```

Continue after the ZIP checksum and every extracted manifest entry report OK; if either fails, retrieve fresh matching release assets before running the installer. Use the release asset, not GitHub's automatic source-code ZIP; keep the verified download for a restart or retry.

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

The optional local LaunchAgent is off on a fresh installation. Leave it off during the basic path unless the user requests local background liveness. See [Local liveness](docs/INSTALL.md#local-liveness).

If Node is missing, use an available supported local runtime or, as the user's prompt requests, install it from the official Node.js distribution, then rerun doctor. Keep the completed base installation and resume from it. Do not use an unofficial runtime source or silently change another Project's toolchain.

## 4 Continue inside the installed project

Give the user this handoff: “Choose Edit project > Add folder, select AutoAssist in your home folder, and choose Make primary. Start a fresh task there and paste the prompt below.”

“Run first-time setup for this installed folder. Then make and save a sample checklist, and open it for me.”

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

Create the requested sample checklist in the installed local Project, save it, reopen it, and show the user where it is. Use the installed first-time skill's completion checks for the local setup. Finish with the installed folder and version, the checks that passed, any remaining user step, and the saved local result.

## 6 Phone and always-on Mac setup

When the user chooses phone-first use, guide them to open ChatGPT on the Mac using the same account and workspace as the phone. In ChatGPT desktop, go to **Settings → Connections → Control this Mac or PC → Set up/Add**, scan the QR code in the ChatGPT phone app, and enable **Keep this Mac awake**; leave the Mac plugged in and online. Have them open [**Remote**](https://learn.chatgpt.com/docs/remote-connections) on the phone and start or continue the AutoBot Codex chat using [Voice](https://help.openai.com/en/articles/20001275-chatgpt-work-and-codex). Verify the host with a read-only question about a detail in the local Project and compare the answer with the local file.

## Existing installation or interrupted setup

If the destination is already managed, read its receipt and run doctor before deciding whether it needs setup, repair or an update. Resume a healthy installation; use instructions matching an installed version newer than v0.5.0, and preserve an unrelated existing folder while resolving a different destination with the user.

For an intended update, first finish or stop writers in that AutoBot installation, then run the command below from the newly verified release source outside the installed root. The flag asserts that the target is idle; it does not stop running work for you.

```zsh
./install.sh --destination "$HOME/AutoAssist" --target-quiescent
```

Use `--repair` with the same verified release for a repair, or the documented `--rollback` path when restoring a retained version is the user's intended action. For a nondefault installation, pass the receipt-bound `--destination` and `--home-root` to every update, repair, rollback or uninstall; never let a default command create or act on a different folder. Preserve user files, customization conflicts and recovery journals, then rerun doctor and the setup validation that applies.

## Source references

[AutoBot v0.5.0 release](https://github.com/demeyer1/Autobot/releases/tag/v0.5.0), [current installation guide](docs/INSTALL.md), [v0.5.0 first-time skill](https://github.com/demeyer1/Autobot/blob/v0.5.0/skills/first-time/SKILL.md), [local Projects](https://learn.chatgpt.com/docs/projects), and [official Node.js download](https://nodejs.org/en/download).
