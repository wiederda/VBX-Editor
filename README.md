# VBX Editor

Ein leichtgewichtiger Editor für VBX-Skripte (`.vb`) für Windows, gebaut mit Flutter.

## Features

### Editor
- **Mehrere Tabs** – gleichzeitiges Bearbeiten mehrerer Dateien, mit Änderungsmarkierung (`*`) und Speicherabfrage (Ja/Nein/Abbrechen) beim Schließen
- **Zeilennummern** – synchron mitscrollende Gutter-Anzeige links im Editor
- **Zeile/Spalte live** – Anzeige in der Statusleiste, aktualisiert sich mit der Cursorposition
- **Syntax-Highlighting** – konfigurierbar über `assets/vbx.json`, mit separaten Farbschemata für Dark- und Light-Theme
- **Live-Syntax-Hinweise** – zeigt beim Tippen automatisch Signatur und Beschreibung der aktuellen Modul-/globalen Funktion an
- **Autovervollständigung** – bei `modul.` erscheint ein Popup mit passenden Funktionen (Pfeiltasten/Enter/Tab/Escape, oder Mausklick)
- **Auto-Einrückung** – berücksichtigt verschachtelte `If`/`For`/`While`/`Do`/`Sub`/`Function`/`Select Case`; fügt beim Anlegen eines neuen Blocks automatisch den passenden Abschluss ein; formatiert `.vb`-Dateien zusätzlich beim Speichern komplett neu ein
- **Kommentar umschalten** – markierte Zeilen per Klick aus-/einkommentieren
- **Suche im Editor** – Vorwärts-/Rückwärtssuche mit Hervorhebung aller Treffer (aktueller Treffer stärker markiert)
- **Drag & Drop** – Dateien direkt in den Editor-Bereich ziehen zum Öffnen
- **Standard-Vorlage** – neue Tabs starten mit Kommentar-Hinweisen zu `#use`/`#requires`/`include`

### Ausführen & Build
- **Direktes Ausführen (F5)** – führt die aktuelle Datei über die konfigurierte VBX-Runtime aus
- **Build** – erzeugt eine verschlüsselte `.vbc` über `vbx Build`
- **Automatische `#use`-Ergänzung** – fehlende, tatsächlich verwendete optionale Module werden vor dem Ausführen automatisch in die `#use`-Zeile eingetragen (mehrfache/fehlplatzierte `#use`-Zeilen werden bereinigt)
- **Konsole** – eingebettetes `cmd.exe`, umschaltbar gegen die normale Programm-Ausgabe im unteren Panel

### Hilfe & Dokumentation
- **Hilfe-Panel** – seitliches, ein-/ausblendbares Panel mit Modul-Dokumentation aus `.md`-Dateien, Text markier- und kopierbar
- Dokumentation wird bei Bedarf von GitHub geladen und lokal gecacht (kein Internet nötig für bereits geladene Inhalte)

### Dateiverwaltung
- **Öffnen unterstützt** neben `.vb` auch `.txt`, `.json`, `.ini`, `.csv`, `.xml`, `.yaml`/`.yml`, `.log`, `.cfg`, `.env` (nur `.vb` ist ausführbar/buildbar)
- **Speichern unter** – unabhängig vom bestehenden Dateipfad an neuem Ort speichern
- **Neu laden** – aktuellen Tab-Inhalt von der Festplatte neu einlesen (mit Sicherheitsabfrage bei ungespeicherten Änderungen)
- **Letzte Sitzung wiederherstellen** – offene Tabs (inkl. ungespeicherter Änderungen) werden beim Beenden gesichert und beim nächsten Start wiederhergestellt
- **Single Instance** – ein zweiter Start (z. B. per Doppelklick oder "Öffnen mit") reicht die Datei an die bereits laufende Instanz weiter, statt ein zweites Fenster zu öffnen
- **Explorer-Integration** (optional, über Einstellungen) – registriert "Öffnen mit VBX Editor" im Kontextmenü für unterstützte Dateitypen

### Sonstiges
- **Dark/Light-Theme** – umschaltbar über Einstellungen-Dialog
- **Schriftgröße** einstellbar
- **Fenstertitel** zeigt die Editor-Versionsnummer

## Projektstruktur

```
assets/
  vbx.json                        Keywords, Operatoren, Farben (Dark + Light), Syntax-Datenbank

%APPDATA%\VBX Editor\
  config.json                     Theme, Schriftgröße, Pfad zur vbx.exe, Explorer-Integration
  session.json                    Zuletzt offene Tabs (für Sitzungswiederherstellung)
  docs_cache\                     Lokal gecachte Hilfe-Dokumentation (.md)
```

## Konfiguration

Beim ersten Start wird unter

```
%APPDATA%\VBX Editor\config.json
```

eine Standardkonfiguration angelegt. Der Pfad zur `vbx.exe` wird automatisch gesucht:

1. Neben dem Editor selbst (`vbx.exe` im aktuellen Arbeitsverzeichnis)
2. Über die System-`PATH`-Umgebungsvariable

Falls nichts gefunden wird, kann der Pfad im **Einstellungen-Dialog** (⚙) oder direkt in der `config.json` unter `vbx.executable` gesetzt werden:

```
"executable": "C:\\Program Files\\vbx\\vbx.exe"
```

Theme, Schriftgröße und Explorer-Integration lassen sich ebenfalls über den Einstellungen-Dialog anpassen.

## Hilfe-Dokumentation

Die Modul-Dokumentation (`.md`-Dateien, z. B. `array.md`, `net.md`, `Allgemein.md`) wird nicht mit der App ausgeliefert, sondern bei Bedarf von GitHub geladen und lokal gecacht unter:

```
%APPDATA%\VBX Editor\docs_cache\
```

Über das **Aktualisieren-Symbol (⟳)** im Hilfe-Panel wird der Cache manuell mit dem aktuellen Stand des Repositories synchronisiert. Ohne Internetverbindung wird der zuletzt geladene Stand aus dem Cache angezeigt. `Allgemein.md` erscheint dabei immer als erster Eintrag in der Liste.

## Explorer-Integration ("Öffnen mit")

Über den Einstellungen-Dialog lässt sich VBX Editor im Windows-Explorer-Kontextmenü registrieren ("Öffnen mit VBX Editor"). Die Registrierung erfolgt ausschließlich unter `HKEY_CURRENT_USER` (keine Adminrechte nötig) und setzt **nicht** die Standard-App für die betroffenen Dateitypen.

Läuft VBX Editor bereits, wird eine so geöffnete Datei als neuer Tab in der laufenden Instanz geöffnet, statt ein zweites Fenster zu starten.