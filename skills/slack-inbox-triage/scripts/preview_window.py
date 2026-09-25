"""Small volatile read-only Slack preview window. No I/O or persistence.

Hold one instance in the foreground read session. Call targets() to choose
read-only fetches, put() with their captured identity ticket, and take_current()
when a queued decision advances the visible card. This cache never authorizes
a mutation or replaces fresh first-party rendered evidence.
"""

from __future__ import annotations

import math
import time
from collections import OrderedDict
from typing import Callable

from triage_state import MAX_DRAFT_CHARS, StateError, card_payload, validate_state


class PreviewWindow:
    MAX_ITEMS = 3
    TTL_SECONDS = 90
    MAX_BYTES = 160_000

    def __init__(self, *, clock: Callable[[], float] = time.monotonic):
        self._clock = clock
        self.capacity = 1
        self._healthy_reads = 0
        self._scope = None
        self._entries = OrderedDict()

    def clear(self):
        self._entries.clear()
        self._scope = None
        self.capacity = 1
        self._healthy_reads = 0

    def observe_read(self, *, elapsed_ms: int, succeeded: bool):
        """Grow after slow successful reads; shrink after two healthy reads.

        Outages do not schedule retries or increase fetch pressure. Valid cached
        entries survive until their TTL or scope changes.
        """
        if type(elapsed_ms) is not int or elapsed_ms < 0 or type(succeeded) is not bool:
            raise StateError("preview telemetry requires nonnegative integer latency and a boolean outcome")
        if not succeeded:
            self._healthy_reads = 0
            return
        if elapsed_ms >= 1500:
            self.capacity = min(self.MAX_ITEMS, self.capacity + 1)
            self._healthy_reads = 0
        else:
            self._healthy_reads += 1
            if self._healthy_reads >= 2:
                self.capacity = max(1, self.capacity - 1)
                self._healthy_reads = 0
        while len(self._entries) > self.capacity:
            self._entries.popitem(last=True)

    @staticmethod
    def _identity(data, item):
        account = data["decision_lane"]["workspace_accounts"][item["workspace"]]
        return (data["run_id"], data["session_id"], data["session_generation"],
                item["workspace"], account, item["conversation"], item["key"],
                item["message_ts"], item["thread_key"], item["surface"],
                item["original_unread_boundary_ts"])

    def _sync(self, data):
        try:
            validate_state(data)
        except (StateError, KeyError, TypeError):
            self.clear()
            raise
        lane = data.get("decision_lane")
        if lane is None or data["run_state"] != "active":
            self.clear()
            return []
        scope = (data["run_id"], data["session_id"], data["session_generation"],
                 data["snapshot_at"], tuple(sorted(lane["workspace_accounts"].items())))
        if self._scope is not None and scope != self._scope:
            self.clear()
        self._scope = scope
        order = data["messages"]
        start = len(lane["submitted_keys"])
        # Include a former successor that has just become the current card.
        eligible = order[start:start + self.capacity + 1]
        identities = {m["key"]: self._identity(data, m) for m in eligible}
        now = self._clock()
        for key, entry in list(self._entries.items()):
            age = now - entry["at"]
            if (not math.isfinite(age) or age < 0 or age >= self.TTL_SECONDS
                    or identities.get(key) != entry["identity"]):
                del self._entries[key]
        return eligible

    def targets(self, data):
        """Return identity-bound successor tickets; fetching remains read-only."""
        eligible = self._sync(data)
        available = self.capacity - len(self._entries)
        return [dict(card=card_payload(item), identity=self._identity(data, item))
                for item in eligible[1:] if item["key"] not in self._entries][:available]

    def put(self, data, *, ticket, text: str):
        eligible = self._sync(data)
        if (not isinstance(ticket, dict) or set(ticket) != {"card", "identity"}
                or not isinstance(ticket["card"], dict)):
            raise StateError("preview requires a captured identity ticket")
        key = ticket["card"].get("key")
        match = next((item for item in eligible[1:] if item["key"] == key), None)
        if match is None or tuple(ticket["identity"]) != self._identity(data, match):
            raise StateError("preview no longer matches an eligible successor identity")
        if not isinstance(text, str) or not text or len(text) > MAX_DRAFT_CHARS:
            raise StateError("preview must be nonempty and bounded; never cache a truncated card")
        size = len(text.encode("utf-8"))
        existing_size = sum(e["bytes"] for k, e in self._entries.items() if k != key)
        if size + existing_size > self.MAX_BYTES:
            raise StateError("preview window byte limit exceeded")
        if key not in self._entries and len(self._entries) >= self.capacity:
            raise StateError("preview window is full; do not fetch additional bodies")
        self._entries[key] = {"identity": self._identity(data, match), "text": text,
                              "bytes": size, "at": self._clock()}

    def take_current(self, data):
        eligible = self._sync(data)
        if not eligible:
            return None
        entry = self._entries.pop(eligible[0]["key"], None)
        if entry is None:
            return None
        return {"card": card_payload(eligible[0]), "text": entry["text"],
                "age_seconds": self._clock() - entry["at"], "source": "cached_read_only"}
