# First-time configuration

Write configuration only under the pinned AutoAssist root. Use `umask 077`, an adjacent temporary file, `chmod 600`, and an atomic rename. Never source these files as shell code; treat them as validated `KEY=VALUE` records.

Values are human-readable labels and enumerated statuses. They must not contain passwords, passkeys, tokens, cookies, recovery keys, private keys, authentication codes, payment data, or raw message text.

## `config/profile.conf`

Required keys:

```text
AUTOASSIST_USER_LABEL=<non-secret owner label>
AUTOASSIST_HOME=<absolute pinned AutoAssist root>
CHATGPT_ACCOUNT_LABEL=<rendered non-secret account label>
DEFAULT_BROWSER_LABEL=<browser name>
DEFAULT_BROWSER_PROFILE_LABEL=<visible profile label>
DEFAULT_DESTINATION_LABEL=<usual local or account destination label>
PRIVACY_MODE=separate-zones
TERMINAL_UPDATES=chatgpt
```

The account, browser, profile, and destination labels are separate identity fields. A value in one field does not prove another.

## `config/first-time.conf`

Required keys and allowed values:

```text
SETUP_VERSION=1
DEDICATED_LAPTOP_READY=yes
CHATGPT_SIGN_IN_METHOD=already-signed-in|native-sso|os-sso|browser-sso
CHATGPT_SIGN_IN_CONFIRMED=yes
REQUESTED_CAPABILITIES=<empty or comma-separated subset of voice,computer-use,app-automation,protected-local-files,native-goal>
PERMISSION_MICROPHONE=confirmed-by-user|deferred-not-needed|required-later
PERMISSION_SCREEN_RECORDING=confirmed-by-user|deferred-not-needed|required-later
PERMISSION_ACCESSIBILITY=confirmed-by-user|deferred-not-needed|required-later
PERMISSION_AUTOMATION=confirmed-by-user|deferred-not-needed|required-later
PERMISSION_FILES_AND_FOLDERS=confirmed-by-user|deferred-not-needed|required-later
ACTIVE_PRIVACY_ZONES=<comma-separated subset of PRIVATE,FAMILY_FRIENDS,WORK,SHARED>
SHARED_ZONE_OPT_IN=yes|no
TONE_LEARNING=disabled|opt-in
TONE_PROFILE_IDS=<empty or comma-separated approved profile IDs>
RAW_MESSAGE_RETENTION=disabled
CONNECTOR_WRITE_MODE=read-only
EXTERNAL_WRITE_POLICY=first-party-rendered-only
NO_ATTRIBUTION_POLICY=fail-closed
NATIVE_GOAL_PERSISTENCE=required
```

All capabilities are optional. An empty `REQUESTED_CAPABILITIES` value is valid. Every capability that is requested must already have its complete setup state resolved before validation can pass:

- `voice` requires `PERMISSION_MICROPHONE=confirmed-by-user`.
- `computer-use` requires both `PERMISSION_SCREEN_RECORDING=confirmed-by-user` and `PERMISSION_ACCESSIBILITY=confirmed-by-user`.
- `app-automation` requires `PERMISSION_AUTOMATION=confirmed-by-user`.
- `protected-local-files` requires `PERMISSION_FILES_AND_FOLDERS=confirmed-by-user`.
- `native-goal` requires `NATIVE_GOAL_PERSISTENCE=required`.

`required-later` remains an honest unresolved status, but a capability that depends on it is not ready and cannot pass completion validation. Never change a permission status to `confirmed-by-user` until the owner has actually confirmed the grant in System Settings.

If `SHARED` appears in `ACTIVE_PRIVACY_ZONES`, `SHARED_ZONE_OPT_IN` must be `yes`; otherwise it must be `no`. If tone learning is disabled, `TONE_PROFILE_IDS` must be empty. If it is opt-in, every identifier must be separately approved and scoped to its channel and audience.

## Tone-profile artifacts

For each approved `TONE_PROFILE_IDS` entry, create exactly one artifact at the mapped path. Its parent directory must be mode `700`; the artifact must be a regular, non-symlink file at mode `600`.

The materialized artifact set under the four canonical `COMMUNICATION-PROFILES` roots must equal `TONE_PROFILE_IDS` exactly. Do not leave an undeclared file, alternate profile ID, nested directory, symlink, or other entry in those roots. When tone learning is disabled, those roots may be absent or empty but must contain no artifacts.

| Profile ID | Channel | Audience | Zone and relative path |
|---|---|---|---|
| `email-work-external` | `email` | `work-external` | `WORK/COMMUNICATION-PROFILES/email-work-external.md` |
| `email-work-internal` | `email` | `work-internal` | `WORK/COMMUNICATION-PROFILES/email-work-internal.md` |
| `chat-work-internal` | `chat` | `work-internal` | `WORK/COMMUNICATION-PROFILES/chat-work-internal.md` |
| `text-family-friends` | `text` | `family-friends` | `FAMILY_FRIENDS/COMMUNICATION-PROFILES/text-family-friends.md` |
| `social-public` | `social` | `public` | `SHARED/COMMUNICATION-PROFILES/social-public.md` |

Use this exact initialized schema, substituting the mapped values:

```text
PROFILE_ID=<mapped profile ID>
CHANNEL=<mapped channel>
AUDIENCE=<mapped audience>
ZONE=<mapped zone>
LEARNING_MODE=aggregate-only
RAW_MESSAGE_RETENTION=disabled
SOURCE_EXAMPLES_RETAINED=no
PATTERNS_STATUS=empty-awaiting-user-approved-examples
```

The initialized artifact records only scope and retention policy. It contains no message, quote, body, example, or source text. After the user opts in, authorizes source examples, and approves the derived result, replace `PATTERNS_STATUS` and add only this bounded aggregate schema:

```text
PATTERNS_STATUS=learned-aggregate
AGGREGATE_SAMPLE_COUNT=<integer from 1 through 999999>
FORMALITY=casual|balanced|formal
DIRECTNESS=direct|balanced|gentle
WARMTH=reserved|balanced|warm
BREVITY=brief|balanced|detailed
EMOJI_FREQUENCY=none|rare|sometimes|frequent
GREETING_STYLE=none|brief|personal
CLOSING_STYLE=none|brief|personal
```

The learned form contains the seven base scope/retention records plus `PATTERNS_STATUS` and the eight bounded aggregate records above, for exactly 16 records. Do not add prose or free-text fields. This allows a later `--require-marker` health check to validate learned aggregates without accepting raw messages or source examples. Work profiles stay physically and logically under `WORK`; the family/friends profile stays under `FAMILY_FRIENDS`; the public profile requires an active, explicitly opted-in `SHARED` zone.

Run validation with both boundaries explicit when the account home differs from the current shell's home:

```zsh
skills/first-time/scripts/validate-setup.sh \
  --root <autoassist-root> \
  --account-home <account-home>
```

The validator passes `AUTOASSIST_ACCOUNT_HOME=<account-home>` only to the installed runtime's doctor process. It does not replace `HOME` or use the account home as the AutoAssist data root.

## Completion marker

`.install-state/first-time-complete` is evidence that setup passed, not a preference file. Create it only after doctor, deterministic setup validation, the local smoke objective, and an independent read-only review pass. `scripts/validate-setup.sh --require-marker` verifies its schema and binding to the current setup config.
