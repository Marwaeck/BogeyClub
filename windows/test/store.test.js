// Tests für die Datenablage der Windows-App: node --test test/
const { test } = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs"), os = require("node:os"), path = require("node:path");
const { Store } = require("../store");

test("Dokumente speichern, löschen und wieder laden", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "bogey-"));
  const s = new Store(dir);
  s.set("players", "abc123", JSON.stringify({ name: "Marcel", hcp: 18.4, hidden: false }));
  s.set("rounds", "r1", JSON.stringify({ date: "2026-11-15", entries: [] }));
  s.delete("rounds", "r1");
  assert.throws(() => s.set("players", "../x", "{}"));
  const again = new Store(dir);
  assert.deepStrictEqual(JSON.parse(again.allJSON()).players.abc123, { name: "Marcel", hcp: 18.4, hidden: false });
  assert.deepStrictEqual(JSON.parse(again.allJSON()).rounds, {});
  fs.rmSync(dir, { recursive: true, force: true });
});

test("Bilder ablegen und entfernen", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "bogey-"));
  const s = new Store(dir);
  const id = s.addPhoto(Buffer.from([0xff, 0xd8, 0xff]), "image/jpeg");
  assert.strictEqual(s.photo(id).type, "image/jpeg");
  s.deletePhoto(id);
  assert.strictEqual(s.photo(id), null);
  assert.strictEqual(s.photo("../daten"), null);
  assert.throws(() => s.addPhoto(Buffer.from("x"), "text/plain"));
  fs.rmSync(dir, { recursive: true, force: true });
});
