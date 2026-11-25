# Changelog

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/bausi2k)

## [Unreleased] – Gesamt-CPU

- `SystemCPUCollector`: Gesamtauslastung aller Kerne aus `host_processor_info` (Tick-Differenz); erfasst auch Last ohne Prozesszuordnung, etwa `kernel_task`
- `Snapshot.systemCPUPercent` (optional; alte Snapshots bleiben lesbar)
- Neue Metrik und Regel "Gesamt-CPU-Last hoch" (Standard: ueber 90 % fuer 120 s, Warnung), Schwelle in den Einstellungen
- Popover-Kachel und Dashboard-Diagramm zeigen "CPU gesamt" (0 bis 100 %, mit Schwellenlinie); ohne Daten bleibt die Summe der Top-Prozesse als Rueckfall
- 128 Tests; Werte im laufenden Agent gegen `top` geprueft

## Regel-Einstellungen

- Schwellen und Mindestdauern der Standardregeln in den Einstellungen: Speicher knapp (%), Prozess-CPU (%), Prozess-Energie (W), Mindestdauer fuer Speicher und fuer CPU/Energie; Button "Standardwerte"
- `settings.json` bekommt die neuen Felder; aeltere Dateien laufen mit Standardwerten weiter; Werte werden begrenzt
- Der Agent baut die Regeln bei jeder Messung aus den Einstellungen; `RuleEngine.update(rules:)` behaelt den Zustand nur fuer unveraenderte Regeln
- Die App bewertet den Status mit denselben Regeln (`StatusService(evaluatorProvider:)`), damit Popover und Benachrichtigung uebereinstimmen
- 118 Tests; Ende-zu-Ende geprueft: Speicherschwelle auf 90 % loeste im laufenden Agent einen Alarm aus

## Release-Pipeline

- Dependabot (woechentlich) fuer GitHub Actions und Swift-Pakete
- CI (`.github/workflows/ci.yml`): `swift test` und unsignierter Release-Build auf `macos-26`
- `scripts/build-release.sh`: Release-Build und DMG; mit `DEVELOPER_ID`, `TEAM_ID`, `NOTARY_PROFILE` signiert und notarisiert
- Release-Workflow (`release.yml`) baut bei `v*`-Tags ein unsigniertes DMG und legt ein GitHub-Release an
- Notarisierte Verteilung braucht das bezahlte Apple Developer Program (Developer-ID-Zertifikat); bis dahin sind Releases unsigniert
- CI laeuft auf `macos-26`; der Energiezaehler-Test wird auf virtuellen CI-Runnern uebersprungen (dort kein Energy Accounting)

## Einstellungen und Hotkey

- Einstellungsfenster (Popover -> "Einstellungen"): Messintervall (Standard 5 s), Prozesse pro Messung, Aufbewahrung, immer erfasste Prozesse; schreibt `settings.json`, der Agent uebernimmt es bei der naechsten Messung
- Globaler Hotkey ⌃⌥⌘H setzt einen Marker (Carbon `RegisterEventHotKey`, keine Berechtigung noetig); laeuft im Agent, also auch bei beendeter App
- Button "Marker setzen" im Popover
- `MarkerRecorder` und `AgentSettings.parseWatchedNames` im Core, getestet
- 108 Tests; der Hotkey selbst ist nicht automatisch testbar (Tastendruck braucht Bedienungshilfen-Rechte)

## Dashboard

- Dashboard-Fenster (aus dem Popover per "Dashboard öffnen"): Statuskopf, Zeitraum 1 Std. / 24 Std. / 14 Tage
- Diagramme fuer freien Speicher (mit Schwelle), CPU und Energie; Alerts (rot/orange) und Marker (blau) als senkrechte Linien
- Verursacher ueber den gewaehlten Zeitraum als Balkendiagramm
- Ereignisliste: Klick auf einen Alert oder Marker hebt den Zeitpunkt in allen Diagrammen hervor
- `HistoryService` und `SnapshotStore.sampledSnapshots` (SQL-seitig ausgeduennt, max. ca. 400 Punkte); lange Zeitraeume zeigen dadurch Stichproben, kurze Spitzen koennen fehlen
- 103 Tests

