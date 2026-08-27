# First-use workflow

Use this sequence for a new installation or a failed setup repair. Keep the user's original task pending until the gate passes.

## 1. Establish local state

- Pin the AutoAssist root and confirm it is a child of the current macOS user's home or another user-selected accessible local folder.
- Run `AUTOASSIST_ACCOUNT_HOME=<account-home> runtime/bin/autoassist doctor --quiet`, scoping that variable to the doctor process only. An expected first-run failure is setup state, not permission to weaken a control.
- Inspect only the release files and configuration named by this skill. Do not enumerate protected folders.
- Confirm the laptop is intended for AutoAssist and is not a shared unmanaged machine. Use the readiness checklist in `macos-and-sign-in.md`.

## 2. Handle user-present boundaries

- Ask the user to complete ChatGPT sign-in in the native first-party app or browser using their chosen SSO route.
- Verify only the rendered account label they approve for local storage.
- Explain each relevant macOS permission separately. The user opens System Settings and grants or declines it. Record `confirmed-by-user`, `deferred-not-needed`, or `required-later`; do not infer live TCC state.
- If authentication, MFA, Keychain, a passkey, or a permission prompt appears, stop control before the user acts and resume only after the first-party surface is stable.

## 3. Configure locally

- Initialize all four owner-only zone folders. Mark only the user's selected zones active.
- Keep `SHARED` disabled unless the user explicitly opts in.
- Write `config/profile.conf` and `config/first-time.conf` from the schema in `configuration.md`. `REQUESTED_CAPABILITIES` may be empty when no optional capability is needed. Otherwise list every capability intended for immediate use; each listed capability must have its required permission state resolved.
- For each opted-in communication profile, create the exact owner-only aggregate-pattern artifact defined in `configuration.md` inside its mapped zone. Do not import or retain source messages during setup.
- Record native Goal pairing as required for persistent work. A local AutoAssist objective and a native ChatGPT Goal should share one recognizable assignment label; setup itself does not manufacture an unrelated Goal.

## 4. Verify without external mutation

- Run doctor again with the same process-scoped `AUTOASSIST_ACCOUNT_HOME=<account-home>` binding.
- Run `skills/first-time/scripts/validate-setup.sh --root <root> --account-home <account-home> --smoke`. The explicit account home binds doctor to the same installed skill and LaunchAgent definition created by an isolated `--home-root` installation.
- The smoke must finish one local objective through `research_complete`, `draft_complete`, `destination_updated`, `save_confirmed`, and `rendered_readback_verified`. Every evidence record must state `external_mutation=false`, and producer and validator labels must differ.
- Run `skills/first-time/scripts/write-status.sh --root <root> --account-home <account-home> --state pending`. The writer owns only `01_PROJECTS/first-time/STATUS.md` and the one first-time entry in `PROJECTS.md`; it preserves every unrelated project entry.
- Ask an independent read-only validator to inspect current files and smoke state. Do not accept the setup actor's own narrative as terminal evidence.

## 5. Seal and reread

After independent acceptance, write `.install-state/first-time-complete` atomically with mode `600`:

```text
SETUP_VERSION=1
COMPLETED_AT=<UTC ISO-8601>
VALIDATOR_LABEL=<non-secret validator identity>
SETUP_CONFIG_SHA256=<SHA-256 of config/first-time.conf>
SMOKE_OBJECTIVE_ID=<local smoke objective ID>
```

Then run validation with the same `--root`, `--account-home`, and `--require-marker`. If it fails, reopen setup at the earliest failed check. After it passes, run `skills/first-time/scripts/write-status.sh --root <root> --account-home <account-home> --state complete` and read back both generated status surfaces. The writer validates the marker again, fails closed on ambiguous first-time entries, and never rewrites another project. Do not erase the original user task.

## Stop conditions

Stop at a precise user-required gate when the user has not completed sign-in, a needed permission remains ungranted, the laptop is not suitable, or a requested label or privacy choice is genuinely ambiguous. Continue all unaffected local setup first. Never substitute another account, browser profile, destination, or permission scope.
