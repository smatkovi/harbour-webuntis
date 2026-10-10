#!/bin/bash
# Baut beide RPMs am Geraet (kein SDK noetig). Ergebnis: ./rpms/
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=$ROOT/rpms
TOP=$(mktemp -d /tmp/webuntis-rpm.XXXXXX)
mkdir -p "$OUT" "$TOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}

build() {   # $1 = Baumname (norm|secret), $2 = Spec
    rpmbuild -bb "$ROOT/rpm/$2" \
        --define "_topdir $TOP" \
        --define "tree $ROOT/$1" \
        --define "_binary_payload w6.xzdio" \
        >"$TOP/$1.log" 2>&1 || { tail -30 "$TOP/$1.log"; exit 1; }
    cp "$TOP"/RPMS/noarch/*.rpm "$OUT"/ 2>/dev/null || true
    rm -f "$TOP"/RPMS/noarch/*.rpm
}

build norm   harbour-webuntis.spec
build secret harbour-webuntis-secret.spec
rm -rf "$TOP"
ls -l "$OUT"
