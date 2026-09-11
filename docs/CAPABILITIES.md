# What works locally, and what needs the native app

Autobot installs a workspace and local tools. It does not install or unlock ChatGPT, Codex, Voice, Computer Use, connectors or a cloud service.

| Capability | Base state | How to establish readiness |
| --- | --- | --- |
| Workspace, privacy-zone scaffolding and uninstall | Local, no account or API key | Install and run doctor |
| Task, requirement, evidence and context runtime | Requires Node.js 22+ | Doctor must find a supported executable |
| Local Project access | Manual until checked | Add the installed folder as the primary folder of a local Project; verify a harmless file read |
| Native Goals or long-running controls | Unverified until available in the current app | Inspect supported controls in the current task; use a local checkpoint if unavailable |
| Voice | Optional, account/app dependent | Configure in the native app; microphone permission is user-granted |
| Full Computer Use | Optional, account/app and OS-permission dependent | Configure only needed apps, then perform a harmless foreground read |
| Connectors | Optional, none preconfigured | Connect the user's chosen account; verify exact identity and scope |
| Native scheduled reasoning | Optional, none preconfigured | Create through supported native controls and inspect an actual run |
| Local liveness tick | Optional, instance-scoped | Verify the exact installed service and its heartbeat; it does not run a model |
| Automatic terminal-response hook | Not installed by this package | Use the explicit local completion check; do not assume every assistant response is intercepted |

Record each optional capability as supported-and-verified, available-not-configured, unavailable or manual. A local configuration flag is not proof that a native app feature is operational. The first-time skill should report what it actually observed, the app/platform context, and what remains manual.

The local files can be used without a native account. Reasoning and app actions require the user's own supported native environment, plan, usage and permissions. Autobot makes no API calls and enables no paid model service during installation. Optional native work uses the user's applicable usage allowance.

Local Projects differ from uploaded web project context. In the desktop app, attach the installed folder and make it primary so project instructions are discovered. A web project does not directly expose a local folder. [Projects](https://learn.chatgpt.com/docs/projects)

Desktop schedules that need local files require the computer and app to remain available. A deterministic local heartbeat is separate from a native scheduled reasoning task. [Scheduled tasks](https://learn.chatgpt.com/docs/automations)

See [Skills and plugins](https://learn.chatgpt.com/docs/skills-and-plugins) for the native extension model and [Node.js downloads](https://nodejs.org/en/download) for an optional supported runtime. Install dependencies yourself through their official routes; Autobot does not change your shared toolchain.
