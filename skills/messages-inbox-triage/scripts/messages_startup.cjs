// Messages-only startup adapter. No app/network access or persistence.
// Load after foreground_cards.cjs in a persistent foreground session, or require
// this module in a local code runtime. Never initialize it for a status question.
var MessagesCardsBase = typeof TriageCards !== "undefined" ? TriageCards :
  require('./foreground_cards.cjs').TriageCards;
var messagesIdentityFields = ['key', 'service', 'kind', 'participant_count',
  'thread_sha256', 'participants_sha256', 'unread_sha256'];
var messagesIdentity = function(item) {
  if (!item || typeof item.key !== 'string' || !item.key) throw new Error('An opaque key is required');
  if (item.materialized === false) return {key: item.key, materialized: false};
  if (messagesIdentityFields.some(field => item[field] === undefined)) {
    throw new Error('Use materialized:false until exact identity is exposed');
  }
  return Object.fromEntries(messagesIdentityFields.map(field => [field, item[field]]));
};
var messagesBinding = item => JSON.stringify(messagesIdentity(item));
var messagesCompleteCard = item => item?.card?.complete === true &&
  typeof item.card.text === 'string' && item.card.text.length > 0;

// Cooperative event guard, not a timer or a monitor of unreported tool calls.
// Holds only an opaque key; presentation is acknowledged by the foreground owner.
var MessagesGuardedCards = class extends MessagesCardsBase {
  applyResult(result) {
    const handoff = super.applyResult(result);
    this.awaitingPresentation = handoff.next_card?.key ?? null;
    return {...handoff, execution_guard: this.awaitingPresentation
      ? {next_step: 'present_card', key: this.awaitingPresentation}
      : {next_step: 'continue'}};
  }
  presented(key) {
    if (!key || key !== this.awaitingPresentation) throw new Error('Presentation key mismatch');
    this.awaitingPresentation = null;
  }
  beforeStep(step) {
    if (this.paused || this.stopped) return {proceed: false, reason: 'paused_or_stopped'};
    if (this.awaitingPresentation && !['present_card', 'safety_recovery'].includes(step)) {
      return {proceed: false, reason: 'present_cached_card_first', key: this.awaitingPresentation};
    }
    return {proceed: true};
  }
  stop() { super.stop(); this.awaitingPresentation = null; }
};

// Call after a real shallow sidebar read, not after opening successor threads.
// observedAt is the original read time; reusing a seed never renews its expiry.
var refillMessagesCards = function(cards, {scope, items = [], observedAt, read}) {
  if (cards.paused || cards.stopped) throw new Error('Answer the interruption before refilling previews');
  if (scope !== cards.scope) throw new Error('Sidebar scope does not match the frozen run');
  if (!Array.isArray(items) || new Set(items.map(item => item?.key)).size !== items.length) {
    throw new Error('Sidebar keys must be unique');
  }
  if (read !== undefined && (!Number.isFinite(read.elapsedMs) || read.elapsedMs < 0 ||
      typeof read.succeeded !== 'boolean')) throw new Error('Actual read telemetry is required');
  cards.expire();
  if (read?.succeeded === false) return {cached: cards.entries.size, reason: 'read_unavailable'};
  const now = cards.clock();
  if (!Number.isFinite(observedAt) || observedAt > now || now - observedAt >= 90000) {
    return {cached: cards.entries.size, reason: 'preview_expired'};
  }
  const end = Math.min(cards.items.length, cards.index + cards.capacity + 1);
  for (let index = cards.index + 1; index < end; index++) {
    const frozen = cards.items[index];
    const item = items.find(row => row.key === frozen.key);
    if (!item) continue;
    if (messagesBinding(item) !== frozen.binding) {
      cards.entries.delete(item.key);
      throw new Error('Sidebar identity changed; reacquire the frozen item');
    }
    if (messagesCompleteCard(item)) cards.put(cards.ticket(item.key), item.card.text, observedAt);
    else cards.entries.delete(item.key);
  }
  return {cached: cards.entries.size};
};

// items is the frozen visible-order inventory plus ONLY the first safe card and
// up to three safe successors. Other rows are body-free provisional items.
// Present the first sidebar card before calling this adapter. Bootstrap output
// acknowledges that same card; it must not cause a second presentation.
var prepareMessagesRun = function({scope, items, observedAt, read, clock = () => Date.now()}) {
  if (!Array.isArray(items) || !messagesCompleteCard(items[0])) {
    throw new Error('The first sidebar card must be complete and safe to present');
  }
  const cards = new MessagesGuardedCards({scope, clock,
    items: items.map(item => ({key: item.key, binding: messagesBinding(item)}))});
  // Keep all safe successors already observed. Adaptive shrinking discarded the
  // second ready card before a fast second decision could consume it.
  cards.capacity = 3;
  refillMessagesCards(cards, {scope, items, observedAt, read});
  const firstText = items[0].card.text;
  const bootstrap = {session_id: scope, preview_window_size: 4,
    snapshot_at: new Date(observedAt).toISOString(), items: items.map((item, index) => {
    const identity = messagesIdentity(item);
    const text = index === 0 ? firstText : cards.entries.get(item.key)?.text;
    return text === undefined ? identity : {...identity, card: {text}};
  })};
  if (read !== undefined) {
    bootstrap.recent_latency_ms = Math.round(read.elapsedMs);
    bootstrap.recent_failures = read.succeeded ? 0 : 1;
  }
  return {cards, bootstrap};
};
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {prepareMessagesRun, refillMessagesCards};
}
