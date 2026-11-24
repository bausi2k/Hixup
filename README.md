# Hixup

Native macOS-App (macOS 26+), die Lags und Hick-ups diagnostiziert: Ein Hintergrundprozess loggt dauerhaft Systemwerte und meldet kritische Zustaende per Notification. Verteilung notarisiert ausserhalb des App Stores.

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/bausi2k)

## Status

Phase 2 von 6 abgeschlossen: `HixupCore` mit Collectors, SQLite-Storage und Regel-Engine.

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

## Storage und Regeln

- `SQLiteSnapshotStore`: Snapshots (Speicher + Top-Prozesse) als JSON in SQLite, Zeitraumabfrage, `purge(olderThan:)` fuer die Retention (geplant: 14 Tage).
- `RuleEngine`: Regel = Metrik, Schwellwert, Mindestdauer, Cooldown. Die Zeit stammt aus den Snapshots, nicht aus einer Uhr. Standardregeln: Speicher unter 15 % fuer 60 s (critical), Prozess ueber 200 % CPU fuer 120 s (warning).

## Bekannte Einschraenkungen

- `kernel_task` (PID 0) ist ueber `libproc` ohne Root nicht lesbar und fehlt in der Prozessliste. Eine Gesamt-CPU-Metrik folgt spaeter.

Die urspruenglichen Diagnose-Scripts bleiben vorerst als Referenz im Repo `scripts`.
