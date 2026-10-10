#!/bin/bash
# Baut das Harmattan-Deb aus meego/. Ergebnis: ./debs/
# Die Tar-Archive macht Python: busybox-tar kann root:root nicht setzen.
set -e
cd "$(dirname "$0")/.."
VER=$(sed -n 's/^Version: //p' meego/DEBIAN/control)
mkdir -p debs
python3 - "$VER" <<'PY'
import os, sys, tarfile, subprocess, tempfile, shutil

version = sys.argv[1]
root = os.getcwd()
work = tempfile.mkdtemp(prefix='webuntis-deb.')


def als_root(info):
    # dpkg erwartet root:root; Verzeichniseintraege muessen mit, sonst legt
    # dpkg die Ordner nicht an.
    info.uid = info.gid = 0
    info.uname = info.gname = 'root'
    return info


def pack(ziel, eintraege, basis):
    with tarfile.open(ziel, 'w:gz', format=tarfile.USTAR_FORMAT) as tar:
        for name in eintraege:
            tar.add(os.path.join(basis, name), arcname='./' + name,
                    filter=als_root)


pack(os.path.join(work, 'data.tar.gz'), ['opt', 'usr'],
     os.path.join(root, 'meego'))

steuer = os.path.join(root, 'meego', 'DEBIAN')
with tarfile.open(os.path.join(work, 'control.tar.gz'), 'w:gz', format=tarfile.USTAR_FORMAT) as tar:
    tar.add(steuer, arcname='.', filter=als_root)

with open(os.path.join(work, 'debian-binary'), 'w') as f:
    f.write('2.0\n')

deb = os.path.join(root, 'debs', 'webuntis_%s_all.deb' % version)
if os.path.exists(deb):
    os.unlink(deb)
subprocess.check_call(['ar', 'rc', deb, 'debian-binary', 'control.tar.gz',
                       'data.tar.gz'], cwd=work)
shutil.rmtree(work)
print(deb)
PY
ls -l debs
