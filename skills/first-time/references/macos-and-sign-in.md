# Dedicated laptop, sign-in, and macOS permissions

## Readiness checklist

Ask the user to confirm these facts; do not change them silently:

- the Mac is dedicated to the intended owner or uses a separate macOS account for AutoAssist;
- macOS and ChatGPT are current enough for the required native features;
- a screen lock is enabled and only the intended owner can unlock the account;
- FileVault and a recoverable local backup are considered in the user's own security plan;
- the AutoAssist root is in an accessible local folder, not Desktop, Documents, Downloads, Photos, iCloud, or an external volume;
- stronger trust-domain isolation uses separate macOS accounts or laptops, not a claim that folder permissions equal hardware isolation.

Record only `DEDICATED_LAPTOP_READY=yes` after the user confirms the setup is suitable. A negative or uncertain result remains a setup blocker.

## ChatGPT sign-in

Supported labels are `already-signed-in`, `native-sso`, `os-sso`, and `browser-sso`.

1. Open only the native ChatGPT app or the user's selected first-party browser profile.
2. Tell the user which first-party sign-in surface is active.
3. Hand control to the user for account selection, passkey, password, MFA, Keychain, consent, or recovery.
4. After the user finishes, read back the visible non-secret account label and record exactly that label in `profile.conf`.

Never inspect browser credential storage, the clipboard, password managers, cookies, Keychain items, authentication messages, or network tokens. Never save an email label as if it proves a browser profile or destination; each receives its own label.

## Permission inventory

Permissions are capability-specific and optional until a requested feature needs them:

| Capability | Likely macOS permission | Least-privilege rule |
| --- | --- | --- |
| ChatGPT Voice | Microphone | Grant only to the first-party ChatGPT app if the user wants Voice. |
| Foreground Computer Use | Accessibility and Screen Recording | Grant only to the exact app/runtime named by the first-party prompt. Background supervisors remain code-only. |
| Controlling another desktop app | Automation, when macOS asks | Approve only the exact app-to-app relationship required for an authorized task. |
| Local files | Files and Folders for a selected location | Keep AutoAssist in an already accessible folder. Do not request broad protected-folder access for convenience. |
| Notifications | Notifications | Optional; not required for correctness. |

Do not request Full Disk Access as a default. Do not approve any permission yourself. Record one of these user-reported labels per permission:

- `confirmed-by-user`
- `deferred-not-needed`
- `required-later`

`required-later` is a blocker only when the current requested capability depends on it.

Record immediate capabilities in `REQUESTED_CAPABILITIES` and bind them as follows:

- `voice` requires `PERMISSION_MICROPHONE=confirmed-by-user`.
- `computer-use` requires both Screen Recording and Accessibility to be `confirmed-by-user`.
- `app-automation` requires Automation to be `confirmed-by-user`.
- `protected-local-files` requires Files and Folders to be `confirmed-by-user` for the exact selected location.
- `native-goal` requires the local native-Goal persistence contract; it has no macOS permission.

Do not list a capability merely to make setup look complete. If the user wants it now, resolve its user-present gate. If the user does not want it now, omit it and retain a truthful deferred permission label.
