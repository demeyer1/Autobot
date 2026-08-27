# Privacy zones and communication learning

## Zone controls

AutoAssist uses four owner-only folders:

- `PRIVATE`: sensitive facts and preferences that never cross zones automatically.
- `FAMILY_FRIENDS`: personal relationships, logistics, and opted-in personal communication patterns.
- `WORK`: organizations, projects, colleagues, customers, and professional communication patterns.
- `SHARED`: the minimum facts the user explicitly allows across zones.

Create every folder with mode `700` and every contained index or profile with mode `600`. Select the narrowest zone for each record. A zone label is not permission to read the entire folder. `SHARED_ZONE_OPT_IN=no` is the safe default.

Family/friends, work, and shared controls are independent. A contact appearing in both personal and work contexts does not merge records. Purpose and current user instruction determine access; the communication channel alone does not.

## Opt-in tone learning

Default `TONE_LEARNING=disabled`. If the user opts in:

1. Select profile IDs separately, such as `email-work-external`, `email-work-internal`, `chat-work-internal`, `text-family-friends`, or `social-public`.
2. Ask the user to authorize the specific source examples or conversation set. Do not perform bulk history ingestion by default.
3. Derive only the bounded aggregate dimensions defined in `configuration.md`; do not save free-text observations or vocabulary excerpts.
4. Show the aggregate observations to the user before saving them.
5. Save only the approved aggregate pattern in the matching zone. Set `RAW_MESSAGE_RETENTION=disabled`; do not retain bodies, attachments, message IDs, authentication codes, or unrelated third-party details.
6. Never apply one profile to another channel or audience without explicit direction.

First-time setup creates one empty aggregate-pattern artifact for every opted-in profile. Each artifact must use the exact ID, channel, audience, and zone mapping in `configuration.md`, be mode `600`, and occur exactly once across all communication-profile folders. It must declare aggregate-only learning, disabled raw-message retention, and no retained source examples. It must not read live messages or send a test communication. A communication test is a later, separately authorized task.

The artifact set is closed: every entry under a canonical `COMMUNICATION-PROFILES` root must correspond to exactly one selected `TONE_PROFILE_IDS` value at its mapped path. Remove stale or undeclared local profile artifacts before completion; never silently adopt them into the configuration.

After later opt-in learning, the artifact may move from the exact eight-record initialized schema to the exact 16-record learned-aggregate schema in `configuration.md`. Both forms remain closed schemas. Raw message bodies, quotes, example text, message identifiers, and arbitrary prose are invalid in either form.

## External-write and attribution defaults

- Connectors, apps, APIs, MCP tools, and browser integrations are read-only.
- A later authorized external write uses the signed-in first-party interface, exact destination and account preflight, and rendered postflight.
- Fail closed if the delivery route forces a non-removable AI or ChatGPT label.
- Do not add AI attribution to editable content and do not claim to suppress first-party platform disclosures.
- Ambiguous outcomes require destination readback before retry.
