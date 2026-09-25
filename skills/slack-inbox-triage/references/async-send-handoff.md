# Optional delayed-send read-only handoff

Do not use this reference automatically. It applies only when the user separately authorizes a read-only observer and the host supports that capability.

## Preconditions

- The first-party account, workspace, recipient, thread/audience, and exact composer text were freshly verified.
- The exact approved draft hash and version are in the private body-free manifest.
- The send was dispatched exactly once and is recorded as `ack_pending`.

If any precondition is missing, keep foreground ownership and resolve the missing evidence. Never delegate to compensate for an unverified send.

## Observer boundary

The observer may use only supported read-only Slack retrieval. Give it opaque identifiers, the approved hash, dispatch time, and the private manifest path only when the host's authorization model explicitly permits those values. It may look for one exact authored message at the intended destination and report an exact match, duplicate, failure evidence, or no evidence.

It must never control Slack UI, send, retry, edit, delete, react, mark read/unread, save a draft, advance either cursor, or write durable state. Stop after two unchanged polls and return the exact resume point. Do not expose message bodies or endpoints in logs.

The foreground owner must return to the first-party Slack interface, freshly render the destination, and record `sent_verified` only after the exact outgoing result is visible. No-message, duplicate, partial, or ambiguous evidence suppresses all retries and remains `ack_pending` or `ambiguous` until reconciled.
