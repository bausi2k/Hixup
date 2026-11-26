# Changelog

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/bausi2k)

## [Unreleased]

## [0.8.0] – Hixup hört zu

Marker mit Notiz: Nach dem Hotkey fragt ein kleines Feld "Was hakt?", die Notiz lässt sich im Detailfenster ändern und fließt in den KI-Bericht ein.

### Marker mit Notiz

- Nach dem Hotkey (⌃⌥⌘H) erscheint ein kleines Eingabefeld "Was hakt?": Enter speichert, Esc oder 8 s ohne Eingabe schließen es. Der Marker selbst ist sofort gespeichert; das Feld nimmt Tastatureingaben an, ohne die aktive App zu wechseln
- Im Marker-Detailfenster lässt sich die Notiz jederzeit ändern oder entfernen; sie erscheint im KI-Bericht
- `EventStore.setMarkerNote`, `MarkerRecorder.updateNote` (Leerraum entfernt, leer = keine Notiz, höchstens 200 Zeichen)
- 243 Tests

## [0.7.0] – Hixup auf Samtpfoten

Speicherdruck als Alarm und ein deutlich ressourcenschonenderer Betrieb: im Ruhezustand rund 0,3 % CPU und 30 MB statt 2,3 % und 55–75 MB.

### Ressourcenschonender Betrieb

- Gemessen im Ruhezustand (nur Menüleiste): CPU von rund 2,3 % auf rund 0,3 %, Speicher von 55–75 MB auf rund 30 MB (Release-Build); der Hintergrunddienst lag schon bei 0,2 % CPU und 9 MB
- Status und Verlauf werden aus einem einzigen Lesevorgang berechnet (`StatusService.overview`) statt dieselben 120 Snapshots doppelt zu dekodieren
- Datenbankzugriffe laufen im Hintergrund statt im Hauptthread
- Popover und Dashboard aktualisieren nur, solange ihr Fenster tatsächlich sichtbar ist (`WindowVisibility`); sonst alle 20 s nur für das Menüleisten-Symbol; geschlossene Dashboards geben ihre Daten frei
- Diagrammpunkte kommen aus eigenen Spalten (`avail`, `cpu_sum`, `energy_sum`, `sys_cpu`) statt aus dem JSON; ältere Zeilen werden weiter korrekt gelesen (Migration ohne Neuberechnung)
- Die Rangliste im Dashboard nutzt höchstens 120 gleichmäßig verteilte Messpunkte
- Dashboard-Takt je Zeitraum: 1 Std. 10 s, 24 Std. 60 s, 14 Tage 300 s
- Unveränderte Daten lösen keine Neuberechnung der Ansichten mehr aus
- 236 Tests

### Speicherdruck als Alarm

- Der Agent misst den Speicherdruck (`kern.memorystatus_vm_pressure_level`) bei jeder Messung; `Snapshot.memoryPressure` ist optional, alte Daten bleiben lesbar
- Neue Standardregeln "Speicherdruck erhöht" (Warnung, ab Stufe Warnung, Mindestdauer wie der Speicher-Alarm) und "Speicherdruck kritisch" (kritisch, ab Stufe kritisch, Mindestdauer höchstens 30 s)
- Einstellung "Speicherdruck-Alarm" (Feineinstellung, standardmäßig an)
- Popover, Verstöße und Benachrichtigung nennen die Stufe ("Speicherdruck: Warnung") statt Prozentzahlen
- Die Spitzen im Dashboard gewichten hohen Druck mit; die Marker-Einschätzung nutzt den höchsten Druck im Fenster
- 230 Tests; Messwert auf dem Mac geprüft

## [0.6.0] – Hixup schnüffelt

Marker-Details mit Ursachen-Einschätzung und Berichtsvorschau, volle Prozessnamen und Hixup selbst nur noch bei echter Last in der Rangliste.

### Marker-Details und Einschätzung

- Klick auf einen Marker im Dashboard öffnet ein Detailfenster: Tiefenmessung und Messwert-Tabelle, mögliche Ursachen mit Einstufung (Hoch / Mittel / Niedrig) und Begründung, Vorschau des KI-Berichts mit Zeichenzahl sowie Kopieren und Sichern
- Das Fenster erklärt, was an die KI geht: Hixup sendet nichts selbst; der Bericht verlässt die App nur per Kopieren oder Sichern; enthalten sind Prozessnamen, Messwerte und Systemdaten, nicht enthalten Dateiinhalte, Dateinamen und Benutzername
- `MarkerDiagnosis`: regelbasierte Heuristik für Speicherknappheit, CPU-Last, Energie, Thermik, Netzwerk und Hixup selbst; Schwellen aus den Einstellungen; ohne Auffälligkeit erscheint "Keine Ursache in den Messwerten sichtbar"
- Die Einschätzung steht auch im exportierten Bericht ("heuristisch, kann falsch sein") und lässt sich im Detailfenster abschalten
- `MarkerMetrics` teilen sich Bericht und Detailfenster; 215 Tests

