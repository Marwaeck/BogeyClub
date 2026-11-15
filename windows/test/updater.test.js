// Tests für den Updater der Windows-App: node --test test/
const { test } = require("node:test");
const assert = require("node:assert");
const { parseRelease, isNewer, installScript } = require("../updater");

test("Versionen vergleichen", () => {
  assert.ok(isNewer("1.0.1", "1.0.0"));
  assert.ok(isNewer("1.10", "1.9.9"));
  assert.ok(isNewer("2.0.0", "1.99"));
  assert.ok(!isNewer("1.0", "1.0.0"));
  assert.ok(!isNewer("1.0.0-beta", "1.0.0"));
  assert.ok(!isNewer("0.9", "1.0.0"));
});

test("Release von GitHub auswerten", () => {
  const r = parseRelease({
    tag_name: "v1.2.0", html_url: "https://github.com/Marwaeck/BogeyClub/releases/tag/v1.2.0", body: "- Neu: Updater\n",
    assets: [
      { name: "Bogey-Club-mac-1.2.0.zip", browser_download_url: "https://example.org/m.zip", size: 20 },
      { name: "Bogey-Club-windows-1.2.0.zip", browser_download_url: "https://example.org/w.zip", size: 10 }
    ]
  });
  assert.deepStrictEqual(r, { version: "1.2.0", notes: "- Neu: Updater", pageURL: "https://github.com/Marwaeck/BogeyClub/releases/tag/v1.2.0", assetURL: "https://example.org/w.zip", assetSize: 10 });
  assert.strictEqual(parseRelease({ tag_name: "1.3", html_url: "https://x.y/", assets: [] }).assetURL, null);
  assert.throws(() => parseRelease([]));
});

test("Installations-Skript", () => {
  const s = installScript({ pid: 4242, source: "C:\\Temp\\neu", target: "C:\\Spiele\\Bogey Club" });
  assert.match(s, /tasklist \/FI "PID eq 4242"/);
  assert.match(s, /robocopy "%SRC%" "%DST%" \/E /);
  assert.match(s, /start "" "%DST%\\Bogey Club\.exe"/);
  assert.ok(!/\/MIR/.test(s), "darf keine fremden Dateien im App-Ordner löschen");
  assert.ok(s.includes("\r\n"), "Windows-Zeilenenden");
  assert.ok(!installScript({ pid: 1, source: 'a"b', target: "c" }).includes('a"b'), "Anführungszeichen werden entfernt");
});