## Menueleisten-Popover

- Klick auf das Menueleisten-Symbol zeigt ein Popover: Status mit Ampelfarbe und Schlagzeile, Kacheln mit Verlauf (Speicher, CPU, Energie), ueberschrittene Schwellen, groesste Verursacher mit Balken und Gruenden
- Das Menueleisten-Symbol wechselt bei Warnung und Kritisch die Form (monochromes SF Symbol)
- `StatusService` (Store -> Status und Verlauf) und `StatusPresentation` (Texte, Symbole) im Core, getestet; `StatusModel` aktualisiert die App alle 5 s
- `ActiveViolation` kennt jetzt die Metrik (fuer Einheiten)
- 96 Tests

## Status-Modell

- `StatusEvaluator`: Gesamtstatus (unbekannt, ok, Warnung, kritisch), aktive Regelverstoesse mit Beginn und Dauer, Verursacher-Rangliste
- Prozesse gleichen Namens werden zusammengefasst und ueber 30 s gemittelt; Gruende CPU, Energie, Speicher, Wakeups
- Zustandslos: laesst sich in der App aus der Datenbank ableiten
- 83 Tests; mit echten Daten des Agents geprueft

## Store-Erweiterungen

- SQLite im WAL-Modus (`busy_timeout` 5 s): paralleles Lesen und Schreiben durch App und Agent
- `SQLiteEventStore`: Alerts und manuelle Marker persistent, mit Zeitraumabfrage und Purge
- Gemeinsame `SQLiteDatabase`-Huelle fuer beide Stores
- `AgentRunner` speichert jeden Alert; Fehler beim Speichern verhindern die Notification nicht
- 65 Tests

## Energie-Collector

- Energie (Watt) und Wakeups pro Sekunde je Prozess aus `proc_pid_rusage`
- Auswahl: Top-N nach CPU zusaetzlich Top-N nach Energie, dazu beobachtete Prozesse
- Neue Metrik `highestProcessEnergyWatts` und Standardregel `energy-sustained` (8 W fuer 120 s)
- Alte gespeicherte Snapshots ohne Energiewerte bleiben lesbar
- 53 Tests; Werte mit realer Last geprueft (1 Kern ca. 6 W, 4 Threads ca. 13 W)

## App-Icon

- App-Icon (EKG-Kurve auf Blaugruen-Verlauf) als Asset Catalog fuer App und Agent
- Reproduzierbare Erzeugung per `scripts/make-icon.swift`

## Dienst-Registrierung geprueft

- Login-Item als Dienstmodell bestaetigt: Anmeldung per `SMAppService`, automatischer Neustart nach Absturz, Notification-Zustellung
- Entscheidung: kein LaunchAgent noetig
- Signierung lokal ueber `Config/Local.xcconfig` (Team-ID aus dem `OU`-Feld des Zertifikats)

## Agent und Xcode-Projekt

- `AgentRunner`: messen, speichern, Regeln auswerten, benachrichtigen, taegliche Retention
- `AgentSettings` (JSON): Messintervall, Retention, beobachtete Prozesse, Anzahl Top-Prozesse
- XcodeGen-Projekt mit `HixupApp` (Menueleiste, Dienst-Schalter) und `HixupAgent` (Login-Item, Notifications)
- Bundle-IDs `casa.gruber.hixup` und `casa.gruber.hixup.agent`
- 43 Tests

## Storage und Regeln

- `Snapshot`-Modell und `SQLiteSnapshotStore` (Append, Zeitraumabfrage, Purge)
- `RuleEngine` mit Mindestdauer und Cooldown, `Alert`-Ereignisse mit Verursacher
- Standardregeln fuer knappen Speicher und anhaltend hohe CPU-Last
- 29 Tests; CPU-Berechnung gegen `ps` verifiziert (98,0 % vs. 98,5 %)

## Core Collectors

- Swift Package `HixupCore` (macOS 26+)
- `MemoryCollector`: verfuegbarer Speicher in Prozent, belegt, komprimiert
- `ProcessCollector`: CPU-Last aus Messdifferenz, Top-N plus beobachtete Prozesse
- Tests mit Stubs und gegen das echte System (13 Tests)
