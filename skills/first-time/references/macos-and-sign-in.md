# Dedicated laptop, sign-in, and macOS permissions

## Readiness checklist

Use `DEDICATED_LAPTOP_READY=local-only` by default. Ask about stronger readiness only when the user enables a capability or trust boundary that depends on it. Do not present the whole list as a mandatory questionnaire. When stronger isolation is requested, confirm only the relevant facts:

- the Mac is dedicated to the intended owner or uses a separate macOS account for AutoAssist;
- macOS and ChatGPT are current enough for the required native features;
- a screen lock is enabled and only the intended owner can unlock the account;
- FileVault and a recoverable local backup are considered in the user's own security plan;
- the AutoAssist root is in an accessible local folder, not Desktop, Documents, Downloads, Photos, iCloud, or an external volume;
- stronger trust-domain isolation uses separate macOS accounts or laptops, not a claim that folder permissions equal hardware isolation.

Record `DEDICATED_LAPTOP_READY=yes` only after the user confirms the applicable checklist. A negative or uncertain answer blocks the stronger requested capability; it does not block local-only installation, doctor, privacy scaffolding or uninstall.

## ChatGPT sign-in

Sign-in is optional. The safe accountless configuration is `CHATGPT_SIGN_IN_METHOD=not-configured`, `CHATGPT_SIGN_IN_CONFIRMED=no`, and `CHATGPT_ACCOUNT_LABEL=not-configured`. Browser and browser-profile labels are independent; preserve a real already observed label or use `not-configured` when unknown. Do not open a sign-in surface unless the user requests an account-backed capability.

Supported configured labels are `already-signed-in`, `native-sso`, `os-sso`, and `browser-sso`.

1. Reuse the current intended signed-in app/profile when fresh readback already proves it. Otherwise open only the native ChatGPT app or the user's selected first-party browser profile.
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

Do not request Full Disk Access as a default. Do not approve any permission yourself. Do not ask again when the current intended process and capability already have fresh verified access. Record native availability independently, then record one of these bounded labels per permission:

- `confirmed-by-user`
- `observed-effective`, only after a fresh successful supported invocation in the same project/profile/process/target-app context
- `deferred-not-needed`
- `required-later`

`observed-effective` is operational evidence, not user confirmation. Never derive it from saved configuration, a receipt, a shell probe, a synthetic test fixture or a different account/profile.

`required-later` is a blocker only when the current requested capability depends on it.

Record immediate capabilities in `REQUESTED_CAPABILITIES` and bind them as follows:

- `voice` requires current effective microphone access.
- `computer-use` requires current effective Screen Recording and Accessibility access.
- `app-automation` requires current effective Automation access.
- `protected-local-files` requires current effective Files and Folders access for the exact selected location.
- `native-goal` requires the local native-Goal persistence contract; it has no macOS permission.

Do not list a capability merely to make setup look complete. If the user wants it now, resolve its user-present gate. If the user does not want it now, omit it and retain a truthful deferred permission label.