### Fix: Prozessnamen und Hixup in der Rangliste

- Prozessnamen kommen aus dem Programmpfad statt aus `proc_name` und sind nicht mehr auf ca. 31 Zeichen gekürzt (z. B. "Google Chrome Helper (Renderer)")
- Hixup und der Hintergrunddienst erscheinen in der Rangliste der ressourcenhungrigsten Apps nur noch, wenn sie selbst auffällig viel verbrauchen
- 195 Tests

## [0.5.0] – Hixup apportiert

Marker mit Tiefenmessung (Speicherdruck, Swap, Thermik, Netzwerk), Export der Marker als Bericht für KI-Analysen, Fokus-Fix und Notarisierungs-Doku.

### Marker-Export für KI-Analysen

- Dashboard → Ereignisse → "Für KI exportieren": erzeugt einen Markdown-Bericht (Zwischenablage oder Datei) für alle Marker des Zeitraums; Rechtsklick auf einen Marker exportiert nur diesen
- Inhalt: Einleitung mit Analyseauftrag, Systeminfos (Modell, Chip, RAM, macOS, Betriebszeit), Messintervall und Schwellen, je Marker die Tiefenmessung (Speicherdruck, Swap, Thermik, Netzwerk), Tabelle "Ø davor / beim Marker / Spitze" für Speicher, CPU und Energie, die fünf ressourcenhungrigsten Apps und Alerts im Fenster von ±5 Minuten, Hinweis auf Messlücken
- Bericht auf Deutsch oder Englisch je nach Spracheinstellung; er enthält nur Prozessnamen und Messwerte
- `MarkerReportBuilder` (rein berechnend) und `MarkerReportService` im Core
- 189 Tests; Bericht mit echten Messdaten geprüft

### Tiefenmessung am Marker

- Beim Setzen eines Markers (Hotkey oder Button) misst Hixup einmalig zusätzliche Werte und speichert sie am Marker: Speicherdruck, Swap-Nutzung, thermischer Zustand, Energiesparmodus sowie Netzwerk (aktive Schnittstelle: WLAN / Ethernet / VPN, Latenz und Paketverlust zum Router und zu 1.1.1.1)
- Der Marker wird sofort gespeichert, die Tiefenmessung (Ping, bis ca. 4 s) folgt im Hintergrund
- Neue Spalte `markers.detail` mit Migration für bestehende Datenbanken
- Hinweis: Für die Internet-Latenz sendet Hixup drei Pings an 1.1.1.1
- 175 Tests; echte Werte auf dem Mac geprüft

### Fix: Fokus-Diebstahl (Ursache)

- SwiftUIs `MenuBarExtra` ruft den Setter von `isInserted` fortlaufend mit dem aktuellen Wert auf; `VisibilityModel` aktivierte dabei jedes Mal die App. Jetzt ist ein unveränderter Wert ein No-op, aktiviert wird nur beim echten Einschalten des Dock-Symbols. Ursache per `lldb`-Backtrace gefunden, Fix per Fokus-Messung bestätigt

- Doku: Schritte zur Notarisierung (`docs/notarization.md`)

## [0.4.0] – Hixup mit Hundeblick

Eigenständige App mit optionalem Dock-Symbol, Deutsch und Englisch, Empfindlichkeit nach Hunderasse, Hunde-Wording sowie aufgeräumtes Popover, Dashboard und Einstellungen.

### Fix: Fokus-Diebstahl

- Hixup holte sich nach dem Start wiederholt den Fokus; der Wechsel zu anderen Apps war kaum möglich. Die Aktivierung läuft nur noch beim bewussten Einschalten des Dock-Symbols, und die Aktivierungsrichtlinie wird nur bei einer Änderung gesetzt

### Einstellungen aufgeräumt

- Gruppen: Alarme (Empfindlichkeit und Feineinstellung), Messung, Immer erfassen, Darstellung (Sprache, Dock, Menüleiste), Marker
- Jede Gruppe mit einer kurzen Erklärung
- 161 Tests

### Dashboard aufgeräumt

- Diagramme im 2×2-Raster (Speicher, CPU, Energie, Ressourcenhungrigste Apps); Schwellenlinien mit Beschriftung (Werte aus den Einstellungen)
- Tooltip beim Überfahren der Diagramme (Wert und Zeit); Alerts als Punkte auf der Kurve statt senkrechter Linien
- Ressourcenhungrigste Apps als Tabelle (Name, CPU, Energie, Speicher)
- Ereignisse nach Tag gruppiert (`DayGrouping`), Filter Alle / Alerts / Marker
- 161 Tests

### Popover aufgeräumt

