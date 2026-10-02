# AutoBot vs OpenAI Dots

AutoBot and OpenAI Dots solve different parts of persistent agent work.

AutoBot is a local agent harness for a ChatGPT or Codex Project on the user’s Mac. Its operating contract, memory, privacy zones, objective state and completion evidence are ordinary files the user can inspect and edit.

OpenAI Dots are persistent assistants that work from their own cloud computer. A dot can create a new local Codex task or continue an existing local Codex task on a connected computer. The local computer connection and the Codex connection are separate controls.

## Product boundary

| Dimension | AutoBot | OpenAI Dots |
| --- | --- | --- |
| Primary runtime | A local ChatGPT or Codex Project on the user’s Mac | A cloud computer operated by OpenAI |
| Memory | Readable and editable Project files with relationship and purpose zones | Dot memory and task context managed by ChatGPT |
| Local task handoff | The user starts or continues work in the local Project | A dot can create or continue a local Codex task after the computer and Codex are connected |
| Completion | Ordered evidence stages, a validator label separate from the producer, and destination readback for external work | The dot can inspect and steer delegated tasks; the cited documentation does not describe AutoBot’s validator contract |
| Privacy boundary | Procedures and owner-only files within one macOS account | Cloud service controls plus any separately authorized local-computer access |
| Benchmarks | Published AssistantBench and OSWorld 2.0 results with evidence and verifiers | No directly comparable harness benchmark in the cited Dots documentation |

## Current Dots availability

OpenAI currently lists Dots for:

- Pro 100, Pro 200 and Pro 500 users over 18 outside the EEA, UK and Switzerland.
- Business Premium users worldwide, subject to gradual rollout.
- Enterprise users worldwide, subject to gradual rollout and administrator enablement.

Eligible accounts may still lack Dots while the rollout continues. Dot conversations do not count against ChatGPT usage, while delegated Work and Codex tasks use those products’ limits.

Sources: [Meet dots](https://learn.chatgpt.com/docs/dots), [Tasks and memory](https://learn.chatgpt.com/docs/dots/tasks-and-memory), [Computers and apps](https://learn.chatgpt.com/docs/dots/computers-and-apps).

## AutoBot compatibility status

AutoBot has not yet published a completed Dot-to-local-Codex canary. This page does not claim “Works with OpenAI Dots” or provide a setup guide.

The acceptance test will require a current Dots-capable ChatGPT desktop app, an eligible account with Dots enabled, a connected Mac, and a local AutoBot Project. It will verify that the delegated Codex task applies the Project’s `AGENTS.md`, advances the five completion stages in order, rejects same-label validation, and reads only the assigned test privacy zone. Any future compatibility claim should name the tested app version and date.

AutoBot’s privacy zones and validator separation are procedural controls within a local Project. They are not OS isolation, an OpenAI certification, or proof that every Dot handoff will behave the same way.
