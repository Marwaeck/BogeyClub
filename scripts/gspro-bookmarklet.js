// Lesezeichen für das GSPro Web Portal (portal.gsprogolf.com → Analytics → Rounds).
// Die Seite hält alle geladenen Runden in window.allData. Das Lesezeichen speichert sie als gspro-JSON,
// die Bogey Club unter Statistik → Simulator einliest. Nichts wird an Bogey Club oder Dritte gesendet.
// Die Web-App (web/index.html) enthält dieselbe Logik verkleinert als GSPRO_BOOKMARKLET – bei Änderungen beide anpassen.
(() => {
  const d = window.allData;
  if (!/(^|\.)gsprogolf\.com$/.test(location.hostname) || !d || !Array.isArray(d.Rounds_Rounds)) {
    alert("Bogey Club: Bitte zuerst im GSPro Web Portal Analytics → Rounds öffnen und warten, bis die Runden geladen sind.");
    return;
  }
  const opt = document.querySelector("#playerDD option:checked");
  const out = {
    format: "gspro-export", version: 1, exportedAt: new Date().toISOString(),
    player: opt ? opt.textContent.trim() : "", units: d.Units || null,
    rounds: d.Rounds_Rounds, scores: d.RoundScores || [], scorecards: d.RoundScorecards || [], strokesGained: d.RoundStrokesGained || []
  };
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([JSON.stringify(out)], { type: "application/json" }));
  a.download = "gspro-" + new Date().toISOString().slice(0, 10) + ".json";
  document.body.appendChild(a); a.click(); a.remove();
})();
