# Local runtime command reference

Entry: `./runtime/bin/autoassist core ACTION < request.json`. One JSON response `{ok:true,result:...}`; errors `{ok:false,error:stable_code}` on stderr with nonzero exit. JSON input maximum 1 MiB. Evidence must be a regular file under the physical installation (no symlink ancestor/hardlink), maximum 1 MiB. Copy output/evidence into authorized installation staging before registration. Store `state/core.json`, schema 2, maximum 16 MiB. No external actions/model/UI/network. Node 22+ required for advanced commands only; version/help/zones/installation doctor remain shell.

`core help` lists actions. `read` without args returns root summaries and counts, not all private memory. `read {root_id}` exposes that task and readiness; `export {root_id}` is a private user-data export. Root-level output completion requires all deliverable stages and all enrolled requirements; status distinguishes historical legacy completion. Native terminal hook is unavailable, and label/source strings are not authentication.

`capabilities {}` reports local attestation, heartbeat, recovery and scoped-memory support separately from optional native-app capabilities. `heartbeat {root_id?,max_checkpoint_age_ms?,no_progress_limit?}` is read-only: it evaluates the current checkpoint and semantic fingerprint and returns a pause/foreground-resume disposition. It never runs a model, starts a schedule or advances a task. `tick` stores a bounded heartbeat receipt and continues to require a separate foreground actor for work.

## Task and verification sequence

1. `root-create`: `{root_id,title,intent,source:"direct_user",target:{kind:"local",destination:"03_OUTPUTS/report.md"},content_sha256?}`. Default deliverable ID is `default`. External target requires `{kind:"external",destination,account,recipient}`. No accounts or authority are prefilled. The API retains explicit user provenance but does not independently authenticate it.
2. `claim`: `{root_id,actor,lease_ms?}` returns `{actor,token,expires_at}`. Default 5 minutes, maximum 1 hour. Renewal includes same `owner_token`. Mutations below include `{root_id,owner_token,actor}`. Optional `expected_revision` enables store-level CAS. Expired/missing owner cannot mutate.
3. `deliverable-add`: owner envelope + `{deliverable_id,title,intent?,target,content_sha256?}`. Existing output cannot be replaced by a child completion.
4. `requirements`: owner envelope + `{deliverable_id?,items:[{id,summary,target,mandatory?,depends_on?:[id]}]}`. Retain IDs; identical contracts are byte-identical no-ops. Unchanged intent cannot drop/downgrade obligations. Independent coverage/support is required for enrolled requirements. A changed requirement contract reopens progressed stages under a fresh attempt so the same artifact can receive current review; an identical contract remains a no-op.
5. `content`: owner envelope + `{deliverable_id?,content_sha256,target?}` binds exact expected artifact. Content changes create new attempt and invalidate prior stage acceptance.
6. `checkpoint`: owner envelope + `{summary,next_action}`. `failure`: owner envelope + `{code,condition}` records signature; two repeated conditions require `recover` with a new `{hypothesis}`. These are local recovery records, not automatic retries or an executor.
7. `evidence-add`: owner envelope + `{deliverable_id?,stage,file,attempt_id,content_sha256,target,observation?}`. Five ordered stages; previous validated before next report. Returns evidence ID/hash. Evidence snapshot remains in the one store; source-file hash must also remain current for completion.
8. `review`: `{root_id,deliverable_id?,stage,validator,attempt_id,content_sha256,target,result:"validated"|"rejected",reason,requirement_digest?,requirement_support?:[{requirement_id,evidence_id,result:"supported"|"unsupported"|"unknown",reason}],requirement_coverage?:{all_requested_clauses_covered:boolean,reason},observation?}`. Validator differs from producer, and an actual independent actor must inspect evidence. Use owner-bound `retry {root_id,owner_token,actor,deliverable_id?,reason,hypothesis?}` to create a fresh attempt for insufficient or rejected evidence without fabricating a changed intent or artifact. Two repeated failures require a new hypothesis. No implicit semantic reviewer is provided.
9. External destination/save/readback evidence and review also require `observation:{kind:stage,persisted:true,unique:true,failure:false,attribution:false,target,content_sha256,observed_at:ISO}`. Observation must be within 5 minutes. These are structured assertions backed by evidence and actual review, not an API fetch of the destination.
10. `correct`: owner envelope + `{source:"direct_user",intent,reason}` increments root intent and invalidates every affected root deliverable's attempt/support; unrelated roots unchanged. Update requirements and content before re-review.
11. `read` checks current artifact hashes, intent/attempt/content/build, all required support and the terminal attestation binding every validated stage. Never claim success from `checkpoint` or an accepted JSON write.

## Memory and issues

`memory-put`: `{source:"direct_user",id,zone:"PRIVATE"|"FAMILY_FRIENDS"|"WORK"|"SHARED",assignment,value,provenance,retention,source_path?,source_sha256?,supersedes_revision?}`. A supplied source path must be installation-relative, root-confined and a current regular file; its SHA-256 is recorded. Durable memory accepts durable-personal/durable-operating/project-state. Session records also accept action-audit-only/no-durable-delta; those classes cannot be promoted through memory-put. Reusing an ID in another assignment/zone is rejected. Changed facts require prior revision and retain history. `memory-list` requires `{zone,assignment,authorized_scope:true}`; cross-assignment access separately requires `cross_assignment_authorized:true,authorized_assignments:[...]`. These labels enforce declared scope consistency, not OS isolation between same-user processes. Memory remains in one private core store; Markdown zone/index records are the user's documentation, not automatic duplicate projections.

