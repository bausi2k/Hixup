# MacDiag

Native macOS-App (macOS 26+), die Lags und Hick-ups diagnostiziert: Ein Hintergrundprozess loggt dauerhaft Systemwerte und meldet kritische Zustaende per Notification. Verteilung notarisiert ausserhalb des App Stores.

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/bausi2k)

## Status

Phase 1 von 6: `MacDiagCore` mit Speicher- und Prozess-Collectors.

## Architektur

```
MacDiagApp   (geplant)  SwiftUI, Menueleiste, Diagramme
MacDiagAgent (geplant)  LaunchAgent, permanentes Logging, Regeln, Notifications
MacDiagCore  (aktuell)  Collectors, Regel-Engine, Storage – ohne UI, voll testbar
```

Collectors lesen ueber injizierbare Provider (`MemoryStatsProviding`, `ProcessListing`). Die System-Implementierungen nutzen `host_statistics64`, `sysctl` und `libproc`; Tests laufen mit Stubs.

## Entwicklung

Voraussetzung: Xcode (der Package-Manifest der Command Line Tools kennt macOS 26 nicht).

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Die urspruenglichen Diagnose-Scripts bleiben vorerst als Referenz im Repo `scripts`.
