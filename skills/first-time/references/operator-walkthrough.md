# Active first-use operator walkthrough

Use this reference when setup begins from downloaded release media, when native Computer Use is requested, or when a prior first-use turn was interrupted. The setup skill remains the operator; this file supplies the phase routing and evidence rules.

## Minimal bootstrap before agent takeover

A new user must first reach an agent-capable local Project. Computer Use cannot bootstrap itself. The pre-agent steps are deliberately small: obtain the release ZIP and matching checksum companion, verify and extract them, open `Install.command`, then in ChatGPT or Codex use **Edit project > Add folder > Make primary** for the installed folder. Start a fresh task there and invoke this project-local first-time skill. Do not require Computer Use, an optional account integration or a permission grant for these steps.

Once invoked, take over every supported safe local action. Revalidate and skip any bootstrap prerequisite already established. If the user invoked the skill directly through an explicitly resolved CLI/current-root route, record native Project state as unavailable rather than fabricating a Project selection; continue local-only work.

## Show the plan and resolve context

Tell the user the current phase, the next action and any capability that cannot be handled from the current surface. Keep their original request pending. Resolve one of these contexts without searching protected locations:

- **Release source:** `VERSION`, `Install.command`, `install.sh` and `config/release-allowlist.txt` exist, while `.install-state/managed-by-autoassist` does not. Require the matching official checksum companion and verify it before installation. If the companion is missing, keep the source distinct from an installed root, retrieve the companion from the same official release, and stop before installation if it cannot be verified. Use the local shell execution tool to run `Install.command` or `install.sh`; Computer Use cannot control Terminal.
- **Managed installation:** `.install-state/managed-by-autoassist` and its receipt bind the current root and account home. Run doctor and show the current walkthrough state.
- **Unknown or conflicting root:** stop before mutation and ask for the exact intended local folder. Never scan Desktop, Documents, Downloads, iCloud, Photos, external volumes or other protected locations to find it.

The default install is `<account-home>/AutoAssist`. Do not replace an unrelated folder, a differently owned installation or a customized installed skill. If an existing managed target is intended, follow the documented quiescent update path and preserve three-way conflicts.

## Execute each phase

At every phase, inspect the expected output before recording a checkpoint. If an action succeeded but checkpointing was interrupted, the next turn must revalidate the artifact and advance without repeating the action.

The progress file is one earliest-unresolved cursor. Finishing a later local action must not erase an earlier project, identity, permission, or capability gate. Revalidate local artifacts to skip work already done, then clear the earlier cursor only after fresh post-gate readback at that phase. A later smoke or review cannot make an unresolved earlier gate complete.

1. **Installed:** run the installer through local shell execution, then verify the exact receipt, root and doctor result. Record `installed-receipt`.
2. **Primary local Project:** Revalidate the bootstrap Project binding. Computer Use cannot automate ChatGPT or Codex. If the installed folder is not already the primary folder, leave a `project-primary` user gate with fresh readable evidence and give one exact handoff: in the Project menu choose **Edit project**, **Add folder**, select the installed folder, and **Make primary**. After the user opens a fresh task in that Project, resolve the current working directory and read back `AGENTS.md` plus the project-local first-time skill before recording `primary-project-readback`.
3. **Local configuration:** inspect existing configuration first. Preserve valid user choices and unrelated files. For a new setup use `not-configured` for an unknown ChatGPT account; preserve independently observed browser/profile labels and use `not-configured` only when those fields are also unknown. Never invent identity. Default to the `PRIVATE` zone only, `SHARED` off, tone learning off, connectors read-only, external writes fail-closed, and no optional accounts or capabilities. Initialize zones and atomically write only the documented fixed-schema configuration.
4. **Native capabilities:** use a supported callable capability to inspect only the current foreground target app. Computer Use may operate supported target apps and Finder when authorized; it cannot operate ChatGPT/Codex, Terminal, authentication dialogs, administrator controls or macOS security/privacy prompts. Record observed native availability separately from access evidence. A fresh successful supported invocation in the same project/profile/process/target context may record `observed-effective` without asking the user to restate a permission; saved configuration or a shell probe cannot. Skip optional capabilities that were not requested.
5. **Local smoke:** run doctor. With Node 22 or newer, validate configuration and run the existing local no-external-mutation smoke once. Persist its objective ID in the walkthrough checkpoint. If Node is unavailable, retain `pending-capability/node-unavailable`; do not download a runtime, create another ledger or arm a scheduler.
6. **Independent review:** write pending generated status, checkpoint `ready-for-review`, and provide the current config hash, doctor output and smoke ID to a separate read-only validator. Producer labels and progress records are not acceptance.
7. **Complete:** after genuine independent acceptance, write the existing completion marker, validate it with `--require-marker`, reconcile generated status, read back both status surfaces, then record `complete/marker-readback`. Return to the user's original task and, when safe, perform its first harmless local output through the ordinary AutoAssist objective flow.

Use `scripts/walkthrough-progress.sh --root <root> --account-home <account-home> show` at entry and `record` after verified transitions. This state contains only typed nonsecret resume metadata. It cannot create or replace the completion marker.

## User-only gates

Pause control only when a fresh readable first-party surface explicitly requires one of these actions:

- account selection, password, passkey, MFA, Keychain or recovery;
- a macOS privacy or security grant;
- first activation of the Computer Use plug-in or approval for the exact target app;
- the manual primary-Project step above, because Computer Use cannot operate ChatGPT/Codex.

Before pausing, finish every unrelated safe local action, record `waiting-user` with `fresh-readable-gate`, state the exact surface, requested action, scope and reason, and stop before credential entry or approval. Do not capture a credential-bearing screenshot or ask the user to send a code. Resume only after the user acts and a fresh rendered readback shows the intended account, project or permission state. A spinner, blank tree, timeout or tool error is not a user gate.

If Computer Use is unavailable, record `pending-capability` with `capability-unavailable`, report the exact native step that remains, and continue local work. Do not claim a click, permission or account state that was not observed.

## Identity and retry rules

Keep the selected project, installation, browser profile, signed-in account and target app stable throughout a capability setup. A mismatched or unknown identity blocks account-bound action; it does not authorize switching profiles or adopting another marker. After one failed action, inspect the destination and checkpoint before retrying. After two same-condition attempts without new evidence, preserve the resume point and stop that route.