`session-record`: `{source:"direct_user",id,assignment,retention,summary,provenance,memory_ids:[]}` rejects cross-assignment bindings and conflicting IDs. It does not infer durable facts or run nightly model reconciliation. `issue-record`: `{id,title,severity,actor,symptoms,reproduction,root_cause,remediation}`; `issue-verify`: `{id,validator,result:"passed",file,reason}` requires independent label and evidence. `issue-list {}` reads current records. `issue-update {id,actor,status,next_action}` advances owner-managed investigation states; only independent issue-verify can mark verified. Use the core store for new issues. A retained old `00_CONTEXT/ISSUES/issues.json` is historical user data and is not automatically imported or used as a second active registry.

## Recovery, handoff and notifications

`tick` records last_tick, bounded heartbeat decisions and recovery-needed state for unverifiable or repeated no-progress roots. It never starts an app/worker. `orphans` distinguishes current/stale/unavailable monitoring and reports existing roots with missing/expired owners or recovery needed. `settings {source:"direct_user",time_zone:"UTC"}` selects the calendar timezone. Orphan histories count consecutive observed calendar days and explicitly retain missing-history flags; no tick means unknown counts. `recover-lock` only removes a lock older than 5 minutes whose recorded PID is dead; it refuses fresh/live locks.

`notification-configure {source:"direct_user",target}` opts into an exact target; null disables. Empty default creates no delivery. `queue-enqueue`/`outbox-enqueue`: `{source:"direct_user",id,root_id,target,payload}`; outbox additionally requires configured target and terminal root. Payload+root+target fingerprints suppress duplicates. `queue-list`/`outbox-list` reads.

`queue-claim`/`outbox-claim {id,actor}` returns a 5 minute token. `queue-transition`/`outbox-transition {id,target,payload_sha256,claim_token,state:"dispatched"|"uncertain"}` marks the action boundary before actual foreground action. `dispatched` is a recorded intent to act, never delivery proof. Expired dispatched work becomes uncertain and cannot be reclaimed automatically.

Independent reconciliation to `verified` supplies `{id,target,payload_sha256,state:"verified",validator,file,observed_at,unique:true,persisted:true,failure:false,attribution:false}`; reconciliation to pending instead requires `confirmed_no_action:true`. `queue-archive`/`outbox-archive {id}` requires verified state. No retries from uncertainty without independent destination readback.

## Compact context, proofs and legacy

`context {file,phase:"producer"|"validator"|"recovery",max_bytes?}` accepts explicit task file within installation. Opt-in markers `<!-- AUTOBOT_CONTEXT_CAPSULE_V1:producer -->` and closing `<!-- /AUTOBOT_CONTEXT_CAPSULE_V1:producer -->`; invalid/absent/oversize/not-smaller capsule returns full file. Does not automatically retrieve zone memory.

`proof-record` owner envelope + `{deliverable_id?,stage}` accepts validated research/draft only. `proof-check {root_id,deliverable_id?,stage}` rehashes original evidence, current intent/attempt/content and core build. It does not reuse external destination checks or automatically advance stages.

`legacy-import {}` reads exact v0.1 objective directories and validates stage order, copied evidence hashes and distinct producer/validator labels; existing old bytes remain audit-only. New runtime writes only core.json. Legacy historical completion remains explicitly marked; it is not a new current external readback. Legacy `objective-create`, `checkpoint`, `validate-stage`, `objective-status`, `supervisor-tick` command spellings remain. Status never implicitly migrates. Old CLI mutable commands import once and use legacy label/evidence semantics. New advanced roots must use the core API rather than the legacy bypass.

## Small local example

Create the artifact first, compute its SHA-256, then register the exact local file as the target. The values named `HASH`, `TOKEN`, `ATTEMPT` and `EVIDENCE` below are outputs from your installation, not literal identifiers to reuse. Keep JSON request files in your own private staging.

```sh
./runtime/bin/autoassist core root-create <<'JSON'
{"root_id":"local-note","title":"Verify a local note","intent":"Save and verify the requested note.","source":"direct_user","target":{"kind":"local","destination":"03_OUTPUTS/note.md"}}
JSON
./runtime/bin/autoassist core claim <<'JSON'
{"root_id":"local-note","actor":"writer"}
JSON
```

Use the returned token in owner operations; hash the actual UTF-8 artifact bytes with `shasum -a 256 03_OUTPUTS/note.md`, then submit `content` with that hash. Read the root to obtain its current attempt. Submit a concise requirement, then record and independently review each of the five stages in order. Each review needs the exact current digest and supporting evidence IDs for the clauses it verifies. A local filesystem note still needs persistence/readback evidence; those stages can point to a small independently generated readback record. The terminal read checks the real target bytes as well as the registered evidence.

Example requirement request shape:

```json
{"root_id":"local-note","owner_token":"TOKEN","actor":"writer","items":[{"id":"r1","summary":"The saved note contains the requested text.","target":"03_OUTPUTS/note.md"}]}
```

The distinct reviewer must actually inspect the saved output. Merely changing a label cannot establish independence. The commands preserve evidence and reject inconsistent bindings; they do not provide a model, reviewer, or native application interaction.
