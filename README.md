# Hixup

Native macOS-App (macOS 26+), die Lags und Hick-ups diagnostiziert: Ein Hintergrundprozess loggt dauerhaft Systemwerte und meldet kritische Zustaende per Notification. Verteilung notarisiert ausserhalb des App Stores.

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/bausi2k)

## Status

Agent, Dienst-Registrierung, App-Icon, Energie-Collector und Event-Store sind fertig. Status-Modell ist fertig. Naechster Schritt: Menueleisten-Popover und Dashboard (Phase 4).

## Architektur

```
HixupApp   (geplant)  SwiftUI, Menueleiste, Diagramme
HixupAgent (geplant)  LaunchAgent, permanentes Logging, Regeln, Notifications
HixupCore  (aktuell)  Collectors, Regel-Engine, Storage – ohne UI, voll testbar
```

Collectors lesen ueber injizierbare Provider (`MemoryStatsProviding`, `ProcessListing`). Die System-Implementierungen nutzen `host_statistics64`, `sysctl` und `libproc`; Tests laufen mit Stubs.

## Entwicklung

Voraussetzung: Xcode (der Package-Manifest der Command Line Tools kennt macOS 26 nicht).

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Xcode-Projekt

Das Projekt wird mit [XcodeGen](https://github.com/yonaskolb/XcodeGen) aus `project.yml` erzeugt; die `.xcodeproj` ist nicht eingecheckt.

```bash
brew install xcodegen
xcodegen generate && open Hixup.xcodeproj
```

Aenderungen an Targets und Einstellungen gehoeren in `project.yml`, sonst gehen sie beim naechsten `generate` verloren.

- `HixupApp` (`casa.gruber.hixup`): Menueleisten-App mit Schalter fuer den Hintergrunddienst.
- `HixupAgent` (`casa.gruber.hixup.agent`): Hintergrund-App, eingebettet unter `Contents/Library/LoginItems`, misst dauerhaft und sendet Notifications.
- Signierung: Team-ID lokal in `Config/Local.xcconfig` eintragen (Vorlage: `Config/Local.xcconfig.example`, nicht eingecheckt).

Unsigniert bauen (Build und Tests):

```bash
xcodebuild -project Hixup.xcodeproj -scheme HixupApp CODE_SIGNING_ALLOWED=NO build
```

## App-Icon

Das Icon wird per Script erzeugt und als Asset Catalog (`Apps/Shared/Assets.xcassets`) von beiden Targets genutzt. Der Agent braucht es ebenfalls, weil Notifications und die Anmeldeobjekte sein Icon zeigen. Aenderungen am Motiv in `scripts/make-icon.swift`, danach neu erzeugen:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/make-icon.swift
```

Das Menueleisten-Symbol bleibt das monochrome SF Symbol `waveform.path.ecg` (Apple HIG).

## Hintergrunddienst

`AgentRunner` misst im Takt von `sampleInterval`, speichert den Snapshot, wertet die Regeln aus und meldet neue Alerts an einen `AlertNotifier`. Messfehler werden protokolliert und beenden den Dienst nicht. Einmal taeglich werden Snapshots ausserhalb der Retention geloescht.

Einstellungen: `~/Library/Application Support/Hixup/settings.json` (wird bei jedem Durchlauf neu gelesen; fehlende Werte nutzen Standardwerte, ungueltige werden begrenzt).

| Schluessel | Standard | Bereich |
|---|---|---|
| `sampleInterval` | 5 | 1–300 s |
| `retentionDays` | 14 | 1–365 |
| `topProcessCount` | 10 | 1–50 |
| `watchedProcessNames` | [] | z. B. `["Citrix Viewer"]` |

**Dienstmodell: Login-Item (geprueft).** Der Agent ist ein eingebettetes Login-Item (`SMAppService.loginItem`). Auf macOS 26 verifiziert (Apple-Development-Signierung):

- Anmeldung ueber den Schalter in der Menueleiste, optional mit Freigabe unter Systemeinstellungen, Allgemein, Anmeldeobjekte.
- Der Agent startet nach einem Absturz (`kill -9`) innerhalb weniger Sekunden automatisch neu.
- Notifications werden zugestellt: Ein Prozess ueber 200 % CPU fuer mehr als 120 s loest eine Meldung mit Prozessnamen aus.
- Der Prozess heisst `casa.gruber.hixup.agent`.

Hinweis zur Team-ID: Sie steht im Feld `OU` des Zertifikats, nicht in der Klammer hinter dem Zertifikatsnamen.

## Storage und Regeln

- `SQLiteSnapshotStore`: Snapshots (Speicher + Top-Prozesse) als JSON in SQLite, Zeitraumabfrage, `purge(olderThan:)` fuer die Retention (Standard 14 Tage).
- `SQLiteEventStore`: ausgeloeste Alerts (JSON) und manuelle Marker (Zeitstempel, optionale Notiz) fuer den Verlauf in der Oberflaeche. Der Agent schreibt jeden Alert hinein; die Retention gilt auch hier.
- Beide Stores teilen sich eine Datei (`hixup.sqlite`) und nutzen den **WAL-Modus** mit `busy_timeout`: Die App kann lesen, waehrend der Agent schreibt.
- `RuleEngine`: Regel = Metrik, Schwellwert, Mindestdauer, Cooldown. Die Zeit stammt aus den Snapshots, nicht aus einer Uhr. Standardregeln: Speicher unter 15 % fuer 60 s (critical), Prozess ueber 200 % CPU fuer 120 s (warning), Prozess ueber 8 W geschaetzte Leistung fuer 120 s (warning).

## Status-Modell

`StatusEvaluator` berechnet aus dem Verlauf der Snapshots den aktuellen Zustand fuer Popover und Dashboard. Er ist zustandslos und liest nur Snapshots; die App braucht den internen Zustand der `RuleEngine` des Agents nicht.

- **Gesamtstatus** (`HealthLevel`): `critical` oder `warning`, sobald eine Regel ihre Mindestdauer erreicht hat; sonst `ok`. `unknown`, wenn keine Daten vorliegen oder der neueste Snapshot aelter als 30 s ist (z. B. Dienst aus).
- **Aktive Verstoesse:** alle aktuell verletzten Regeln mit Wert, Schwelle, Verursacher, Beginn und Dauer. Noch nicht anhaltende Verstoesse werden gelistet (`isSustained == false`), heben den Status aber nicht an.
- **Verursacher:** Prozesse gleichen Namens werden zusammengefasst und ueber ein Fenster von 30 s gemittelt. Die Rangliste ordnet nach einem Score (Summe der Verhaeltnisse zu den Referenzwerten). Als Grund (`reasons`) gelten CPU ab 150 %, Energie ab 5 W, Speicher ab 4 GiB und Wakeups ab 1000/s.
- Die letzten Alerts werden durchgereicht.

## Energie

Pro Prozess erfasst Hixup die vom System geschaetzte Energie (`proc_pid_rusage`, `ri_energy_nj`) als Leistung in Watt sowie Wakeups pro Sekunde. Das ist eine Schaetzung des Systems, kein Messgeraet. Orientierung auf Apple Silicon: ein voll ausgelasteter Kern liegt bei rund 6 W, vier Threads bei rund 13 W. Daher feuert die Standardregel erst ab 8 W. Prozesse mit hohem Verbrauch und niedriger CPU-Last (z. B. GPU-lastig) werden zusaetzlich zur Top-N nach CPU erfasst.

## Bekannte Einschraenkungen

- `kernel_task` (PID 0) ist ueber `libproc` ohne Root nicht lesbar und fehlt in der Prozessliste. Eine Gesamt-CPU-Metrik folgt spaeter.

Die urspruenglichen Diagnose-Scripts bleiben vorerst als Referenz im Repo `scripts`.
