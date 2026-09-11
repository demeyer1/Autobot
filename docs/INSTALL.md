# Install Autobot

The default folder is `~/AutoAssist`. The product is called Autobot; keeping the folder name preserves existing local Project paths.

## Before you start

The base installer uses macOS's zsh and standard local tools. It requires no administrator account, API key, sign-in, Node installation or new privacy permission. Advanced task/context/evidence commands require Node.js 22 or later. The installer diagnoses runtime availability and does not download or change your shared toolchain.

The current release is tested on the macOS/CPU/runtime listed in its validation report. Intel Macs and other macOS versions are not implied to be tested by an Apple-silicon run. Native app support is separate: check the [current ChatGPT desktop requirements](https://learn.chatgpt.com/docs/app), available local Project features and your account's access.

Keep enough space for the package plus a staged copy and recoverable backup of an existing installation. The installer checks space before a transaction. Large user workspaces need more room than a fresh install. Back up important data before upgrading pre-release software.

## Download and install

1. Download the versioned ZIP and matching checksum from this repository's Releases page. Use the release asset, not GitHub's automatic source-code ZIP.
2. In the folder containing both files, run `shasum -a 256 -c AutoAssist-v0.3.0.zip.sha256`. Continue only if it reports `OK`. If the matching checksum companion is missing, retrieve it from the same official release and stop before installation if verification is not possible.
3. Extract the ZIP, open the extracted folder and double-click `Install.command`. You can also run `./install.sh` from Terminal.
4. If macOS blocks opening the file, inspect its origin and use the standard Finder/System Settings opening flow. Do not disable Gatekeeper or strip security attributes as an installation shortcut.
5. Read the reported installation path and doctor result. An installed folder and an available advanced runtime are separate results.

A different destination can be selected explicitly:

```zsh
./install.sh --destination "$HOME/Autobot Workspace"
```

`--home-root` is for an explicitly selected account root or isolated test environment. It does not change the process's HOME or Codex configuration root. Installation refuses broad, unsafe or unmanaged destinations.

## Start a local Project

First complete this minimal bootstrap. It does not require Computer Use:

1. Download the release ZIP and checksum companion, verify the checksum, extract them and open `Install.command` as described above.
2. Open ChatGPT or Codex and create or edit a local Project.
3. Choose **Edit project > Add folder**, select the installed `AutoAssist` folder and choose **Make primary**.
4. Start a fresh task in that Project and ask: “Run the first-time skill for this installed folder.”

An uploaded web project is a different environment and does not directly expose the folder. [Local Projects](https://learn.chatgpt.com/docs/projects)

At that point the project-local skill takes over. It avoids replacing an unrelated global skill. Ask it to show what works locally and which optional capabilities are unavailable.

The first-time agent now works through the setup in the foreground. It checks the exact installation, creates empty privacy-zone indexes, applies local/private defaults, runs local verification when supported and reports native capabilities. It resumes from validated files after an interruption and asks only at a freshly visible credential, security, permission, consent or manual Project step. You choose accounts and permissions only for workflows you want. No contact, notification recipient, recurring task or spending authority is inherited from the maintainer.

Computer Use cannot operate ChatGPT/Codex itself or Terminal. If native controls are unavailable, use **Edit project > Add folder**, choose the installed folder, and **Make primary**. Start a fresh task in that local Project and ask the agent to read back its working folder, `AGENTS.md` and project-local first-time skill. An explicitly resolved command-line/current-root setup can remain local-only without claiming a native Project selection.

A useful first task is a small local plan with two outputs, such as a checklist and a short summary. Ask the agent to register both outputs, write them locally, and have a separate reviewer reopen and check them. Use `./runtime/bin/autoassist help` for the installed command interface.

## Diagnose readiness

```zsh
./runtime/bin/autoassist doctor
./runtime/bin/autoassist version
```

Installation integrity covers the local files, path binding and permissions. Missing Node means the advanced runtime is unavailable; it is not permission to download a runtime or activate a broken service. Install a supported Node version through the [official distribution](https://nodejs.org/en/download) if you want those commands, then rerun doctor.

Native app, Voice, Goals, Computer Use, connectors and reasoning schedules are optional. Verify each separately. No terminal hook is installed to intercept every assistant response. See [Capabilities](CAPABILITIES.md).

## Upgrade an existing installation

Close or finish work in the target Autobot Project before upgrading. Quiesce that installation only; other Projects do not need to stop. An old runtime or editor cannot be made safe by a new lock it does not recognize.

Extract the new official package and run:

```zsh
./install.sh --target-quiescent
```

The installer recognizes the published old receipt and compares original product files, your installed bytes and the new version. It preserves user files and detects conflicting custom instructions or policies before replacing them. Resolve a reported conflict using the staged guidance; do not delete your customization just to make an update pass.

The transaction preserves state, checks for concurrent changes and retains recoverable evidence. An interruption is recovered through the same installer. Do not manually delete a transaction journal or move swap directories while recovery is pending.

To repair product-file or permission drift, use `./install.sh --repair --target-quiescent` from the same release. To restore a retained earlier code version, use `./install.sh --rollback --target-quiescent`. Rollback preserves current user state and refuses an incompatible schema; it does not silently discard newer data.

## Local liveness

The optional service is scoped to one installation. It records local liveness and pending work; it does not run a model or control desktop apps. `--skip-launch-agent` leaves it inactive. An unavailable runtime cannot arm it.

Native scheduled reasoning is configured separately through supported app controls. It requires the app, computer and local files to remain available. Verify an actual run before relying on it. [Scheduled tasks](https://learn.chatgpt.com/docs/automations)

## Remove the installation

Run the installed `uninstall.sh` with its exact destination and account home when nondefault. The reversible path stops only the receipt-bound service, removes only owned projections and moves the folder to recoverable Trash. It does not delete user data or an unrelated global skill. Conflicting ownership is reported instead of guessed.

## Test boundary

Read the release validation report for actual tested bytes and commands. An isolated folder under the same macOS user proves path/state isolation; it is not a fresh macOS account, reset TCC database or VM. This release does not claim that existing host permissions prove every new Mac's permission behavior.
