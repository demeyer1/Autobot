(() => {
  const sourceFromQuery = new URLSearchParams(location.search).get("utm_source") || "";
  const allowed = new Set(["chatgpt.com", "perplexity.ai"]);
  let source = allowed.has(sourceFromQuery) ? sourceFromQuery : "";
  if (!source && document.referrer) {
    try {
      const host = new URL(document.referrer).hostname.toLowerCase().replace(/^www\./, "");
      if (host === "chatgpt.com" || host.endsWith(".chatgpt.com")) source = "chatgpt.com";
      if (host === "perplexity.ai" || host.endsWith(".perplexity.ai")) source = "perplexity.ai";
    } catch {}
  }
  if (!source) return;
  const page = location.pathname.replace(/^\/Autobot/, "") || "/";
  const pixel = new Image(1, 1);
  pixel.referrerPolicy = "no-referrer";
  pixel.alt = "";
  pixel.src = "https://autobot-harness.goatcounter.com/count?p=" +
    encodeURIComponent("/referral/" + source + page) +
    "&r=" + encodeURIComponent(source) + "&e=1&rnd=" + Date.now();
})();
