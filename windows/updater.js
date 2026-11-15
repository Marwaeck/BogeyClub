// Updater der Windows-App – Auswertung ohne Netzwerk (testbar), gleiche Regeln wie die Mac-App
// (mac/Sources/BogeyCore/UpdateCheck.swift): neueste Version aus den GitHub-Releases von Marwaeck/BogeyClub,
// Tag „v1.2.3“, ZIP-Datei „Bogey-Club-windows-<Version>.zip“.
const REPOSITORY = "Marwaeck/BogeyClub";
const LATEST_URL = `https://api.github.com/repos/${REPOSITORY}/releases/latest`;
const RELEASES_PAGE = `https://github.com/${REPOSITORY}/releases`;
const ASSET_PREFIX = "Bogey-Club-windows-";

function parseRelease(json, prefix = ASSET_PREFIX) {
  const o = typeof json === "string" ? JSON.parse(json) : json;
  if (!o || typeof o.tag_name !== "string" || typeof o.html_url !== "string") throw new Error("bad_data");
  const asset = (o.assets || []).find(a => typeof a?.name === "string" && a.name.startsWith(prefix) && a.name.toLowerCase().endsWith(".zip"));
  return {
    version: o.tag_name.replace(/^[vV]/, ""),
    notes: String(o.body || "").trim(),
    pageURL: o.html_url,
    assetURL: asset?.browser_download_url || null,
    assetSize: asset?.size || 0
  };
}

/** Versionen zahlenweise vergleichen (fehlende Stellen = 0, Zusätze nach „-“ ignoriert). */
function isNewer(candidate, current) {
  const parts = v => String(v).split("-")[0].split(".").map(x => parseInt(x, 10) || 0);
  const a = parts(candidate), b = parts(current);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = a[i] || 0, y = b[i] || 0;
    if (x !== y) return x > y;
  }
  return false;
}

/**
 * Batch-Skript, das nach dem Beenden der App die neuen Dateien über den App-Ordner kopiert und
 * Bogey Club wieder startet. Daten liegen in %APPDATA% und sind davon nicht betroffen.
 * Klappt das Kopieren nicht (z. B. Ordner schreibgeschützt), startet die alte Version und die Download-Seite.
 */
function installScript({ pid, source, target, exe = "Bogey Club.exe", page = RELEASES_PAGE }) {
  const q = s => String(s).replace(/"/g, "");
  return [
    "@echo off",
    "chcp 65001 >nul",
    `set "SRC=${q(source)}"`,
    `set "DST=${q(target)}"`,
    ":wait",
    `tasklist /FI "PID eq ${Number(pid)}" 2>nul | find "${Number(pid)}" >nul`,
    "if not errorlevel 1 ( timeout /t 1 /nobreak >nul & goto wait )",
    'robocopy "%SRC%" "%DST%" /E /R:5 /W:1 /NFL /NDL /NJH /NJS /NP >nul',
    `if errorlevel 8 ( start "" "%DST%\\${q(exe)}" & start "" "${q(page)}" & goto end )`,
    `start "" "%DST%\\${q(exe)}"`,
    ":end",
    'rmdir /s /q "%SRC%"',
    ""
  ].join("\r\n");
}

module.exports = { REPOSITORY, LATEST_URL, RELEASES_PAGE, ASSET_PREFIX, parseRelease, isNewer, installScript };
