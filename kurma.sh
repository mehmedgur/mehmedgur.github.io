#!/usr/bin/env bash
# Lider Ahenk kurulum sihirbazını (lider-ahenk-installer) indirir ve başlatır.
# Çalıştırılacağı yer: Pardus GNOME/XFCE masaüstü (normal kullanıcı, sudo yetkili):
#   bash kurulum-sihirbazi.sh
# Sihirbaz sunucuya SSH ile bağlanıp Lider, LDAP, veritabanı ve XMPP bileşenlerini kurar.
# Kaynak: https://github.com/Pardus-LiderAhenk/lider-ahenk-installer
#
# Not: Resmi belge pip için /usr/lib/python3.x/EXTERNALLY-MANAGED dosyasını siliyor.
# Bu betik sistemi bozmamak için onun yerine sanal ortam (venv) kullanır.
set -euo pipefail

BASE_DIR="${HOME}/liderahenk-kurulum"
REPO_DIR="${BASE_DIR}/lider-ahenk-installer"
VENV_DIR="${BASE_DIR}/venv"

if [[ $EUID -eq 0 ]]; then
    echo "Bu betiği root olarak değil, normal kullanıcıyla çalıştırın." >&2
    exit 1
fi

echo "==> Bağımlılıklar kuruluyor (sudo parolası istenebilir)"
sudo apt-get update
sudo apt-get install -y git openssh-client xterm \
    python3-paramiko python3-pyqt5 python3-pip python3-psutil python3-venv

mkdir -p "${BASE_DIR}"

echo "==> Kurulum sihirbazı indiriliyor / güncelleniyor"
if [[ -d "${REPO_DIR}/.git" ]]; then
    git -C "${REPO_DIR}" pull --ff-only
else
    git clone https://github.com/Pardus-LiderAhenk/lider-ahenk-installer.git "${REPO_DIR}"
fi

echo "==> Python sanal ortamı hazırlanıyor"
# --system-site-packages: apt ile gelen PyQt5, paramiko, psutil sanal ortamda da görünür
if [[ ! -x "${VENV_DIR}/bin/python3" ]]; then
    python3 -m venv --system-site-packages "${VENV_DIR}"
fi
"${VENV_DIR}/bin/pip" install --upgrade mysql-connector-python argon2-cffi

echo "==> Sihirbaz başlatılıyor"
cd "${REPO_DIR}/src"
exec "${VENV_DIR}/bin/python3" app.py
