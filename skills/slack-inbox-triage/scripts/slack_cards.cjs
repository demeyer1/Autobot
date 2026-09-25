// Slack-only foreground adapter. No timers, app/network access or persistence.
// Load after foreground_cards.cjs, once in the existing foreground runtime.
var SlackCardsBase = typeof TriageCards !== 'undefined' ? TriageCards :
  require('./foreground_cards.cjs').TriageCards;
var SlackCards = class extends SlackCardsBase {
  constructor(options) { super(options); this.capacity = 3; this.awaitingPresentation = null; }
  observeRead(read) {
    if (!Number.isFinite(read?.elapsedMs) || read.elapsedMs < 0 ||
        typeof read.succeeded !== 'boolean') throw new Error('Actual read telemetry is required');
    // Keep already-observed safe previews, even after fast reads or an outage.
    this.expire();
  }
  applyResult(result) {
    if (this.awaitingPresentation && result?.stopped !== true && result?.run_state !== 'stopped') {
      throw new Error('Present the pending card before another decision');
    }
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
if (typeof module !== 'undefined' && module.exports) module.exports = {SlackCards};
