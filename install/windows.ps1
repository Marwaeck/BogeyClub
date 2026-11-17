# Bogey Club für Windows installieren oder aktualisieren – ein Befehl in PowerShell:
#   irm https://raw.githubusercontent.com/Marwaeck/BogeyClub/main/install/windows.ps1 | iex
# Lädt die neueste Windows-Version von GitHub (Releases) nach %LOCALAPPDATA%\Programs\Bogey Club,
# legt Verknüpfungen im Startmenü und auf dem Desktop an und startet die App.
# Deine Daten (%APPDATA%\Bogey Club) bleiben unberührt. Keine Administratorrechte nötig.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # schnellerer Download
$repo = 'Marwaeck/BogeyClub'
$dest = Join-Path $env:LOCALAPPDATA 'Programs\Bogey Club'
$exe = Join-Path $dest 'Bogey Club.exe'

function Say($t) { Write-Host "→ $t" }

try {
  Say 'Suche die neueste Version auf GitHub …'
  try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'BogeyClub-Installer'; 'Accept' = 'application/vnd.github+json' }
  } catch { throw 'Noch keine Version veröffentlicht oder keine Verbindung zu GitHub.' }
  $asset = $release.assets | Where-Object { $_.name -like 'Bogey-Club-windows-*.zip' } | Select-Object -First 1
  if (-not $asset) { throw 'In der neuesten Version fehlt die Windows-Datei (Bogey-Club-windows-….zip).' }
  $version = $release.tag_name -replace '^[vV]', ''

  $work = Join-Path $env:TEMP ('bogeyclub-' + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $work | Out-Null
  $zip = Join-Path $work $asset.name
  Say "Lade $($asset.name) ($([math]::Round($asset.size / 1MB)) MB) …"
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing

  Say 'Entpacke …'
  $unpacked = Join-Path $work 'neu'
  Expand-Archive -Path $zip -DestinationPath $unpacked -Force
  if (-not (Test-Path (Join-Path $unpacked 'Bogey Club.exe'))) { throw 'Die ZIP enthält keine „Bogey Club.exe“.' }

  $running = Get-Process -Name 'Bogey Club' -ErrorAction SilentlyContinue
  if ($running) { Say 'Beende die laufende App …'; $running | Stop-Process -Force; Start-Sleep -Seconds 2 }

  Say "Installiere Bogey Club $version nach $dest …"
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  Copy-Item -Path (Join-Path $unpacked '*') -Destination $dest -Recurse -Force
  Get-ChildItem -Path $dest -Recurse | Unblock-File   # Herkunft „Internet“ entfernen

  $shell = New-Object -ComObject WScript.Shell
  foreach ($dir in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
    $link = $shell.CreateShortcut((Join-Path $dir 'Bogey Club.lnk'))
    $link.TargetPath = $exe
    $link.WorkingDirectory = $dest
    $link.IconLocation = "$exe,0"
    $link.Description = 'Bogey Club – privates Golf-Scorebuch'
    $link.Save()
  }

  # .bogey-Dateien mit Bogey Club verknüpfen (nur für diesen Benutzer, ohne Admin-Rechte)
  $classes = 'HKCU:\Software\Classes'
  New-Item -Path "$classes\.bogey" -Force | Out-Null
  Set-ItemProperty -Path "$classes\.bogey" -Name '(Default)' -Value 'BogeyClub.Datei'
  Set-ItemProperty -Path "$classes\.bogey" -Name 'Content Type' -Value 'application/vnd.bogeyclub'
  New-Item -Path "$classes\BogeyClub.Datei\DefaultIcon" -Force | Out-Null
  New-Item -Path "$classes\BogeyClub.Datei\shell\open\command" -Force | Out-Null
  Set-ItemProperty -Path "$classes\BogeyClub.Datei" -Name '(Default)' -Value 'Bogey-Club-Datei'
  Set-ItemProperty -Path "$classes\BogeyClub.Datei\DefaultIcon" -Name '(Default)' -Value "`"$exe`",0"
  Set-ItemProperty -Path "$classes\BogeyClub.Datei\shell\open\command" -Name '(Default)' -Value "`"$exe`" `"%1`""

  Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
  Start-Process -FilePath $exe
  Write-Host "✓ Bogey Club $version ist installiert (Startmenü und Desktop)." -ForegroundColor Green
} catch {
  Write-Host "✗ $_" -ForegroundColor Red
}
