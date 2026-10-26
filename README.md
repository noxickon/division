# Division 2 Codex

Gear-Sets, Brand-Sets, Named Items, Exotics und Schadensformeln von The Division 2 – direkt aus den Spieldateien, auf Deutsch und Englisch, mit PvE/PvP-Umschalter. Läuft über GitHub Pages (`index.html`).

## Aktualisieren nach einem Patch

Kurzfassung (ausführlich in [docs/datamining.md](docs/datamining.md)):

1. Spiel schließen, mit [Hunter](https://dtzxporter.com/tools/hunter) die Raw Files nach `Downloads\exported_files` exportieren.
2. `powershell -NoProfile -ExecutionPolicy Bypass -File tools\extract.ps1`
3. `powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1`
4. Ansehen: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\serve.ps1` → http://localhost:8080
5. Committen und pushen.

## Aufbau

| Pfad | Inhalt |
| --- | --- |
| `template.html` | Seite (HTML, CSS, JS); `build.ps1` setzt die Daten ein |
| `index.html` | gebaute Seite für GitHub Pages |
| `data/*.json` | aus den Spieldateien extrahiert (nicht von Hand bearbeiten) |
| `data/community/` | alte Community-Daten: „seit wann“, Bezugsquellen, Attribut-Höchstwerte |
| `tools/` | `extract.ps1`, `juice.ps1`, `build.ps1`, `serve.ps1` (nur PowerShell, kein Node/Python nötig) |
| `docs/datamining.md` | Doku: Formeln, Update-Anleitung, wo was in den Spieldaten liegt |
