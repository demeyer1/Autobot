# AutoBot installation instructions for AI

**This is the agent checklist for the [three-step guided setup](README.md#setup-and-installation). The user's first finish line is one saved local task; for phone-first use, complete step 6 to pair the phone with Remote and Voice.**

Use this guide when the user gives you the repository URL and asks to install AutoBot in a new local Project. Work through package verification, installation, project setup and one local result, carrying forward the user's original request.

## Prompt to start installation

“Install AutoBot from https://github.com/demeyer1/Autobot, following INSTALL_FOR_AI.md. Verify the latest stable release ZIP and its manifest, install it, and guide me through selecting the installed folder as my local Project's primary folder. Include support software needed for first-time setup from official sources. Bring me in for any Mac or account step I need to do.”

## 1 Use the right environment

Confirm that you have local filesystem and shell access on the user's Mac. If you are in a web or cloud environment, guide the user to the [Mac app](https://learn.chatgpt.com/docs/app), have them select Codex, and continue locally.

If the user already created an AutoBot local project for this installation, use it. Otherwise, create a separate setup folder in an accessible location, then create a local project called AutoBot through supported project controls when available, or guide the user to create it and select that setup folder.

A folder on disk is not by itself a native Project. Confirm the selected local Project and working folder before continuing; keep unrelated Projects and the eventual installed folder separate.

For a fresh installation, use the setup project as the download workspace and the user's home-folder AutoAssist as the default installation destination. Let the installer create the destination.

For an update or repair, use a separate accessible setup folder outside the installed root, even when the current project points at that installation. Confirm that the download workspace and release source do not overlap the destination before continuing.

## 2 Download and verify the release

Run this block with the local shell tool using /bin/zsh, from the separate setup folder selected above. It resolves the latest stable release and its attached ZIP, checks the matching checksum and manifest, extracts it and prints the source folder to use next.

```zsh
set -euo pipefail
umask 077
AUTOBOT_STAGE="$(mktemp -d "$PWD/.autobot-install.XXXXXX")"
cd "$AUTOBOT_STAGE"
AUTOBOT_RELEASE_JSON="$(
  curl --fail --location --silent \
    https://api.github.com/repos/demeyer1/Autobot/releases/latest 2>/dev/null \
  || curl --fail --location --show-error --silent \
    'https://api.github.com/repos/demeyer1/Autobot/releases?per_page=1'
)"
AUTOBOT_TAG="$(printf '%s' "$AUTOBOT_RELEASE_JSON" \
  | /usr/bin/grep -oE '"tag_name":[[:space:]]*"[^\"]+"' \
  | /usr/bin/sed -E 's/^.*"([^\"]+)"$/\1/' \
  | /usr/bin/awk '!found { value=$0; found=1 } END { if (!found) exit 1; print value }')"
[[ "$AUTOBOT_TAG" == v[0-9]*.[0-9]*.[0-9]* ]] || {
  printf 'Unexpected stable release tag: %s\n' "$AUTOBOT_TAG" >&2
  exit 1
}
AUTOBOT_ASSETS_HTML="$(curl --fail --location --show-error --silent \
  "https://github.com/demeyer1/Autobot/releases/expanded_assets/$AUTOBOT_TAG")"
AUTOBOT_ZIP_PATH="$(printf '%s' "$AUTOBOT_ASSETS_HTML" \
  | /usr/bin/grep -oE '/demeyer1/Autobot/releases/download/[^\"]+\.zip' \
  | /usr/bin/awk -v prefix="/demeyer1/Autobot/releases/download/$AUTOBOT_TAG/" \
      'index($0,prefix)==1 && !found { print; found=1 } END { if (!found) exit 1 }')"
AUTOBOT_ZIP="${AUTOBOT_ZIP_PATH##*/}"
AUTOBOT_MANIFEST="${AUTOBOT_ZIP%.zip}.manifest.sha256"
curl --fail --location --show-error \
  "https://github.com$AUTOBOT_ZIP_PATH" \
  --output "$AUTOBOT_ZIP"
curl --fail --location --show-error \
  "https://github.com$AUTOBOT_ZIP_PATH.sha256" \
  --output "$AUTOBOT_ZIP.sha256"
curl --fail --location --show-error \
  "https://github.com${AUTOBOT_ZIP_PATH%.zip}.manifest.sha256" \
  --output "$AUTOBOT_MANIFEST"
shasum -a 256 -c "$AUTOBOT_ZIP.sha256"
ditto -x -k "$AUTOBOT_ZIP" .
cd AutoAssist
shasum -a 256 -c "../$AUTOBOT_MANIFEST"
cd ..
printf 'Release: %s\nRelease source: %s/AutoAssist\n' \
  "$AUTOBOT_TAG" "$AUTOBOT_STAGE"
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

Use `runtime/bin/autobot` when that alias exists. An earlier package may expose only the compatible `runtime/bin/autoassist` command.

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
if [[ -x ./runtime/bin/autobot ]]; then
  ./runtime/bin/autobot doctor --json
else
  ./runtime/bin/autoassist doctor --json
fi
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

If the destination is already managed, read its receipt and run doctor before deciding whether it needs setup, repair or an update. Resume a healthy installation; use instructions matching the installed version, and preserve an unrelated existing folder while resolving a different destination with the user.

For an intended update, first finish or stop writers in that AutoBot installation, then run the command below from the newly verified release source outside the installed root. The flag asserts that the target is idle; it does not stop running work for you.

```zsh
./install.sh --destination "$HOME/AutoAssist" --target-quiescent
```

Use `--repair` with the same verified release for a repair, or the documented `--rollback` path when restoring a retained version is the user's intended action. For a nondefault installation, pass the receipt-bound `--destination` and `--home-root` to every update, repair, rollback or uninstall; never let a default command create or act on a different folder. Preserve user files, customization conflicts and recovery journals, then rerun doctor and the setup validation that applies.

## Source references

[Latest stable AutoBot release](https://github.com/demeyer1/Autobot/releases/latest), [current installation guide](docs/INSTALL.md), [current first-time skill](https://github.com/demeyer1/Autobot/blob/main/skills/first-time/SKILL.md), [local Projects](https://learn.chatgpt.com/docs/projects), and [official Node.js download](https://nodejs.org/en/download).
