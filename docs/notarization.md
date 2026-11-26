# Notarisierung (signiertes DMG)

Ein notarisiertes DMG startet ohne Gatekeeper-Warnung. Voraussetzung ist das bezahlte Apple Developer Program (99 USD/Jahr). Mit einem kostenlosen Konto geht es nicht.

## Einmalig einrichten

1. **Developer ID Application Zertifikat** erstellen: Xcode → Settings → Accounts → Team wählen → *Manage Certificates* → `+` → *Developer ID Application*. Es landet im Schlüsselbund.
2. **Identität und Team ID** nachschlagen:

   ```bash
   security find-identity -v -p codesigning
   ```

   Gesucht ist die Zeile `Developer ID Application: Name (TEAMID)`. Die Team ID steht in Klammern und unter developer.apple.com → Membership.
3. **App-spezifisches Passwort** erzeugen: account.apple.com → Anmeldung und Sicherheit → App-spezifische Passwörter.
4. **Notary-Profil speichern** (einmalig; die Zugangsdaten liegen danach im Schlüsselbund):

   ```bash
   xcrun notarytool store-credentials hixup-notary --apple-id "<Apple-ID>" --team-id "<TEAMID>" --password "<app-spezifisches Passwort>"
   ```

## Release lokal bauen

```bash
DEVELOPER_ID="Developer ID Application: Name (TEAMID)" TEAM_ID="TEAMID" NOTARY_PROFILE="hixup-notary" scripts/build-release.sh
```

Das Skript baut mit Hardened Runtime, signiert (inkl. eingebettetem Agent), packt das DMG, reicht es bei Apple ein (`notarytool submit --wait`) und heftet das Ticket an (`stapler staple`). Ergebnis: `dist/Hixup-<Version>.dmg`.

Prüfen:

```bash
xcrun stapler validate dist/Hixup-*.dmg
spctl --assess --type open --context context:primary-signature -v dist/Hixup-*.dmg
```

## Release auf GitHub

Der Workflow `release.yml` baut bisher ein unsigniertes DMG. Für ein signiertes Release das lokal gebaute DMG an das GitHub-Release hängen:

```bash
gh release upload v<Version> dist/Hixup-<Version>.dmg --clobber
```

Soll CI selbst signieren, braucht der Workflow als Secrets das Zertifikat (`.p12`, base64), dessen Passwort, die Apple-ID, das App-Passwort und die Team ID. Er müsste das Zertifikat in einen temporären Schlüsselbund importieren und `notarytool` mit `--apple-id/--team-id/--password` statt eines Profils aufrufen. Das ist nicht umgesetzt.

## Hinweise

- Der Hintergrunddienst (Login-Item) lässt sich nur mit einer gültigen Signatur zuverlässig registrieren.
- Die Zugangsdaten gehören nie ins Repository.
- Auf verwalteten Geräten entscheidet die Policy, ob signierte Apps starten dürfen.
