# Issue tracking

Autobot uses the single private `state/core.json` store for active issue records, alongside its task, memory, handoff and evidence state. Use `runtime/bin/autoassist core issue-record`, `issue-update`, `issue-list` and `issue-verify`. See [the command reference](../../docs/CLI-REFERENCE.md).

Record each defect once with an ID, severity, owner, discovery time, symptoms, reproduction, likely cause, remediation, affected systems and verification criteria. The owner may advance investigation states. Only a separate reviewer who inspected repair evidence may use `issue-verify` to mark it verified. Different labels alone do not prove independent review.

The adjacent `issues.json` is the retained v0.1 file. Fresh releases contain an empty seed; upgrades preserve existing user bytes as read-only historical audit. The current runtime does not write to it or automatically import it. Do not maintain two active issue registries.

For an unresolved historical issue, inspect its original record and create one corresponding core issue with the same safe ID (or an explicit stable mapping). Put a reference to the historical ID and file in the reproduction or root-cause text. Keep the original file and evidence unchanged; use the core record for all subsequent status changes and current verification. A formerly verified historical record remains history and must not acquire new current verification merely from migration.
