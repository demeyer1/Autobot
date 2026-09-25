# Voice-mode Slack triage

Use this mode when the conversation is spoken or the user requests hands-free triage. Keep the same snapshot, privacy, mutation, authorization, and verification rules as text mode.

## Pacing

- Open with the visible snapshot total and the three ordinary choices: `leave unread`, `mark read`, and `reply`.
- Present one card, stop speaking, and wait for one decision. Do not stack questions or read opaque IDs, hashes, URLs, or endpoints unless needed.
- Keep the full visual card and complete drafts available in chat. While the user decides, fill the bounded read-only preview window and immediately present the next safe card after queueing a choice. Say `Queued` until the separate mutation has rendered proof.
- A process question, latency complaint, or correction takes precedence over the next card. Pause, answer directly, and wait for clear continuation.

## Spoken card

1. Position, sender, destination, and whether the audience is a DM, group DM, channel, or thread.
2. The exact message when it is 75 words or fewer.
3. For a longer message, a faithful summary followed by the exact ask, decision, deadline, or risk. Offer the full text on request.
4. One context sentence only when it changes the decision.
5. One recommendation and one prompt: `Leave unread, mark read, or reply?`

Mention links or attachments without reading URLs or filenames character by character unless needed. Make a channel or group audience explicit before proposing a reply.

## Commands and drafts

- `leave unread`, `keep it unread`, `skip it`, and `next` retain unread; `mark read`, `no reply`, and `mark red` mark read.
- `reply` enters drafting. `repeat` repeats only the current card or draft. `more context` retrieves only the context needed. `go back` is read-only. `pause`, `resume`, `status`, and `stop` affect the current run.
- A draft starts at `Draft v1` and increments after each wording change. Read the complete current version after each revision. An interruption means the draft was not fully presented until reread or explicitly reviewed.
- `looks good`, `approved`, or `that works` finalizes wording but does not send. `send it`, an explicit version command, or a direct instruction for that exact reply authorizes delivery. A changed destination, audience, thread, or wording requires a new send instruction.
- Before dispatch, say `Sending Draft vN to <destination>.` This is a readback of the already authorized action, not a new approval request.

If speech is overlapping or a state-changing command is unclear, state the interpretation briefly and ask for the exact command. Never guess. On a voice drop, keep queued and ambiguous evidence, discard stale previews, and resume from the durable checkpoint without inferring a send.

After one dispatch with delayed acknowledgement, do not perform another Slack UI mutation. Use the optional handoff only if separately authorized, and say the send is still being verified. Report `Sent and verified` only after foreground rendered proof.
