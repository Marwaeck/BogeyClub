// Baut die Windows-App: windows/dist/Bogey-Club-windows-<Version>.zip (darin „Bogey Club.exe“).
// Die Versionsnummer kommt aus package.json im Projektordner – eine Nummer für Mac und Windows.
// Aufruf: npm run dist (in windows/) oder npm run windows (im Projektordner).
// Mit „--installer“ entsteht zusätzlich ein Installationsprogramm (nur unter Windows oder auf Intel-Macs möglich).
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const { build, Platform, Arch } = require("electron-builder");

const root = path.join(__dirname, "..");
const version = require(path.join(root, "package.json")).version;
const config = require("./package.json").build;

execFileSync(process.execPath, [path.join(root, "mac", "prepare-web.mjs"), "--target", "windows"], { stdio: "inherit" });

const targets = ["zip"].concat(process.argv.includes("--installer") ? ["nsis"] : []);
build({
  targets: Platform.WINDOWS.createTarget(targets, Arch.x64),
  config: {
    ...config,
    extraMetadata: { version },
    // Lizenz und Lizenzen der Bausteine: in der App (Hilfe-Menü) und neben der .exe
    extraResources: [
      { from: "../LICENSE", to: "Lizenzen/LICENSE.txt" },
      { from: "../THIRD-PARTY-NOTICES.md", to: "Lizenzen/Drittanbieter.txt" },
      { from: "../licenses", to: "Lizenzen", filter: ["*.txt"] }
    ],
    extraFiles: [{ from: "../LICENSE", to: "LICENSE.txt" }],
    win: { ...config.win, artifactName: "Bogey-Club-windows-${version}.${ext}" },
    nsis: { ...config.nsis, license: "../LICENSE" }
  }
}).then(files => {
  console.log(`Fertig (Version ${version}):\n` + files.filter(f => /\.(zip|exe)$/.test(f)).map(f => "  " + path.relative(root, f)).join("\n"));
}).catch(e => { console.error(e); process.exit(1); });