- Verstöße in einer Zeile: "9 % (Schwelle unter 15 %), seit 1 Min."; ein Chip "Beobachtung" ersetzt "noch kein Alarm"
- Ressourcenhungrigste Apps: nur die Top 3 mit Hauptkennzahl (z. B. "CPU 240 %"); Details per Klick
- Fußbereich getrennt in Aktionen (Marker, Dashboard) und System (Dienst, Einstellungen, Beenden)
- Dauer- und Kennzahl-Texte als getestete Funktionen in `StatusPresentation`
- 158 Tests

### Eigenständige App

- Hixup startet als normale App mit Dock-Symbol und öffnet das Dashboard als Hauptfenster
- Einstellungen: "Im Dock anzeigen" und "Menüleisten-Symbol anzeigen"; der Wechsel gilt sofort (`NSApplication.setActivationPolicy`). Mindestens eines von beiden bleibt aktiv (`AppVisibility`), damit die App erreichbar bleibt
- Ohne Dock-Symbol startet Hixup wie bisher nur in der Menüleiste
- 155 Tests

### Englische Version

- `L10n`: prozessweite Lokalisierung (Deutsch/Englisch) über `.strings`-Dateien im Core; der deutsche Text dient als Schlüssel, fehlende Übersetzungen fallen auf Deutsch zurück
- Einstellungen: Sprache `System` / `Deutsch` / `English`; Wechsel gilt sofort ohne Neustart. `System` folgt der bevorzugten Systemsprache (Fallback Englisch)
- Die Sprache steht in `settings.json` (`language`), damit der Agent Benachrichtigungen in derselben Sprache sendet
- Bereits gespeicherte Alerts behalten die Sprache, in der sie entstanden sind
- 150 Tests (inkl. Prüfung, dass jeder deutsche Schlüssel eine englische Übersetzung hat)

### Hunde-Wording

- "Größte Verursacher" heißt jetzt "Ressourcenhungrigste App" (Popover und Dashboard)
- Statuszeile mit Hundestimmung: "Alles ruhig, Hixup döst." / "Hixup spitzt die Ohren." / "Hixup schlägt an!", dazu die hungrigste App
- Alarm-Benachrichtigungen bleiben sachlich
- 144 Tests

### Empfindlichkeit nach Hunderasse

- `SensitivityLevel`: Labrador (gelassen), Border Collie (Standard), Dobermann (wachsam) setzen alle Schwellen und Mindestdauern auf einmal
- Einstellungen: Schieberegler mit drei Stufen; die Feineinstellung bleibt aufklappbar, abweichende Werte zeigen "Individuell"
- 141 Tests

## [0.3.0] – Regeln, Gesamt-CPU und Spitzen

Konfigurierbare Regel-Schwellen, Gesamt-CPU-Metrik inkl. `kernel_task`, Lastspitzen im Dashboard sowie CI-, Dependabot- und Release-Pipeline.

### Spitzen im Dashboard

- `SnapshotStore.peakSnapshots`: je Zeitabschnitt der Snapshot mit der hoechsten Belastung (CPU, Energie, Speicherdruck) statt jedem n-ten
- Neue Spalte `snapshots.load` (Migration fuer bestehende Datenbanken; alte Zeilen zaehlen als 0)
- Dashboard-Diagramme nutzen Spitzen; Verursacher bleiben aus gleichmaessigen Stichproben berechnet
- 134 Tests

### Gesamt-CPU

- `SystemCPUCollector`: Gesamtauslastung aller Kerne aus `host_processor_info` (Tick-Differenz); erfasst auch Last ohne Prozesszuordnung, etwa `kernel_task`
- `Snapshot.systemCPUPercent` (optional; alte Snapshots bleiben lesbar)
- Neue Metrik und Regel "Gesamt-CPU-Last hoch" (Standard: ueber 90 % fuer 120 s, Warnung), Schwelle in den Einstellungen
- Popover-Kachel und Dashboard-Diagramm zeigen "CPU gesamt" (0 bis 100 %, mit Schwellenlinie); ohne Daten bleibt die Summe der Top-Prozesse als Rueckfall
- 128 Tests; Werte im laufenden Agent gegen `top` geprueft

### Regel-Einstellungen

- Schwellen und Mindestdauern der Standardregeln in den Einstellungen: Speicher knapp (%), Prozess-CPU (%), Prozess-Energie (W), Mindestdauer fuer Speicher und fuer CPU/Energie; Button "Standardwerte"
- `settings.json` bekommt die neuen Felder; aeltere Dateien laufen mit Standardwerten weiter; Werte werden begrenzt
- Der Agent baut die Regeln bei jeder Messung aus den Einstellungen; `RuleEngine.update(rules:)` behaelt den Zustand nur fuer unveraenderte Regeln
- Die App bewertet den Status mit denselben Regeln (`StatusService(evaluatorProvider:)`), damit Popover und Benachrichtigung uebereinstimmen
- 118 Tests; Ende-zu-Ende geprueft: Speicherschwelle auf 90 % loeste im laufenden Agent einen Alarm aus

### Release-Pipeline

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
