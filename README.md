# WebUntis für Sailfish OS und MeeGo Harmattan

Inoffizieller WebUntis-Klassenbuch-Client. Drei Pakete aus einem Baum:

| Paket | Gerät | Anmeldung |
|---|---|---|
| `harbour-webuntis` | Sailfish OS | Benutzername + Passwort (JSON-RPC) |
| `harbour-webuntis-secret` | Sailfish OS | Benutzer + Schlüssel aus dem QR-Code (Mobile-API/TOTP), für Microsoft-365-Schulen |
| `webuntis` | Nokia N9 / N950, Harmattan PR1.3 | Benutzer + Schlüssel aus dem QR-Code |

Die beiden Sailfish-Pakete belegen dieselben Pfade und schließen sich darum
gegenseitig aus – es kann nur eines von beiden installiert sein.

## Was in 1.8.7 / 3.61 / 1.5.3 repariert wurde

**Schulsuche und Anmeldung liefen auf Sailfish gar nicht an.** Grund: das
Python-Modul begann mit `import requests`. Sailjail gibt der App vom
Heimverzeichnis nur `~/.local/share/<app>` & Co. frei – ein mit `pip --user`
installiertes `requests` liegt in `~/.local/lib/python3.11/site-packages` und
ist im Sandkasten unsichtbar. Der Import scheiterte, damit war das ganze
Hintergrundmodul tot: die Suche drehte endlos, die Anmeldung antwortete nie.
Im Terminal lief derselbe Import einwandfrei, und auf Geräten, die `requests`
aus den Jolla-Repos unter `/usr/lib` hatten, lief die App auch – daher „geht
auf dem einen Telefon, auf dem anderen nicht".

HTTP läuft jetzt über `untis_http.py`, einen kleinen requests-Nachbau auf
`urllib` (Standardbibliothek, immer vorhanden). Die Pakete verlangen außerdem
per `Requires:` ausdrücklich pyotherside und python3-base – fehlte das, startete
die App mit weißem Schirm.

Weiter:

* **Schulsuche braucht 3 Zeichen.** Mit zwei Zeichen antwortet
  `schoolsearch.webuntis.com` fast immer mit `-6003 "too many results"`; das
  stand vorher als englischer Fehler in Rot da. Jetzt steht in Grau
  „Zu viele Treffer – bitte genauer eingeben".
* **Adresse von Hand eintragen.** Findet die Suche die Schule nicht, kann die
  WebUntis-Adresse aus dem Browser eingesetzt werden
  (`https://xyz.webuntis.com/WebUntis/?school=kennung`); Server und
  Schulkennung werden daraus gelesen.
* **Scheitert das Hintergrundmodul doch einmal**, steht der Grund auf der
  Anmeldeseite statt nur im Journal.
* **Harmattan:** `QTimer.singleShot` hält unter PySide die übergebene Funktion
  nicht fest – Suchergebnisse und der Abschluss der Anmeldung konnten
  unterwegs verschwinden. Jetzt hängen echte Timer samt Rückruf am Objekt.

## Installieren

Sailfish OS:

```
sudo rpm -Uvh harbour-webuntis-1.8.7-1.noarch.rpm
```

N9 / N950 (eigene Pakete brauchen `aegis-dpkg`, sonst lässt sich daraus nichts
starten):

```
sudo aegis-dpkg -i webuntis_1.5.3_all.deb
```

## Bauen

Kein SDK nötig, beides läuft am Gerät:

```
tools/build-rpm.sh     # -> rpms/
tools/build-deb.sh     # -> debs/
```

## Prüfen

`tools/jailtest.sh <sonde.py>` führt eine Python-Sonde im echten
Sailjail-Sandkasten der App aus – das ist der einzige Weg, so einen fehlenden
Import zu sehen, denn im Terminal fällt er nicht auf. Sonden dürfen dabei
nichts in Sailfish Secrets anlegen: sie laufen unter einer anderen Kennung als
die App.

`tools/n9ssh.sh` ist der Zugang zum N9/N950 (deren OpenSSH kennt weder ed25519
noch SHA-2).
