# First-use workflow

Use this sequence for a new installation or failed setup repair. The operator actively performs each safe local step and uses `operator-walkthrough.md` for UI routing and interruption recovery. Keep the user's original task pending until the applicable gate passes.

## 1. Establish local state

- Pin the AutoAssist root and confirm it is a child of the current macOS user's home or another user-selected accessible local folder.
- Run `AUTOASSIST_ACCOUNT_HOME=<account-home> runtime/bin/autoassist doctor --quiet`, scoping that variable to the doctor process only. Base integrity may pass while advanced runtime is unavailable. That state permits local inspection, privacy-zone initialization, repair, and uninstall, but it does not permit advanced objectives or a scheduler.
- Inspect only the release files and configuration named by this skill. Do not enumerate protected folders.
- Default to local-only operation. Ask the narrower readiness question only when a requested capability needs a stronger trust boundary.

## 2. Handle user-present boundaries

- If the user requests an account-backed capability and sign-in is not already freshly verified, ask them to complete sign-in in the native first-party app or browser using their chosen SSO route. Accountless readiness does not require this step.
- Verify only the rendered account label they approve for local storage.
- Resolve only access required by selected immediate capabilities. The user opens System Settings and grants or declines a real prompt. Record native capability state separately from `confirmed-by-user`, fresh same-context `observed-effective`, `deferred-not-needed`, or `required-later`; do not infer live TCC state from saved files or shell probes.
- If authentication, MFA, Keychain, a passkey, or a permission prompt appears, stop control before the user acts and resume only after the first-party surface is stable.

## 3. Configure locally

- Initialize all four owner-only zone folders. For a new setup mark only `PRIVATE` active unless the user requests another zone.
- Keep `SHARED` disabled unless the user explicitly opts in.
- Inspect before writing. Preserve valid existing labels and choices. Write `config/profile.conf` and `config/first-time.conf` atomically from the schema in `configuration.md`; use `not-configured` rather than asking for an unused optional identity. `REQUESTED_CAPABILITIES` may be empty. Every requested capability must bind both observed native availability and current effective access evidence as defined in `configuration.md`.
- For each opted-in communication profile, create the exact owner-only aggregate-pattern artifact defined in `configuration.md` inside its mapped zone. Do not import or retain source messages during setup.
- Record native Goal pairing as required for persistent work. A local AutoAssist objective and a native ChatGPT Goal should share one recognizable assignment label; setup itself does not manufacture an unrelated Goal.

## 4. Verify without external mutation

- Run doctor again with the same process-scoped `AUTOASSIST_ACCOUNT_HOME=<account-home>` binding.
- When doctor reports runtime `available`, run `skills/first-time/scripts/validate-setup.sh --root <root> --account-home <account-home> --smoke`. If it reports runtime `unavailable` or `unsupported`, do not create a scheduler or alternate state ledger; report the Node 22+ prerequisite and leave advanced setup incomplete.
- The smoke must finish one local objective through `research_complete`, `draft_complete`, `destination_updated`, `save_confirmed`, and `rendered_readback_verified`. Every evidence record must state `external_mutation=false`, and producer and validator labels must differ.
- Run `skills/first-time/scripts/write-status.sh --root <root> --account-home <account-home> --state pending`. The writer owns only `01_PROJECTS/first-time/STATUS.md` and the one first-time entry in `PROJECTS.md`; it preserves every unrelated project entry.
- Ask an independent read-only validator to inspect current files and smoke state. Progress checkpoints and producer labels are resume aids, not terminal evidence.

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
