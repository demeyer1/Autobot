// Volatile bridge between a durable decision result and the next spoken card.
// Pure JavaScript: safe to load once into the existing foreground CUA session.
// No app control, file/network I/O, message sends, or persistence.
var TriageCards = class TriageCards {
  constructor({scope, items, clock = () => Date.now()}) {
    if (typeof scope !== "string" || !scope || !Array.isArray(items) ||
        items.some(x => !x || typeof x.key !== "string" || !x.key ||
          typeof x.binding !== "string" || !x.binding) ||
        new Set(items.map(x => x.key)).size !== items.length) {
      throw new Error("A frozen scope and unique identity-bound items are required");
    }
    this.scope = scope;
    this.items = items.map(x => Object.freeze({key: x.key, binding: x.binding}));
    this.clock = clock;
    this.index = 0;
    this.capacity = 1;
    this.healthy = 0;
    this.paused = false;
    this.stopped = false;
    this.entries = new Map();
  }
  ticket(key) {
    const item = this.items.find(x => x.key === key);
    if (!item) throw new Error("Unknown snapshot key");
    return Object.freeze({scope: this.scope, ...item});
  }
  observeRead({elapsedMs, succeeded}) {
    if (!Number.isFinite(elapsedMs) || elapsedMs < 0 || typeof succeeded !== "boolean") {
      throw new Error("Actual read telemetry is required");
    }
    if (!succeeded) { this.healthy = 0; return; }
    if (elapsedMs >= 1500) { this.capacity = Math.min(3, this.capacity + 1); this.healthy = 0; }
    else if (++this.healthy >= 2) { this.capacity = Math.max(1, this.capacity - 1); this.healthy = 0; }
    while (this.entries.size > this.capacity) this.entries.delete([...this.entries.keys()].pop());
  }
  put(ticket, text, observedAt = this.clock()) {
    if (this.paused || this.stopped) throw new Error("Preview refill is paused");
    const itemIndex = this.items.findIndex(x => x.key === ticket?.key);
    const item = this.items[itemIndex];
    const now = this.clock();
    if (ticket?.scope !== this.scope || item?.binding !== ticket.binding ||
        itemIndex <= this.index || itemIndex > this.index + this.capacity) {
      throw new Error("Preview does not match an eligible successor");
    }
    if (typeof text !== "string" || !text || text.length > 40000 ||
        !Number.isFinite(observedAt) || observedAt > now || now - observedAt >= 90000) {
      throw new Error("Preview must be complete, bounded, and fresh");
    }
    this.expire();
    const bytes = new TextEncoder().encode(text).length;
    const total = [...this.entries.entries()].reduce((n, [key, value]) =>
      n + (key === ticket.key ? 0 : value.bytes), bytes);
    if (total > 160000 || (!this.entries.has(ticket.key) && this.entries.size >= this.capacity)) {
      throw new Error("Volatile preview limit reached");
    }
    this.entries.set(ticket.key, {text, bytes, observedAt, binding: ticket.binding});
  }
  expire() {
    const now = this.clock();
    for (const [key, entry] of this.entries) {
      const age = now - entry.observedAt;
      if (!Number.isFinite(age) || age < 0 || age >= 90000) this.entries.delete(key);
    }
  }
  applyResult(result) {
    if (result?.stopped === true || result?.run_state === "stopped") {
      this.stop();
      return {stopped: true, next_card: null, allow_ui_mutation: false};
    }
    if (this.paused || this.stopped) throw new Error("Answer the interruption before continuing triage");
    if (!result || result.ok === false || result.error) throw new Error("Decision was not recorded");
    const from = result.queued_key ?? result.decision_recorded ?? result.approved_key;
    const current = this.items[this.index]?.key;
    if (!from || from !== current) throw new Error("Stale, duplicate, or unbound decision result");
    const next = result.next_card !== undefined ? (result.next_card?.key ?? null) : result.next_key;
    if (next === from && result.choice === "reply") {
      return {drafting_key: from, next_card: null, present_before_mutation: true};
    }
    const expected = this.items[this.index + 1]?.key ?? null;
    if (next !== expected) throw new Error("Decision result changed the frozen order");
    this.index++;
    this.expire();
    const entry = next === null ? null : this.entries.get(next);
    this.entries.delete(next);
    const item = this.items[this.index];
    const card = entry && entry.binding === item.binding
      ? {key: next, text: entry.text, source: "cached_read_only"} : null;
    return {decision_recorded: from, next_key: next, next_card: card,
      present_before_mutation: true, prior_mutation_complete: false,
      ...(next !== null && !card ? {reason: "preview_unavailable"} : {})};
  }
  pause() { this.paused = true; return {allow_ui_mutation: false}; }
  resume() {
    if (this.stopped) throw new Error("A stopped run requires explicit durable resume and new cache");
    this.paused = false; this.expire();
  }
  stop() { this.paused = true; this.stopped = true; this.entries.clear(); }
};
if (typeof module !== "undefined" && module.exports) module.exports = {TriageCards};
