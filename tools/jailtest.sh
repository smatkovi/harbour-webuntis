#!/bin/bash
# Fuehrt eine Python-Sonde im echten Sailjail-Sandkasten der App aus.
# ACHTUNG: Sonden duerfen nichts in Sailfish Secrets anlegen - sie laufen
# unter einer anderen Kennung als die App. Was eine Sonde anlegt, muss sie
# auch wieder entfernen (deleteCollection, Signatur ss(i)s).
# Aufruf: tools/jailtest.sh <sonde.py>   (Sonde schreibt nach stdout)
set -e
PROBE=$1
[ -f "$PROBE" ] || { echo "Sonde fehlt: $PROBE"; exit 1; }
APPDIR=/usr/share/harbour-webuntis
CACHE=$HOME/.cache/harbour-webuntis/harbour-webuntis
sudo cp "$PROBE" $APPDIR/_probe.py
# pyotherside gibt es nur im QML-Prozess -> Attrappe
sudo tee $APPDIR/pyotherside.py >/dev/null <<'STUB'
def send(*a, **k): pass
def atexit(*a, **k): pass
STUB
mkdir -p "$CACHE"
/usr/bin/firejail --quiet \
  --template=OrganizationName:harbour-webuntis \
  --template=ApplicationName:harbour-webuntis \
  --private-bin=sailfish-qml,python3,python3.11 \
  --whitelist=$APPDIR \
  --whitelist=/usr/share/applications/harbour-webuntis.desktop \
  --whitelist=$HOME/.local/share/harbour-webuntis \
  --whitelist=$HOME/.config/harbour-webuntis \
  --whitelist=$HOME/.cache/harbour-webuntis \
  --mkdir=$CACHE --whitelist=$CACHE \
  --dbus-user.own=harbour-webuntis.harbour-webuntis \
  --profile=/etc/sailjail/permissions/Internet.permission \
  --profile=/etc/sailjail/permissions/Secrets.permission \
  --profile=/etc/sailjail/permissions/Base.permission \
  -- /usr/bin/python3 $APPDIR/_probe.py >"$CACHE/probe.out" 2>&1 || true
sudo rm -f $APPDIR/_probe.py $APPDIR/pyotherside.py
sudo rm -rf $APPDIR/__pycache__
cat "$CACHE/probe.out"
