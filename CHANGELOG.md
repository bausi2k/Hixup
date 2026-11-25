# Changelog

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/bausi2k)

## [Unreleased] – Menueleisten-Popover

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
