#!/usr/bin/env bash
# Lider sunucusunu Lider Ahenk kurulum sihirbazına hazırlar.
# Çalıştırılacağı yer: Pardus 25.1 SERVER (amd64), root olarak:  sudo bash sunucu.sh
# Kaynak: https://docs.liderahenk.org.tr/installation/lider/lider/
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Root olarak çalıştırın: sudo bash $0" >&2
    exit 1
fi

# Sürüm denetimi (uyarı verir, durdurmaz)
. /etc/os-release
echo "Sistem: ${PRETTY_NAME}"
if [[ "${ID:-}" != "pardus" || "${VERSION_ID:-}" != 25* ]]; then
    echo "UYARI: Resmi belge Pardus 25.1 SERVER öneriyor." >&2
    read -r -p "Yine de devam edilsin mi? [e/H] " ans
    [[ "${ans,,}" == "e" ]] || exit 1
fi

echo "==> Paket listesi güncelleniyor"
apt-get update

echo "==> SSH sunucusu ve dil paketi kuruluyor"
DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server locales

echo "==> SSH servisi etkinleştiriliyor"
systemctl enable --now ssh

# Belge: "Sunucu dilini İngilizce olarak ayarlayınız."
echo "==> Sistem dili en_US.UTF-8 yapılıyor"
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

echo
echo "Hazır. Sunucu IP adres(ler)i:"
hostname -I
echo
echo "Sonraki adımlar:"
echo "  1) Sunucuyu yeniden başlatın (dil ayarı için): sudo reboot"
echo "  2) Masaüstü makinede kurma.sh betiğini çalıştırın;"
echo "     sihirbaza bu IP'yi ve SSH kullanıcı bilgilerini girin."
echo "  3) Kurulum bitince tarayıcıdan: http://<sunucu-ip>:8080"
