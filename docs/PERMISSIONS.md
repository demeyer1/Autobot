# Permissions

AutoAssist does not replace macOS or ChatGPT security controls. It adds a least-privilege operating policy around them.

Three independent permission layers matter:

1. **macOS permissions** decide whether ChatGPT or its Computer Use process can see the screen, use the microphone, or interact with apps.
2. **ChatGPT sandbox and reviewer settings** decide what local commands and file operations can run and when approval is required.
3. **ChatGPT per-app approvals** decide which apps Computer Use may access during a task.

Granting one layer does not grant the others.

## Recommended baseline

- Start in **Ask for approval** mode.
- Keep the AutoAssist Project in a deliberate user-owned folder such as `~/AutoAssist`.
- Enable only the native features you plan to use.
- Approve apps one at a time during a real task.
- Avoid **Always allow** until the app and action class are well understood.
- Do not use **Full access** as the default.
- Never give AutoAssist a password, MFA code, private key, payment credential, or recovery code to store.

OpenAI documents sandbox scope and reviewer behavior as separate controls. Enabling Auto-review changes the reviewer but does not expand the sandbox. Full access can edit any file and run network commands without approval, which materially increases the risk of data loss, leakage, or unexpected behavior. [Permission modes](https://learn.chatgpt.com/docs/permission-modes)

## Permission matrix

| Capability | Permission or setting | What it allows | Limit |
| --- | --- | --- | --- |
| Local Project | User selects the primary folder | Read and edit authorized project files under the active sandbox | A ChatGPT web Project does not automatically have direct local-folder access. [Projects](https://learn.chatgpt.com/docs/projects) |
| Commands and network | ChatGPT sandbox plus reviewer mode | Commands within the configured boundary | Reviewer changes do not expand sandbox scope. [Permission modes](https://learn.chatgpt.com/docs/permission-modes) |
| Voice | Microphone | Spoken conversation | Availability and usage depend on plan, workspace, and rollout. [Voice](https://learn.chatgpt.com/docs/features/voice) |
| Voice screen context | Screen & System Audio Recording and Accessibility | Appshots from the frontmost window, including accessible text | Appshots can include off-screen accessible text and are stored locally with the session after they are added. [Appshots](https://learn.chatgpt.com/docs/appshots) |
| Computer Use visibility | Screen Recording | See app windows | This does not permit clicking or typing. [Computer Use](https://learn.chatgpt.com/docs/computer-use) |
| Computer Use interaction | Accessibility | Click, type, and navigate | This does not approve every app or every sensitive action. [Computer Use](https://learn.chatgpt.com/docs/computer-use) |
| Computer Use app access | Settings > Computer Use plus task-time app approval | Use the named app | “Always allow” is optional; sensitive or disruptive actions can still prompt. [Computer Use](https://learn.chatgpt.com/docs/computer-use) |
| Protected folders | Additional macOS approval may appear | Access Desktop, Downloads, Music, or another protected location | Avoid probing protected locations merely to discover access. [Troubleshooting](https://learn.chatgpt.com/docs/reference/troubleshooting) |
| Notifications | ChatGPT desktop notification permission | Surface completion, questions, permissions, and blockers | Notification does not prove an external action succeeded. [Notifications](https://learn.chatgpt.com/docs/notifications) |
| Local long-running work | Mac, app, workspace, and power state remain available | Continue a local Goal or schedule | It is not cloud-hosted merely because it is long-running. [Long-running work](https://learn.chatgpt.com/docs/long-running-work) |

## Computer Use setup

According to the current [Computer Use documentation](https://learn.chatgpt.com/docs/computer-use):

1. Switch to ChatGPT Work or Codex in the desktop app.
2. Open Plugins and install or enable Computer Use.
3. Turn on the Computer Use server and skill.
4. In macOS System Settings, grant the named Computer Use process Screen Recording and Accessibility.
5. In ChatGPT **Settings > Computer Use**, configure app access.
6. During a task, review the prompt for the exact app and action.

AutoAssist never approves a macOS privacy prompt for the user. The user must review the process name, requested access, and reason in System Settings.

Computer Use also cannot automate ChatGPT/Codex itself, Terminal, an administrator authentication flow or a macOS security/privacy approval. The first-time agent performs supported local work and supported target-app actions, then pauses only when a fresh readable surface names one of those user-only steps. A blank capture, spinner, tool failure or elapsed time is not an authentication or permission prompt. After the user acts, the agent must re-read the same project, profile/account and capability surface before continuing.

Configuration records native feature availability separately from user-confirmed permission. A shell test, receipt, prior completion marker or synthetic test fixture does not prove that Computer Use is installed, that the intended app is approved, or that a macOS permission is present. An unavailable optional feature remains a precise resumable capability; local/private setup can continue.

Use a structured connector or MCP tool for authorized reads and repeatable data access when it is available. Use Computer Use for visual interaction in the signed-in first-party app. AutoAssist's default external-write policy still requires a rendered preflight and postflight.

### Locked use

Locked use is an optional native ChatGPT feature on macOS. Its setup installs an Apple authorization plug-in and can temporarily unlock the Mac only for an active, trusted Computer Use turn while blocking local use.

It is not required by AutoAssist and is not a general unattended-unlock mechanism. Review the current [Computer Use documentation](https://learn.chatgpt.com/docs/computer-use) before enabling it.

## Voice permissions and limits

For Voice:

- Start a new empty chat or task in Voice mode. Existing non-Voice chats provide dictation, while a prior Voice chat can be resumed.
- Grant microphone access when prompted.
- Enable screen context only if the task needs it.
- Review the appshot before adding it to the conversation.
- Remember that accessible text can extend beyond what is visibly on screen.

Current documented limits include:

- one active Voice chat across desktop at a time;
- plan-dependent Voice allowance in rolling five-hour windows;
- Codex usage consumed by tasks started through Voice;
- workspace controls and rollout-dependent availability.

Source: [ChatGPT Voice](https://learn.chatgpt.com/docs/features/voice)

## Long-running and scheduled work

Starting a Goal does not broaden access. The same sandbox and approvals remain in effect, and the work pauses when a real decision is required.

For local work:

- enable **Prevent sleep while running** when appropriate;
- keep the Mac, app, and workspace available;
- avoid two chats editing the same files;
- use separate worktrees when parallel chats must change the same repository;
- expect a task to pause at authentication, permission, or ambiguous user-decision gates.

Desktop scheduled tasks that use a local Project also need the computer and app running. Web scheduled tasks run in a different environment and do not inherit direct local-folder access. [Long-running work](https://learn.chatgpt.com/docs/long-running-work), [Scheduled tasks](https://learn.chatgpt.com/docs/automations)

## Plan and workspace boundaries

Native feature availability can differ by plan, workspace policy, supported region, rollout, and usage budget. AutoAssist cannot enable a ChatGPT feature that the signed-in account does not have.

OpenAI's published statement that Business, Enterprise, and Edu data is not used to train models by default applies to those plans. Do not generalize that statement to every consumer account. [ChatGPT Work cloud security](https://learn.chatgpt.com/docs/enterprise/chatgpt-work-cloud-security)

## Revoking access

Revoke native permissions where they were granted:

- macOS System Settings for Microphone, Screen & System Audio Recording, and Accessibility;
- ChatGPT Settings for Computer Use app access, Voice screen context, and optional Locked use;
- ChatGPT Project settings for attached folders and connected sources;
- ChatGPT permission mode settings for sandbox/reviewer posture.

Removing the AutoAssist folder does not automatically revoke ChatGPT or macOS permissions. Revocation is a separate user action.

**Documentation date:** 2026-08-26. Follow the linked OpenAI pages for the current UI and feature availability.
