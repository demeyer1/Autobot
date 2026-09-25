#!/usr/bin/env python3
"""Classify high-confidence Slack triage voice controls without echoing speech.

This helper is intentionally conservative. Natural-language draft feedback remains
semantic, while any command that could authorize a Slack mutation must match a
small phase-aware vocabulary.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from typing import Any


PHASES = {"triage", "draft", "paused"}
MAX_VOICE_UTTERANCE_CHARS = 10_000

GLOBAL_COMMANDS = {
    "repeat": "repeat",
    "repeat that": "repeat",
    "read that again": "repeat",
    "more context": "more_context",
    "give me more context": "more_context",
    "read the full message": "read_full_message",
    "full message": "read_full_message",
    "go back": "go_back",
    "previous": "go_back",
    "pause": "pause",
    "pause here": "pause",
    "status": "status",
    "give me a status": "status",
    "stop": "stop",
    "stop here": "stop",
}

TRIAGE_COMMANDS = {
    "leave unread": "leave_unread",
    "leave it unread": "leave_unread",
    "keep unread": "leave_unread",
    "keep it unread": "leave_unread",
    "skip": "leave_unread",
    "skip it": "leave_unread",
    "next": "leave_unread",
    "mark read": "mark_read",
    "mark it read": "mark_read",
    "mark red": "mark_read",
    "mark it red": "mark_read",
    "no reply": "mark_read",
    "reply": "draft_reply",
    "draft reply": "draft_reply",
    "draft a reply": "draft_reply",
    "respond": "draft_reply",
    "respond to it": "draft_reply",
}

DRAFT_DISPOSITION_COMMANDS = {
    "leave unread": "leave_unread",
    "leave it unread": "leave_unread",
    "keep it unread": "leave_unread",
    "mark read": "mark_read",
    "mark it read": "mark_read",
    "mark red": "mark_read",
    "mark it red": "mark_read",
    "no reply": "mark_read",
}

FINALIZE_ONLY = {
    "looks good",
    "that works",
    "approved",
    "final",
    "finalize it",
}

SEND_CURRENT = {
    "send it",
    "yes send it",
    "go ahead and send it",
    "looks good send it",
    "that works send it",
    "finalize and send it",
}

AMBIGUOUS_ACKNOWLEDGEMENTS = {
    "yes",
    "okay",
    "ok",
    "sounds good",
    "do it",
    "go ahead",
}


def normalize(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold()
    value = value.replace("_", " ")
    return " ".join(re.sub(r"[^\w]+", " ", value).split())


def result(action: str, phase: str, **extra: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "ok": True,
        "phase": phase,
        "action": action,
        "requires_clarification": action == "clarify",
    }
    payload.update(extra)
    return payload


def classify(
    utterance: str,
    phase: str,
    draft_version: int,
    draft_presented: bool,
) -> dict[str, Any]:
    phrase = normalize(utterance)
    if not phrase:
        return result("clarify", phase, reason="empty_or_unheard")

    if phase == "paused":
        if phrase in {"resume", "continue", "continue triage"}:
            return result("resume", phase)
        if phrase in GLOBAL_COMMANDS:
            return result(GLOBAL_COMMANDS[phrase], phase)
        return result("clarify", phase, reason="paused_requires_resume")

    if phrase in GLOBAL_COMMANDS:
        return result(GLOBAL_COMMANDS[phrase], phase)

    if phase == "triage":
        action = TRIAGE_COMMANDS.get(phrase)
        if action:
            return result(action, phase)
        return result("clarify", phase, reason="unrecognized_triage_command")

    if phrase in DRAFT_DISPOSITION_COMMANDS:
        return result(DRAFT_DISPOSITION_COMMANDS[phrase], phase)

    if phrase in FINALIZE_ONLY:
        return result("finalize_only", phase, draft_version=draft_version)

    version_match = re.fullmatch(r"send draft (\d+)", phrase)
    if version_match:
        requested_version = int(version_match.group(1))
        if requested_version != draft_version:
            return result(
                "clarify",
                phase,
                reason="draft_version_mismatch",
                requested_version=requested_version,
                active_version=draft_version,
            )
        phrase = "send it"

    if phrase in SEND_CURRENT:
        if draft_version < 1:
            return result("clarify", phase, reason="no_active_draft")
        if not draft_presented:
            return result("clarify", phase, reason="draft_not_fully_presented")
        return result(
            "send_current",
            phase,
            draft_version=draft_version,
            explicit_send=True,
        )

    if phrase in AMBIGUOUS_ACKNOWLEDGEMENTS:
        return result("clarify", phase, reason="acknowledgement_is_not_send_authority")

    return result("revise_draft", phase)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Classify one Slack triage voice transcript from standard input."
    )
    parser.add_argument("--phase", required=True, choices=sorted(PHASES))
    parser.add_argument("--draft-version", type=int, default=0)
    parser.add_argument("--draft-presented", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.draft_version < 0:
        print(json.dumps({"ok": False, "error": "draft version must be non-negative"}))
        return 2
    utterance = sys.stdin.read(MAX_VOICE_UTTERANCE_CHARS + 1)
    if len(utterance) > MAX_VOICE_UTTERANCE_CHARS:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": (
                        "voice utterance exceeds the "
                        f"{MAX_VOICE_UTTERANCE_CHARS}-character limit"
                    ),
                },
                sort_keys=True,
            )
        )
        return 2
    print(
        json.dumps(
            classify(
                utterance,
                args.phase,
                args.draft_version,
                args.draft_presented,
            ),
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
