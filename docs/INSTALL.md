# Install Autobot

The easiest route is the [three-step guided setup](../README.md#setup-and-installation). This page covers manual installation, upgrades, repair and removal. The default folder is `~/AutoAssist`; that folder name preserves existing local Project paths.

## Manual install

1. From the [v0.4.0 release](https://github.com/demeyer1/Autobot/releases/tag/v0.4.0), download `AutoAssist-v0.4.0.zip` and its matching `.zip.sha256` and `.manifest.sha256` files. Choose the attached release ZIP, not GitHub's automatic source-code ZIP.
2. In the download folder, run `shasum -a 256 -c AutoAssist-v0.4.0.zip.sha256`. Extract the ZIP, open the extracted `AutoAssist` folder, then run `shasum -a 256 -c ../AutoAssist-v0.4.0.manifest.sha256`. Continue only when the ZIP and every manifest entry report `OK`.
3. Double-click `Install.command`, or run `./install.sh` from that extracted folder. Note the installed path and doctor result.

If macOS blocks opening the installer, inspect its origin and use the standard Finder/System Settings opening flow. Keep Gatekeeper enabled. The installer checks available space before making changes.

The base install uses macOS's local tools without Node.js, an administrator account, API key or new privacy permission. Completing first-time setup's local smoke check and using advanced runtime commands require [Node.js 22 or newer](https://nodejs.org/en/download). The installer reports runtime availability without changing your shared toolchain. The [v0.4.0 validation report](https://github.com/demeyer1/Autobot/releases/download/v0.4.0/AutoAssist-v0.4.0-validation.md) records tests on macOS 15.7.4, Apple silicon and Node.js 22.23.3. Check the [current desktop app requirements](https://learn.chatgpt.com/docs/app) for your Mac.

### Choose another folder

From the extracted release folder:

```zsh
./install.sh --destination "$HOME/Autobot Workspace"
```

`--home-root` selects an account root for an explicit alternate account or isolated test. It does not change the shell's HOME or Codex configuration. The installer rejects broad or unmanaged destinations.

## Start using it

1. In the Codex desktop app, create a local Project called AutoBot, or open your existing local Project. Choose **Edit project > Add folder**, select the installed `AutoAssist` folder and choose **Make primary**.
2. Start a fresh task in that Project: “Run first-time setup for this installed folder. Then make and save a sample checklist, and open it for me.”

The project-local first-time skill checks the installation, applies local defaults, validates setup and resumes from saved progress after an interruption. You choose accounts and permissions only for workflows you want. If native Project controls are unavailable to the agent, make the folder selection yourself; an uploaded web project does not directly expose a Mac folder. [Local Projects](https://learn.chatgpt.com/docs/projects)

For a quick manual check in the installed folder:

```zsh
./runtime/bin/autoassist doctor
./runtime/bin/autoassist version
```

### Phone and always-on Mac setup

On the Mac, open ChatGPT and sign in to the same account and workspace you use on your phone. Go to **Settings → Connections → Control this Mac or PC → Set up/Add**, scan the QR code in the ChatGPT phone app, and enable **Keep this Mac awake**; leave the Mac plugged in and online. On your phone, open [**Remote**](https://learn.chatgpt.com/docs/remote-connections) and start or continue the AutoBot Codex chat using [Voice](https://help.openai.com/en/articles/20001275-chatgpt-work-and-codex). Ask a read-only question about a detail in the local Project to confirm the connection.

## Upgrade an existing installation

Close or finish work in the target Autobot Project before upgrading. Quiesce that installation only; other Projects do not need to stop. Keep room for a staged copy and recoverable backup. The installer checks free space before changing the target.

Extract the new official package and run:

```zsh
./install.sh --destination "$HOME/AutoAssist" --target-quiescent
```

The installer recognizes the published old receipt and compares original product files, your installed bytes and the new version. It preserves user files and detects conflicting custom instructions or policies before replacing them. Resolve a reported conflict using the staged guidance; do not delete your customization just to make an update pass.

The transaction preserves state, checks for concurrent changes and retains recoverable evidence. An interruption is recovered through the same installer. Do not manually delete a transaction journal or move swap directories while recovery is pending.

To repair product-file or permission drift from the same release, use `./install.sh --destination "$HOME/AutoAssist" --repair --target-quiescent`. To restore a retained earlier code version, use `./install.sh --destination "$HOME/AutoAssist" --rollback --target-quiescent`. Rollback preserves current user state and refuses an incompatible schema.

If you installed elsewhere, replace `"$HOME/AutoAssist"` in every upgrade, repair and rollback command with your exact installed path. Supply the same `--home-root` used at installation when it was nondefault. For example, an upgrade of the alternate folder above is `./install.sh --destination "$HOME/Autobot Workspace" --home-root "$HOME" --target-quiescent`.

## Local liveness

The optional service is off by default. It is scoped to one installation and records local liveness and pending work; it does not run a model or control desktop apps. Use `--enable-launch-agent` to opt in after Node 22+ is available. An update retains an already configured service unless `--skip-launch-agent` explicitly disables it. An unavailable runtime cannot arm it.

Native scheduled reasoning is configured separately through supported app controls. It requires the app, computer and local files to remain available. Verify an actual run before relying on it. [Scheduled tasks](https://learn.chatgpt.com/docs/automations)

## Remove the installation

Finish work in the target Project, then run this from the installed folder:

```zsh
./uninstall.sh --destination "$HOME/AutoAssist" --target-quiescent
```

For another folder or account root, provide both exact values, for example `./uninstall.sh --destination "$HOME/Autobot Workspace" --home-root "$HOME" --target-quiescent`. The reversible path stops only the receipt-bound service, removes only owned projections and moves the folder to recoverable Trash. It preserves user data and unrelated global skills.
