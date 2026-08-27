# Install AutoAssist on macOS

AutoAssist is designed as a guided ZIP install into a local ChatGPT Project. The target is less than 30 minutes from an official release ZIP to a working first project on a supported Mac.

Version `0.1.0` is pre-release. Its automated install test fails when the local file installation takes 30 minutes or more in an isolated test home. A complete ZIP-to-ready timing claim still needs a clean-Mac receipt covering ChatGPT installation, sign-in, permissions, first-time choices, and final validation.

## Before you start

You need:

- A Mac that can run the current [ChatGPT desktop app](https://learn.chatgpt.com/docs/app). The current download link is labeled for Apple silicon. OpenAI's documentation reviewed for this release does not state a minimum macOS version.
- A signed-in ChatGPT account with access to the native features you plan to use. Voice, Computer Use, usage limits, and workspace controls vary by plan, region, and rollout.
- A user-owned folder under your home directory. The default is `~/AutoAssist`.
- Enough free local space for the release, objective evidence, logs, and future outputs. No minimum storage figure has been measured for this pre-release.
- Time to review macOS and ChatGPT permission prompts. AutoAssist does not approve them for you.

First-time setup requires a dedicated owner environment. Use a dedicated Mac or a separate macOS user account that only the intended owner can unlock.

## Install from the official ZIP

1. Download an official AutoAssist release ZIP.
2. Verify that the ZIP's SHA-256 matches the checksum published with the release. Do not install when the checksum is absent or different.
3. Extract the ZIP into a normal user-accessible folder. Avoid Desktop, Documents, Downloads, Photos, iCloud, or an external volume as the permanent installation path if you want to minimize macOS protected-folder prompts.
4. Open the extracted AutoAssist folder.
5. Double-click `Install.command`.
6. Read the Terminal output. The default destination is `~/AutoAssist`.
7. Wait for the final line that reports the installation duration and the next step.

`Install.command` invokes the local `install.sh` with no network installer and no `sudo`. The installer:

- validates that the release skeleton is present;
- refuses `/`, your home directory itself, or a destination outside the selected home root;
- refuses to overwrite an existing unmanaged destination;
- copies only release-allowlisted content;
- creates owner-only local install state and privacy zones;
- installs the bundled `first-time` skill under `~/.codex/skills/first-time`;
- refuses to replace a non-AutoAssist skill at that path;
- installs a user LaunchAgent for the one-minute liveness supervisor;
- writes a local installation receipt with version, UTC timestamp, duration, and path.

The release candidate must pass its privacy and package validation before distribution. Do not use a ZIP that reports a missing allowlist entry or unfinished scaffold marker.

## Terminal installation

If you prefer Terminal:

```zsh
cd /path/to/extracted/AutoAssist
./install.sh
```

See available options:

```zsh
./install.sh --help
```

Supported installer options include:

- `--destination PATH` to choose another child directory of your home root. The current installer accepts only letters, digits, spaces, periods, underscores, hyphens, and slashes in the destination path. Use the default if your home path contains another character.
- `--skip-launch-agent` to install without loading the liveness supervisor;
- `--home-root PATH` for isolated release testing, not ordinary use. If `--destination` is omitted, the installer uses `<PATH>/AutoAssist`.

For an existing managed installation, the installer has a separate update path. It replaces the files named in `config/immutable-manifest.txt`, including the operating contract, product policies, documentation, runtime, scripts, bundled skill, tests, and templates. It copies `PROJECTS.md`, `00_CONTEXT/MEMORY.md`, and `00_CONTEXT/ISSUES/issues.json` only when missing.

The update path preserves existing privacy-zone contents, user initiative folders, non-README inbox and output contents, `config/profile.conf`, runtime state, and the three existing seed files above. The automated install test writes sentinels across those preserved areas, reruns the installer, and requires every sentinel hash to remain unchanged.

Back up important user data before any pre-release update. The preservation test covers the checked paths and cannot predict every future schema or manual customization.

## Create the local ChatGPT Project

After the local install:

1. Open the ChatGPT desktop app.
2. Create a new **local project**.
3. Add `~/AutoAssist` as its primary folder.
4. Confirm that the Project can see `AGENTS.md`, `PROJECTS.md`, and `00_CONTEXT/MEMORY.md`.
5. Start a new chat in that Project.
6. Ask ChatGPT to run the `first-time` skill.

The primary folder sets the default working directory and lets ChatGPT discover project-level `AGENTS.md`, skills, and `config.toml`. Secondary folders can be searched and edited, but ChatGPT does not automatically discover project instructions from them. [ChatGPT Projects](https://learn.chatgpt.com/docs/projects)

## Run first-time setup

The guided skill should:

1. Explain the four privacy zones.
2. Ask for labels, not credentials, for the current user, ChatGPT account, browser, browser profile, and usual destination.
3. Create only the communication profiles the user wants.
4. Review the exact permission surfaces needed for the selected workflows.
5. Run local setup validation.
6. Leave credentials, authentication codes, payment data, and raw message archives outside the AutoAssist workspace.

If the bundled skill is not complete or cannot be discovered, stop. Do not invent identity values or manually copy private history into the workspace. See [Troubleshooting](TROUBLESHOOTING.md).

## Configure native ChatGPT permissions

Start with **Ask for approval**. Install and configure Computer Use only if you need GUI interaction. Grant microphone access only if you use Voice. Screen context and app control require separate macOS permissions.

Follow [Permissions](PERMISSIONS.md) before granting anything. Full access is not the AutoAssist default.

## Verify the installation

From `~/AutoAssist`:

```zsh
./runtime/bin/autoassist doctor
./runtime/bin/autoassist version
```

Expected results:

- `doctor` reports required files and definitions as `PASS` and ends with `AutoAssist doctor passed.` It checks the LaunchAgent plist, not whether that service is currently loaded.
- `version` prints the installed version.

Confirm that the standard supervisor is loaded:

```zsh
launchctl print "gui/$(id -u)/io.autoassist.supervisor"
```

After the `first-time` skill creates and independently validates its marker, run:

```zsh
./skills/first-time/scripts/validate-setup.sh --root "$PWD" --require-marker
```

The setup validator checks the configured root, owner-only file modes, required labels, privacy choices, communication-profile settings, local smoke objective, doctor result, and marker binding.

The package privacy scan is for a clean release candidate before user configuration. Do not run it against a populated installation and treat legitimate user records as release defects. It remains a bounded pattern scan, not proof that arbitrary text contains no sensitive information.

## Verify durable objectives

Create a harmless local objective:

```zsh
./runtime/bin/autoassist objective-create install-check "Verify the AutoAssist installation"
./runtime/bin/autoassist objective-status install-check
```

The objective should be `active` with five pending stages. Do not report fake stage evidence merely to turn the status green. Use a real workflow with a different producer and validator label when testing completion integrity.

## Native feature setup

- [Voice setup and limits](https://learn.chatgpt.com/docs/features/voice)
- [Computer Use setup](https://learn.chatgpt.com/docs/computer-use)
- [Long-running Goal mode](https://learn.chatgpt.com/docs/long-running-work)
- [Scheduled tasks](https://learn.chatgpt.com/docs/automations)
- [Skills and plugins](https://learn.chatgpt.com/docs/skills-and-plugins)

For local Goals and scheduled work, keep the Mac, ChatGPT app, and workspace available. Enable **Prevent sleep while running** when appropriate.

## Uninstall

Run the uninstaller from the managed installation:

```zsh
~/AutoAssist/uninstall.sh
```

The script refuses a broad or unmanaged target, stops the AutoAssist supervisor, and moves the managed installation into Trash with a timestamp. That makes the workspace recoverable until Trash is emptied.

Before uninstalling, inspect and back up any user-owned project, context, or output files you intend to keep. The current uninstaller leaves `~/.codex/skills/first-time` and `~/Library/LaunchAgents/io.autoassist.supervisor.plist` in place after stopping the loaded service and moving the AutoAssist root. Remove those exact AutoAssist-managed files separately only after reviewing them. The uninstaller does not remove ChatGPT settings or revoke macOS privacy grants.

### Gatekeeper and signing status

Version `0.1.0` does not yet include a documented code-signing or notarization attestation. If macOS blocks `Install.command`, do not disable Gatekeeper, strip quarantine attributes, or weaken system security to continue. Stop and obtain an official release with clear signing and notarization status, or review and run the local shell installer only through a security process you already trust.

## Installation sources

- [ChatGPT desktop app](https://learn.chatgpt.com/docs/app)
- [ChatGPT quickstart](https://learn.chatgpt.com/docs/quickstart)
- [Projects](https://learn.chatgpt.com/docs/projects)
- [Permission modes](https://learn.chatgpt.com/docs/permission-modes)
- [Computer Use](https://learn.chatgpt.com/docs/computer-use)
- [Voice](https://learn.chatgpt.com/docs/features/voice)
- [Long-running work](https://learn.chatgpt.com/docs/long-running-work)
- [Scheduled tasks](https://learn.chatgpt.com/docs/automations)
- [Troubleshooting](https://learn.chatgpt.com/docs/reference/troubleshooting)

**Documentation date:** 2026-08-26. Check the linked OpenAI pages for current product behavior before installation.
