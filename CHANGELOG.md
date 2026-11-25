# Changelog

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/bausi2k)

## [Unreleased] – Dienst-Registrierung geprueft

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
