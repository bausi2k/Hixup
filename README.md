# Hixup

Native macOS-App (macOS 26+), die Lags und Hick-ups diagnostiziert: Ein Hintergrundprozess loggt dauerhaft Systemwerte und meldet kritische Zustaende per Notification. Verteilung notarisiert ausserhalb des App Stores.

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/bausi2k)

## Status

Phase 3 von 6: Agent und Xcode-Projekt (Dienst-Registrierung noch ungeprueft, siehe unten).

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

## Hintergrunddienst

`AgentRunner` misst im Takt von `sampleInterval`, speichert den Snapshot, wertet die Regeln aus und meldet neue Alerts an einen `AlertNotifier`. Messfehler werden protokolliert und beenden den Dienst nicht. Einmal taeglich werden Snapshots ausserhalb der Retention geloescht.

Einstellungen: `~/Library/Application Support/Hixup/settings.json` (wird bei jedem Durchlauf neu gelesen; fehlende Werte nutzen Standardwerte, ungueltige werden begrenzt).

| Schluessel | Standard | Bereich |
|---|---|---|
| `sampleInterval` | 5 | 1–300 s |
| `retentionDays` | 14 | 1–365 |
| `topProcessCount` | 10 | 1–50 |
| `watchedProcessNames` | [] | z. B. `["Citrix Viewer"]` |

**Offen (braucht Signierung):** Anmeldung des Agents per `SMAppService` und Notification-Zustellung sind noch nicht auf einem echten Lauf geprueft. Der Agent selbst wurde unsigniert gestartet und schreibt Snapshots.

## Storage und Regeln

- `SQLiteSnapshotStore`: Snapshots (Speicher + Top-Prozesse) als JSON in SQLite, Zeitraumabfrage, `purge(olderThan:)` fuer die Retention (geplant: 14 Tage).
- `RuleEngine`: Regel = Metrik, Schwellwert, Mindestdauer, Cooldown. Die Zeit stammt aus den Snapshots, nicht aus einer Uhr. Standardregeln: Speicher unter 15 % fuer 60 s (critical), Prozess ueber 200 % CPU fuer 120 s (warning).

## Bekannte Einschraenkungen

- `kernel_task` (PID 0) ist ueber `libproc` ohne Root nicht lesbar und fehlt in der Prozessliste. Eine Gesamt-CPU-Metrik folgt spaeter.

Die urspruenglichen Diagnose-Scripts bleiben vorerst als Referenz im Repo `scripts`.
