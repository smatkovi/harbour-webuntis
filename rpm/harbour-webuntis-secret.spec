Name:       harbour-webuntis-secret
Summary:    WebUntis for Microsoft 365 Schools
Version:    3.61
Release:    1
License:    MIT
BuildArch:  noarch

# busybox-xargs vertraegt brp-strip nicht, und es gibt nichts zu strippen
%define __os_install_post %{nil}
Requires:   pyotherside-qml-plugin-python3-qt5
Requires:   python3-base
Conflicts:  harbour-webuntis

%description
WebUntis client for Sailfish OS using Mobile API with TOTP authentication.
Designed for Microsoft 365 schools that do not support traditional login.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a %{tree}/usr %{buildroot}/
rm -rf %{buildroot}/usr/share/harbour-webuntis/__pycache__

%files
%defattr(0644,root,root,0755)
/usr/share/applications/harbour-webuntis.desktop
/usr/share/harbour-webuntis
/usr/share/icons/hicolor/*/apps/harbour-webuntis.png

%changelog
* Sat Oct 10 2026 Sebastian Matkovich <smatkovi@users.noreply.github.com> - 3.61-1
- Fixed: Schulsuche und Anmeldung liefen im Sailjail-Sandkasten nie an,
  weil "import requests" dort scheitert (pip --user ist unsichtbar).
  HTTP laeuft jetzt ueber untis_http (urllib, Standardbibliothek).
- Fixed: Schulsuche braucht 3 Zeichen; -6003 heisst jetzt
  "Zu viele Treffer - bitte genauer eingeben" statt "too many results".
- Added: Schule von Hand eintragen - WebUntis-Adresse aus dem Browser
  einsetzen, wenn die Suche die Schule nicht findet.
- Added: Scheitert das Python-Modul, steht der Grund jetzt auf der
  Anmeldeseite statt nur im Journal.
- Added: Requires auf pyotherside und python3-base.
