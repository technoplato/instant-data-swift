const tbody = document.getElementById("tbody");
const logEl = document.getElementById("log");
const statusEl = document.getElementById("status");
const rows = [];
const maxRows = 80;
let windowStart = Date.now();
let windowCount = 0;

document.getElementById("start").onclick = async () => {
  statusEl.textContent = "starting…";
  await window.exerciseGem.start();
  statusEl.textContent = "running";
};

document.getElementById("stop").onclick = async () => {
  await window.exerciseGem.stop();
  statusEl.textContent = "stopped";
};

window.exerciseGem.onEvent((ev) => {
  if (ev.type === "write") {
    windowCount += 1;
    const now = Date.now();
    if (now - windowStart >= 1000) {
      document.getElementById("ops").textContent = String(windowCount);
      windowCount = 0;
      windowStart = now;
    }
    document.getElementById("p50").textContent =
      ev.rttMs != null ? Number(ev.rttMs).toFixed(1) : "—";
    if (ev.appRssMiB != null) {
      document.getElementById("rss").textContent = Number(ev.appRssMiB).toFixed(1);
    }
    document.getElementById("seq").textContent = String(ev.seq ?? 0);
    rows.unshift(ev);
    if (rows.length > maxRows) rows.pop();
    tbody.innerHTML = rows
      .map(
        (r) =>
          `<tr>
            <td>${r.seq ?? ""}</td>
            <td>${r.rttMs != null ? Number(r.rttMs).toFixed(1) : ""}</td>
            <td>${escapeHtml(short(r.clientId))}</td>
            <td>${escapeHtml(r.descriptor ?? "")}</td>
            <td>${escapeHtml(short(r.entityId))}</td>
          </tr>`,
      )
      .join("");
  } else if (ev.type === "log") {
    logEl.textContent += String(ev.message ?? "") + "\n";
  } else if (ev.type === "metrics") {
    if (ev.observedPerSecond != null) {
      document.getElementById("ops").textContent = Number(ev.observedPerSecond).toFixed(1);
    }
    if (ev.rttP50Ms != null) {
      document.getElementById("p50").textContent = Number(ev.rttP50Ms).toFixed(1);
    }
    if (ev.appRssMiB != null) {
      document.getElementById("rss").textContent = Number(ev.appRssMiB).toFixed(1);
    }
  } else if (ev.type === "worker-exit") {
    statusEl.textContent = `worker exited (${ev.code})`;
  }
});

function short(s) {
  if (!s) return "";
  return s.length > 12 ? s.slice(0, 8) + "…" : s;
}

function escapeHtml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
