#!/usr/bin/env bash
# =============================================================================
#  liderahenk-kur.sh — Lider Ahenk sunucusunu TEK SUNUCUYA tek komutla kurar
# -----------------------------------------------------------------------------
#  Kurulanlar : MariaDB · OpenLDAP · ejabberd (XMPP) · Tomcat + Lider 3.5 · guacd
#  Hedef OS   : Pardus 25.x Server (İngilizce kurulum), amd64
#
#  Kaynak: Resmi kurulum aracı github.com/Pardus-LiderAhenk/lider-ahenk-installer
#  (commit 69c03a0, 10.08.2026). O araç ayrı bir masaüstünden SSH ile sunucuya
#  bağlanıp komut çalıştırır. Bu script aynı adımları sunucunun içinde,
#  arayüzsüz yapar. Her bölümün başında hangi resmi dosyadan alındığı yazar.
#
#  Kullanım:
#     sudo bash liderahenk-kur.sh             # birkaç soru sorar, gerisi otomatik
#     sudo bash liderahenk-kur.sh --yes       # hiç soru sormaz (varsayılan/ortam)
#     sudo bash liderahenk-kur.sh --config ayarlar.conf --yes
#
#  Tekrar çalıştırılabilir: tamamlanan adımlar /var/lib/liderahenk-kur/ altında
#  işaretlenir ve atlanır. Şifreler /root/liderahenk-bilgiler.txt (600) içindedir.
# =============================================================================
set -Eeuo pipefail
umask 027

SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/liderahenk-kur.log"
STATE_DIR="/var/lib/liderahenk-kur"
CRED_FILE="/root/liderahenk-bilgiler.txt"
ENV_FILE="${STATE_DIR}/kurulum.env"     # üretilen şifreler (yeniden çalıştırmada aynısı kullanılır)
WORK_DIR="${STATE_DIR}/tmp"

# ---- Resmi kurulum aracındaki sabitler -------------------------------------
# settings_page.py: depo adresi ve anahtarı
LA_REPO_URL="https://repo.liderahenk.org.tr/liderahenk"
LA_REPO_SUITE="stable main"
LA_REPO_KEY_URL="https://repo.liderahenk.org.tr/liderahenk-archive-keyring.asc"
# api/lider/lider.py: Tomcat ve Lider WAR
TOMCAT_VERSION="10.1.55"
TOMCAT_URL="https://liderahenk.org.tr/downloads/v3.5/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_SHA512_URL="https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz.sha512"
LIDER_WAR_URL="https://liderahenk.org.tr/downloads/v3.5/ROOT.war"
# api/ejabberd/ejabberd.py: depodaki sabit sürüm ve kurulum yolları
EJABBERD_PKG_VERSION="19.09.1-0"
EJABBERD_HOME="/opt/ejabberd-19.09.1"
EJABBERD_CONF_DIR="/opt/ejabberd/conf"
# settings_page.py get_params(): sabit değerler
DB_NAME="lidermysdb"
XMPP_LIDER_USER="lider_sunucu"
XMPP_ADMIN_USER="admin"

# ---- Kullanıcı ayarları (ortam değişkeni veya --config ile verilebilir) -----
LIDER_IP="${LIDER_IP:-}"                       # boşsa otomatik bulunur
LDAP_DOMAIN="${LDAP_DOMAIN:-}"                 # ör. kurum.local → dc=kurum,dc=local
LDAP_ORG="${LDAP_ORG:-}"                       # boşsa alan adının ilk parçası
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"           # LDAP admin (+cn=config) — boşsa üretilir
CONSOLE_USER="${CONSOLE_USER:-lider_admin}"    # Lider web arayüzü kullanıcısı
CONSOLE_PASSWORD="${CONSOLE_PASSWORD:-}"       # boşsa üretilir
CONSOLE_MAIL="${CONSOLE_MAIL:-}"
XMPP_DOMAIN="${XMPP_DOMAIN:-im.liderahenk.org}" # resmi araçta sabit
FS_USER="${FS_USER:-liderfs}"                  # dosya sunucusu (SSH) kullanıcısı
DB_REMOTE="${DB_REMOTE:-0}"                    # 1: MariaDB'yi ağa aç (ayrı sunucu senaryosu)
STRICT_REPO="${STRICT_REPO:-0}"                # 1: depo imzası doğrulanamazsa dur
SKIP_TOMCAT_VERIFY="${SKIP_TOMCAT_VERIFY:-0}"  # 1: Tomcat SHA512 eşleşmezse yine de devam et
FORCE_LDAP="${FORCE_LDAP:-0}"                  # 1: mevcut slapd verisini SİLİP yeniden kur
ASSUME_YES=0

# =============================================================================
#  Yardımcılar
# =============================================================================
if [[ -t 1 ]]; then C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_B=$'\e[1;34m'; C_0=$'\e[0m'
else C_R=""; C_G=""; C_Y=""; C_B=""; C_0=""; fi

log()  { printf '%s [BİLGİ] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; printf '%s•%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s [UYARI] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; printf '%s! %s%s\n' "$C_Y" "$*" "$C_0" >&2; }
die()  { printf '%s [HATA] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; printf '%s✗ %s%s\n' "$C_R" "$*" "$C_0" >&2; exit 1; }
step() { printf '\n%s==> %s%s\n' "$C_B" "$*" "$C_0"; printf '\n%s ==> %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; }

# Komutu çalıştır, çıktısını log'a yaz
run() { printf '%s $ %s\n' "$(date '+%T')" "$*" >>"$LOG_FILE"; "$@" >>"$LOG_FILE" 2>&1; }

on_error() {
  local rc=$? line=${1:-?}
  printf '%s [HATA] satır %s, çıkış kodu %s: %s\n' "$(date '+%F %T')" "$line" "$rc" "${BASH_COMMAND}" >>"$LOG_FILE"
  printf '\n%s✗ Kurulum satır %s civarında durdu (kod %s).%s\n' "$C_R" "$line" "$rc" "$C_0" >&2
  printf '  Ayrıntı: %s\n  Sorunu giderip script'"'"'i tekrar çalıştırın; tamamlanan adımlar atlanır.\n' "$LOG_FILE" >&2
}
trap 'on_error $LINENO' ERR

done_mark() { touch "${STATE_DIR}/$1.done"; }
is_done()   { [[ -f "${STATE_DIR}/$1.done" ]]; }

apt_install() { DEBIAN_FRONTEND=noninteractive run apt-get install -y --no-install-recommends "$@"; }

genpass() { python3 -c 'import secrets,string;a=string.ascii_letters+string.digits;print("".join(secrets.choice(a) for _ in range(24)))'; }

# Şifreler LDIF, YAML, SQL ve properties dosyalarına yazıldığı için güvenli karakter kümesi
valid_pass()   { [[ "$1" =~ ^[A-Za-z0-9._@%+=:,~^-]{10,}$ ]]; }
valid_domain() { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; }
valid_user()   { [[ "$1" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]]; }
valid_ip()     { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }

ask() { # ask DEĞİŞKEN "Soru" varsayılan
  local __var=$1 __q=$2 __def=${3:-} __ans
  if (( ASSUME_YES )) || [[ ! -t 0 ]]; then printf -v "$__var" '%s' "$__def"; return; fi
  read -r -p "  ${__q} [${__def}]: " __ans || true
  printf -v "$__var" '%s' "${__ans:-$__def}"
}

usage() {
  sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'
Ortam değişkenleri / config anahtarları:
  LIDER_IP LDAP_DOMAIN LDAP_ORG ADMIN_PASSWORD CONSOLE_USER CONSOLE_PASSWORD
  CONSOLE_MAIL XMPP_DOMAIN FS_USER DB_REMOTE STRICT_REPO SKIP_TOMCAT_VERIFY FORCE_LDAP
EOF
}

# =============================================================================
#  Argümanlar
# =============================================================================
while (( $# )); do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    -c|--config)
      [[ -n "${2:-}" && -f "$2" ]] || { echo "Config dosyası bulunamadı: ${2:-}" >&2; exit 2; }
      # shellcheck disable=SC1090
      source "$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Bilinmeyen seçenek: $1 (--help)" >&2; exit 2 ;;
  esac
  shift
done

# =============================================================================
#  0) Ön kontroller  — docs: installation/lider/systemRequirements.md
# =============================================================================
[[ $EUID -eq 0 ]] || { echo "Bu script root olarak çalışmalı: sudo bash $0" >&2; exit 1; }
mkdir -p "$STATE_DIR" "$WORK_DIR"; chmod 700 "$STATE_DIR"
touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
export LC_ALL=C.UTF-8 LANG=C.UTF-8
step "Lider Ahenk tek sunucu kurulumu v${SCRIPT_VERSION} — log: $LOG_FILE"

command -v systemctl >/dev/null || die "systemd bulunamadı."
[[ "$(dpkg --print-architecture)" == "amd64" ]] || die "Yalnızca amd64 desteklenir (Lider deposu arch=amd64)."

# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  pardus)
    [[ "${VERSION_ID%%.*}" -ge 25 ]] || die "Pardus ${VERSION_ID} desteklenmiyor. Lider 3.5 OpenJDK 21 ister; Pardus 25.1 Server kullanın."
    ;;
  debian)
    [[ "${VERSION_ID%%.*}" -ge 13 ]] || die "Debian ${VERSION_ID:-?} desteklenmiyor (OpenJDK 21 için Debian 13 gerekir)."
    warn "Resmi olarak desteklenen sistem Pardus Server'dır; Debian ${VERSION_ID} üzerinde test edilmemiş olabilir."
    ;;
  *) die "Desteklenmeyen işletim sistemi: ${PRETTY_NAME:-bilinmiyor}. Pardus 25.1 Server kullanın." ;;
esac

# Donanım: üretim için 4 CPU / 8 GB / 50 GB, test için 2 / 4 / 20
CPU=$(nproc); RAM_MB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 )); DISK_GB=$(( $(df -Pk / | awk 'NR==2{print $4}') / 1024 / 1024 ))
log "Donanım: ${CPU} CPU, ${RAM_MB} MB RAM, / üzerinde ${DISK_GB} GB boş"
(( CPU >= 2 && RAM_MB >= 3500 && DISK_GB >= 15 )) || die "Asgari test ortamı gereksinimi karşılanmıyor (2 CPU, 4 GB RAM, 20 GB disk)."
(( CPU >= 4 && RAM_MB >= 7500 && DISK_GB >= 45 )) || warn "Üretim önerisinin (4 CPU, 8 GB RAM, 50 GB disk) altındasınız; test ortamı için yeterli."

[[ "$(locale 2>/dev/null | awk -F= '/^LANG=/{print $2}')" == en* || "${LANG}" == C.* ]] \
  || warn "Belgeler sunucu dilinin İngilizce olmasını istiyor."

# =============================================================================
#  Ayarların toplanması
# =============================================================================
# Daha önce üretilmiş şifreler varsa onları yeniden kullan (idempotent)
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  log "Önceki çalıştırmanın ayarları yüklendi: $ENV_FILE"
fi

if [[ -z "$LIDER_IP" ]]; then
  LIDER_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)
  [[ -n "$LIDER_IP" ]] || LIDER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

if [[ ! -f "$ENV_FILE" ]]; then
  printf '\n%sBirkaç bilgi gerekiyor (Enter = köşeli parantezdeki değer):%s\n' "$C_B" "$C_0"
  ask LIDER_IP     "Sunucu IP adresi (istemciler buna bağlanacak)" "$LIDER_IP"
  ask LDAP_DOMAIN  "LDAP alan adı (ör. kurum.local)"               "${LDAP_DOMAIN:-liderahenk.local}"
  ask CONSOLE_USER "Lider arayüz kullanıcı adı"                    "$CONSOLE_USER"
  ask CONSOLE_MAIL "Lider arayüz kullanıcısının e-postası"         "${CONSOLE_MAIL:-${CONSOLE_USER}@${LDAP_DOMAIN}}"
fi

LDAP_DOMAIN=${LDAP_DOMAIN,,}
valid_ip "$LIDER_IP"         || die "Geçersiz IP: '$LIDER_IP' (LIDER_IP=... ile verin)."
valid_domain "$LDAP_DOMAIN"  || die "Geçersiz alan adı: '$LDAP_DOMAIN' (ör. kurum.local)."
valid_domain "$XMPP_DOMAIN"  || die "Geçersiz XMPP alan adı: '$XMPP_DOMAIN'."
valid_user "$CONSOLE_USER"   || die "Geçersiz arayüz kullanıcı adı: '$CONSOLE_USER'."
valid_user "$FS_USER"        || die "Geçersiz dosya sunucusu kullanıcı adı: '$FS_USER'."
LDAP_ORG=${LDAP_ORG:-${LDAP_DOMAIN%%.*}}
CONSOLE_MAIL=${CONSOLE_MAIL:-${CONSOLE_USER}@${LDAP_DOMAIN}}

# Resmi araç tüm şifreleri tek "Sistem Admin Parolası"na eşitler; burada her
# bileşen ayrı, rastgele şifre alır (LDAP admin ile cn=config aynı kalır).
ADMIN_PASSWORD=${ADMIN_PASSWORD:-$(genpass)}
CONSOLE_PASSWORD=${CONSOLE_PASSWORD:-$(genpass)}
DB_PASSWORD=${DB_PASSWORD:-$(genpass)}
XMPP_ADMIN_PASSWORD=${XMPP_ADMIN_PASSWORD:-$(genpass)}
XMPP_LIDER_PASSWORD=${XMPP_LIDER_PASSWORD:-$(genpass)}
FS_PASSWORD=${FS_PASSWORD:-$(genpass)}
JWT_SECRET=${JWT_SECRET:-$(python3 -c 'import secrets;print(secrets.token_urlsafe(96))')}
for p in ADMIN_PASSWORD CONSOLE_PASSWORD DB_PASSWORD XMPP_ADMIN_PASSWORD XMPP_LIDER_PASSWORD FS_PASSWORD; do
  valid_pass "${!p}" || die "$p en az 10 karakter olmalı ve yalnızca A-Z a-z 0-9 . _ @ % + = : , ~ ^ - içermeli."
done

# DN'ler: liderahenk.local → dc=liderahenk,dc=local (resmi base_dn_parse ile aynı)
BASE_DN=$(awk -F. '{for(i=1;i<=NF;i++) printf "%sdc=%s", (i>1?",":""), $i}' <<<"$LDAP_DOMAIN")
ADMIN_DN="cn=admin,${BASE_DN}"
CONFIG_DN="cn=admin,cn=config"

# Ayarları kalıcı yap (root-only)
( umask 077; cat >"$ENV_FILE" <<EOF
LIDER_IP='$LIDER_IP'
LDAP_DOMAIN='$LDAP_DOMAIN'
LDAP_ORG='$LDAP_ORG'
CONSOLE_USER='$CONSOLE_USER'
CONSOLE_MAIL='$CONSOLE_MAIL'
XMPP_DOMAIN='$XMPP_DOMAIN'
FS_USER='$FS_USER'
ADMIN_PASSWORD='$ADMIN_PASSWORD'
CONSOLE_PASSWORD='$CONSOLE_PASSWORD'
DB_PASSWORD='$DB_PASSWORD'
XMPP_ADMIN_PASSWORD='$XMPP_ADMIN_PASSWORD'
XMPP_LIDER_PASSWORD='$XMPP_LIDER_PASSWORD'
FS_PASSWORD='$FS_PASSWORD'
JWT_SECRET='$JWT_SECRET'
EOF
)

printf '\n  IP: %s | LDAP: %s (%s) | Arayüz: %s | XMPP: %s\n' "$LIDER_IP" "$LDAP_DOMAIN" "$BASE_DN" "$CONSOLE_USER" "$XMPP_DOMAIN"
if (( ! ASSUME_YES )) && [[ -t 0 ]] && ! is_done base; then
  read -r -p "  Kurulum başlasın mı? [E/h]: " ok || true
  [[ "${ok:-E}" =~ ^[EeYy]$ ]] || die "İptal edildi."
fi

# Erlang (ejabberd) için makine adının çözülebilmesi gerekir
if ! getent hosts "$(hostname)" >/dev/null; then
  echo "127.0.1.1 $(hostname)" >>/etc/hosts
  log "/etc/hosts dosyasına $(hostname) eklendi"
fi

# =============================================================================
#  1) Temel paketler
# =============================================================================
if ! is_done base; then
  step "1/7 Temel paketler"
  run apt-get update
  apt_install ca-certificates curl gnupg debconf-utils openssl python3 python3-argon2 \
              iproute2 sshpass rsync openssh-server
  done_mark base
fi

# =============================================================================
#  2) Lider Ahenk deposu  — settings_page.py + docs/installation/ahenk/ahenk.md
#     Resmi araç "deb [trusted=yes] ..." kullanıyor (imza doğrulaması kapalı).
#     Burada önce imzalı (signed-by) denenir; olmazsa uyarıyla resmi davranışa döner.
# =============================================================================
if ! is_done repo; then
  step "2/7 Lider Ahenk paket deposu"
  KEYRING=/usr/share/keyrings/liderahenk-archive-keyring.asc
  LIST=/etc/apt/sources.list.d/liderahenk.list
  rm -f /etc/apt/sources.list.d/liderahenk*.list
  if run curl -fsSL --retry 3 -o "$KEYRING" "$LA_REPO_KEY_URL" && grep -q "BEGIN PGP PUBLIC KEY" "$KEYRING"; then
    chmod 644 "$KEYRING"
    echo "deb [arch=amd64 signed-by=${KEYRING}] ${LA_REPO_URL} ${LA_REPO_SUITE}" >"$LIST"
  else
    : >"$LIST"
  fi
  APT_OUT=$(apt-get update 2>&1 || true); echo "$APT_OUT" >>"$LOG_FILE"
  if [[ ! -s "$LIST" ]] || grep -Eqi 'repo\.liderahenk.*(NO_PUBKEY|not signed|EXPKEYSIG|BADSIG|is not signed)|(NO_PUBKEY|not signed|EXPKEYSIG|BADSIG).*liderahenk' <<<"$APT_OUT"; then
    (( STRICT_REPO )) && die "Lider Ahenk deposunun imzası doğrulanamadı (STRICT_REPO=1)."
    warn "Depo imzası doğrulanamadı; resmi kurulum aracı gibi [trusted=yes] ile devam ediliyor."
    echo "deb [arch=amd64 trusted=yes] ${LA_REPO_URL} ${LA_REPO_SUITE}" >"$LIST"
    run apt-get update
  fi
  apt-cache policy ejabberd | grep -q "$EJABBERD_PKG_VERSION" \
    || die "Lider deposunda ejabberd ${EJABBERD_PKG_VERSION} bulunamadı. Depo erişimini kontrol edin: ${LA_REPO_URL}"
  apt-cache show openjdk-21-jdk-headless >/dev/null 2>&1 \
    || die "openjdk-21-jdk-headless paketi bulunamadı (Pardus 25 depoları gerekli)."
  done_mark repo
fi

# =============================================================================
#  3) MariaDB  — api/database/mariadb.py
#     Farklar: root yerine ayrı 'lider' kullanıcısı; root@'%' açılmaz;
#     varsayılan olarak yalnızca 127.0.0.1 dinlenir (DB_REMOTE=1 ile açılır).
# =============================================================================
if ! is_done mariadb; then
  step "3/7 MariaDB"
  apt_install mariadb-server
  run systemctl enable --now mariadb
  mysql -uroot <<SQL >>"$LOG_FILE" 2>&1
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS 'lider'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS 'lider'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER 'lider'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER 'lider'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO 'lider'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO 'lider'@'127.0.0.1';
FLUSH PRIVILEGES;
CREATE TABLE IF NOT EXISTS \`${DB_NAME}\`.c_config (
  config_id INT NOT NULL, create_date VARCHAR(45) NOT NULL, modify_date VARCHAR(45) NULL,
  name VARCHAR(45) NOT NULL, value LONGTEXT NULL, PRIMARY KEY (config_id));
SQL
  if (( DB_REMOTE )); then
    sed -i 's/^\s*bind-address/#&/' /etc/mysql/mariadb.conf.d/50-server.cnf
    mysql -uroot -e "CREATE USER IF NOT EXISTS 'lider'@'%' IDENTIFIED BY '${DB_PASSWORD}'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO 'lider'@'%'; FLUSH PRIVILEGES;"
    run systemctl restart mariadb
    warn "MariaDB ağa açıldı (DB_REMOTE=1). 3306 portunu güvenlik duvarında yalnızca gerekli adreslere açın."
  fi
  done_mark mariadb
fi

# =============================================================================
#  4) OpenLDAP  — api/ldap/openldap.py + conf/ldapconfig_temp + conf/*.ldif
#     Düzeltme: resmi betik overlay'leri var olmayan olcDatabase={2}mdb'ye
#     eklemeye çalışıyor; burada doğru veritabanına ({1}mdb) eklenir.
# =============================================================================
ldap_cfg()  { ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// "$@" 2>>"$LOG_FILE"; }
ldap_mod()  { ldapmodify -Q -Y EXTERNAL -H ldapi:/// >>"$LOG_FILE" 2>&1; }

if ! is_done ldap; then
  step "4/7 OpenLDAP"
  if dpkg -s slapd >/dev/null 2>&1 && [[ -d /var/lib/ldap ]] && [[ -n "$(ls -A /var/lib/ldap 2>/dev/null)" ]] && (( ! FORCE_LDAP )); then
    die "Bu sunucuda zaten bir OpenLDAP veritabanı var. Silinip yeniden kurulması için FORCE_LDAP=1 verin (VERİ KAYBOLUR)."
  fi
  debconf-set-selections <<EOF
slapd slapd/password1 password ${ADMIN_PASSWORD}
slapd slapd/password2 password ${ADMIN_PASSWORD}
slapd slapd/internal/adminpw password ${ADMIN_PASSWORD}
slapd slapd/internal/generated_adminpw password ${ADMIN_PASSWORD}
slapd slapd/no_configuration boolean false
slapd slapd/invalid_config boolean true
slapd slapd/domain string ${LDAP_DOMAIN}
slapd shared/organization string ${LDAP_ORG}
slapd slapd/backend select MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
EOF
  apt_install slapd ldap-utils
  DEBIAN_FRONTEND=noninteractive run dpkg-reconfigure slapd
  run systemctl enable --now slapd

  MDB_DN=$(ldap_cfg -b cn=config "(olcSuffix=${BASE_DN})" dn | awk '/^dn: /{print $2; exit}')
  [[ -n "$MDB_DN" ]] || die "slapd veritabanı (${BASE_DN}) oluşturulamadı."
  log "LDAP veritabanı: $MDB_DN"
  CONFIG_HASH=$(slappasswd -h '{SSHA}' -s "$ADMIN_PASSWORD")
  ADMIN_HASH=$(slappasswd -h '{SSHA}' -s "$ADMIN_PASSWORD")

  # cn=config ve veritabanı yönetici şifreleri, arama limiti
  ldap_mod <<EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: ${CONFIG_DN}
-
replace: olcRootPW
olcRootPW: ${CONFIG_HASH}

dn: ${MDB_DN}
changetype: modify
replace: olcRootDN
olcRootDN: ${ADMIN_DN}
-
replace: olcRootPW
olcRootPW: ${ADMIN_HASH}

dn: cn=config
changetype: modify
replace: olcAuthzRegexp
olcAuthzRegexp: {0}uid=([^,]*),cn=[^,]*,cn=auth  ldap:///${BASE_DN}??sub?(uid=\$1)
-
replace: olcSizeLimit
olcSizeLimit: 10000
EOF

  # Modüller: unique, ppolicy, memberof (+ argon2 varsa)
  MOD_DN=$(ldap_cfg -b cn=config '(objectClass=olcModuleList)' dn | awk '/^dn: /{print $2; exit}')
  HAVE_MODS=$(ldap_cfg -b "$MOD_DN" -s base olcModuleLoad | awk '/^olcModuleLoad:/{print $2}')
  WANT_MODS=(unique ppolicy memberof)
  ARGON2=0
  if compgen -G "/usr/lib/ldap/argon2.so*" >/dev/null; then WANT_MODS+=(argon2); ARGON2=1
  else warn "OpenLDAP argon2 modülü yok; arayüz şifresi {SSHA} ile saklanacak."; fi
  for m in "${WANT_MODS[@]}"; do
    grep -Eq "(^|\})${m}(\.la)?$" <<<"$HAVE_MODS" && continue
    printf 'dn: %s\nchangetype: modify\nadd: olcModuleLoad\nolcModuleLoad: %s\n' "$MOD_DN" "$m" | ldap_mod
  done

  # Overlay'ler
  HAVE_OV=$(ldap_cfg -b "$MDB_DN" -s one '(objectClass=olcOverlayConfig)' olcOverlay | awk '/^olcOverlay:/{print $2}')
  grep -q 'ppolicy' <<<"$HAVE_OV" || ldap_mod <<EOF
dn: olcOverlay=ppolicy,${MDB_DN}
changetype: add
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: ppolicy
olcPPolicyDefault: cn=Default Password Policy,ou=Policies,ou=Groups,${BASE_DN}
olcPPolicyHashCleartext: FALSE
olcPPolicyUseLockout: FALSE
olcPPolicyForwardUpdates: FALSE
EOF
  grep -q 'unique' <<<"$HAVE_OV" || ldap_mod <<EOF
dn: olcOverlay=unique,${MDB_DN}
changetype: add
objectClass: olcOverlayConfig
objectClass: olcUniqueConfig
olcOverlay: unique
olcUniqueAttribute: uid
EOF
  grep -q 'memberof' <<<"$HAVE_OV" || ldap_mod <<EOF
dn: olcOverlay=memberof,${MDB_DN}
changetype: add
objectClass: olcOverlayConfig
objectClass: olcMemberOf
olcOverlay: memberof
EOF

  # Şemalar — conf/liderahenk.ldif ve conf/sudo.ldif (birebir)
  if ! ldap_cfg -b cn=schema,cn=config '(cn=*liderahenk)' dn | grep -q liderahenk; then
    ldapadd -Q -Y EXTERNAL -H ldapi:/// >>"$LOG_FILE" 2>&1 <<'EOF'
dn: cn=liderahenk,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: liderahenk
olcAttributeTypes: {0}( 2.4.2.42.1.9.7.9.0.9.7.2 NAME 'liderServiceAddress' SUP description SINGLE-VALUE )
olcAttributeTypes: {1}( 2.4.2.42.1.9.7.9.0.9.7.1 NAME 'liderPrivilege' SUP description )
olcAttributeTypes: {2}( 2.4.2.42.1.9.7.9.0.9.7.3 NAME 'liderDeviceObjectClassName' SUP objectClass SINGLE-VALUE )
olcAttributeTypes: {3}( 2.4.2.42.1.9.7.9.0.9.7.4 NAME 'liderUserObjectClassName' SUP objectClass SINGLE-VALUE )
olcAttributeTypes: {4}( 2.4.2.42.1.9.7.9.0.9.7.5 NAME 'liderUserIdentityAttributeName' SUP description SINGLE-VALUE )
olcAttributeTypes: {5}( 2.4.2.42.1.9.7.9.0.9.7.6 NAME 'liderAhenkOwnerAttributeName' SUP description SINGLE-VALUE )
olcAttributeTypes: {6}( 2.4.2.42.1.9.7.9.0.9.7.7 NAME 'liderDeviceOSType' SUP description )
olcAttributeTypes: {7}( 2.4.2.42.1.9.7.9.0.9.7.8 NAME 'liderGroupType' SUP description )
olcObjectClasses: {0}( 2.4.2.42.1.9.7.8.1.1.6.1 NAME 'pardusLiderAhenkConfig' STRUCTURAL MUST ( liderServiceAddress $ cn ) MAY ( liderAhenkOwnerAttributeName $ liderDeviceObjectClassName $ liderUserIdentityAttributeName $ liderUserObjectClassName ) )
olcObjectClasses: {1}( 2.4.2.42.1.9.7.8.1.1.6.4 NAME 'pardusAccount' AUXILIARY MUST ( uid $ userPassword ) )
olcObjectClasses: {2}( 2.4.2.42.1.9.7.8.1.1.6.3 NAME 'pardusDevice' AUXILIARY MUST ( cn $ uid $ userPassword $ owner ) MAY (liderDeviceOSType) )
olcObjectClasses: {3}( 2.4.2.42.1.9.7.8.1.1.6.2 NAME 'pardusLider' AUXILIARY MAY ( liderPrivilege $ liderGroupType ))
EOF
  fi
  if ! ldap_cfg -b cn=schema,cn=config '(cn=*sudo)' dn | grep -q sudo; then
    ldapadd -Q -Y EXTERNAL -H ldapi:/// >>"$LOG_FILE" 2>&1 <<'EOF'
dn: cn=sudo,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: sudo
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.1 NAME 'sudoUser' DESC 'User(s) who may  run sudo' EQUALITY caseExactIA5Match SUBSTR caseExactIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.2 NAME 'sudoHost' DESC 'Host(s) who may run sudo' EQUALITY caseExactIA5Match SUBSTR caseExactIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.3 NAME 'sudoCommand' DESC 'Command(s) to be executed by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.4 NAME 'sudoRunAs' DESC 'User(s) impersonated by sudo (deprecated)' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.5 NAME 'sudoOption' DESC 'Options(s) followed by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.6 NAME 'sudoRunAsUser' DESC 'User(s) impersonated by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.7 NAME 'sudoRunAsGroup' DESC 'Group(s) impersonated by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcObjectClasses: ( 1.3.6.1.4.1.15953.9.2.1 NAME 'sudoRole' SUP top STRUCTURAL DESC 'Sudoer Entries' MUST ( cn ) MAY ( sudoUser $ sudoHost $ sudoCommand $ sudoRunAs $ sudoRunAsUser $ sudoRunAsGroup $ sudoOption $ description ) )
EOF
  fi

  # Lider arayüz kullanıcısının şifresi — resmi araç argon2 (PasswordHasher) kullanır
  if (( ARGON2 )); then
    CONSOLE_HASH="{ARGON2}$(CP="$CONSOLE_PASSWORD" python3 -c 'import os;from argon2 import PasswordHasher;print(PasswordHasher().hash(os.environ["CP"]))')"
  else
    CONSOLE_HASH=$(slappasswd -h '{SSHA}' -s "$CONSOLE_PASSWORD")
  fi

  GROUPDN="ou=Groups,${BASE_DN}";  USERDN="ou=Users,${BASE_DN}";   AGENTDN="ou=Agents,${BASE_DN}"
  AGENTGROUPDN="ou=Agent,${GROUPDN}"; USERGROUPDN="ou=User,${GROUPDN}"; ROLEGROUPDN="ou=Role,${GROUPDN}"
  POLICYGROUPDN="ou=Policies,${GROUPDN}"
  ADMINGROUPDN="cn=adminGroups,${USERGROUPDN}"; DOMAINADMINGROUPDN="cn=domainAdminGroup,${USERGROUPDN}"

  # Dizin ağacı — ldapconfig_temp'teki girdilerin aynısı
  LDAP_TREE_OUT=$(ldapadd -c -x -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -H ldapi:/// 2>&1 <<EOF || true
dn: cn=liderAhenkConfig,${BASE_DN}
objectClass: pardusLiderAhenkConfig
liderServiceAddress: http://${LIDER_IP}:8181
cn: liderAhenkConfig

dn: ${USERDN}
objectClass: organizationalUnit
objectClass: pardusLider
objectClass: top
ou: Users
description: Users

dn: ${AGENTDN}
objectClass: organizationalUnit
objectClass: pardusLider
objectClass: top
ou: Agents
description: pardusDeviceGroup

dn: ${GROUPDN}
objectClass: organizationalUnit
objectClass: pardusLider
objectClass: top
ou: Groups

dn: ${USERGROUPDN}
objectClass: organizationalUnit
objectClass: pardusLider
objectClass: top
ou: User
description: User groups

dn: ${AGENTGROUPDN}
objectClass: organizationalUnit
objectClass: pardusLider
objectClass: top
ou: Agent
description: Agent groups

dn: cn=${CONSOLE_USER},${USERDN}
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: pardusAccount
objectClass: pardusLider
objectClass: person
objectClass: top
cn: ${CONSOLE_USER}
sn: ${CONSOLE_USER}
uid: ${CONSOLE_USER}
userPassword: ${CONSOLE_HASH}
mail: ${CONSOLE_MAIL}
liderPrivilege: [REPORT:ALL]
liderPrivilege: [TASK:${BASE_DN}:ALL]
liderPrivilege: ROLE_ADMIN
liderPrivilege: ROLE_USER

dn: ${ADMINGROUPDN}
objectClass: groupOfNames
objectClass: top
objectClass: pardusLider
member: ${ADMIN_DN}
member: cn=${CONSOLE_USER},${USERDN}
cn: adminGroups
liderPrivilege: ROLE_DOMAIN_ADMIN
description: User group authorized to write on LDAP

dn: ${DOMAINADMINGROUPDN}
objectClass: groupOfNames
objectClass: top
objectClass: pardusLider
member: cn=${CONSOLE_USER},${USERDN}
cn: domainAdminGroup
liderPrivilege: ROLE_DOMAIN_ADMIN
description: Domain admin group for register client

dn: ${ROLEGROUPDN}
objectClass: organizationalUnit
objectClass: top
objectClass: pardusLider
ou: Role
description: group of roles

dn: ${POLICYGROUPDN}
objectClass: organizationalUnit
objectClass: pardusLider
objectClass: top
ou: Policies
description: group of policy
EOF
)
  echo "$LDAP_TREE_OUT" >>"$LOG_FILE"
  if grep -E '^ldap_add: ' <<<"$LDAP_TREE_OUT" | grep -vq 'Already exists'; then
    die "LDAP dizin ağacı eklenirken hata oluştu (ayrıntı log'da)."
  fi

  # Erişim kuralları — resmi betiğin vardığı SON sıralamanın aynısı, tek seferde
  ldap_mod <<EOF
dn: ${MDB_DN}
changetype: modify
replace: olcAccess
olcAccess: to attrs=userPassword,shadowLastChange by group.exact="${ADMINGROUPDN}" write by anonymous auth by self write
olcAccess: to dn.subtree="${ROLEGROUPDN}" by dn.subtree="${AGENTDN}" read by * break
olcAccess: to dn.subtree="${USERDN}" by dn.subtree="${AGENTDN}" read by * break
olcAccess: to dn.subtree="${USERDN}" by group.exact="${ADMINGROUPDN}" write by * break
olcAccess: to dn.subtree="${AGENTDN}" by group.exact="${ADMINGROUPDN}" write by * break
olcAccess: to dn.subtree="${POLICYGROUPDN}" by group.exact="${ADMINGROUPDN}" write by * break
olcAccess: to dn.subtree="${USERGROUPDN}" by group.exact="${ADMINGROUPDN}" write by * break
olcAccess: to dn.subtree="${ROLEGROUPDN}" by group.exact="${ADMINGROUPDN}" write by * break
olcAccess: to dn.subtree="${AGENTGROUPDN}" by group.exact="${ADMINGROUPDN}" write by * break
olcAccess: to attrs=userPassword by self write by anonymous auth by * none
olcAccess: to dn.base="${BASE_DN}" by * read by * break
olcAccess: to dn.base="${USERDN}" by * read by * break
olcAccess: to dn.base="${AGENTDN}" by * read by * break
olcAccess: to dn.base="${POLICYGROUPDN}" by * read by * break
olcAccess: to dn.base="${GROUPDN}" by * read by * break
olcAccess: to dn.base="${USERGROUPDN}" by * read by * break
olcAccess: to dn.base="${AGENTGROUPDN}" by * read by * break
olcAccess: to dn.base="${ROLEGROUPDN}" by * read by * break
olcAccess: to * by self write
EOF
  printf 'dn: olcDatabase={-1}frontend,cn=config\nchangetype: modify\nreplace: olcSizeLimit\nolcSizeLimit: 5000\n' | ldap_mod
  run systemctl restart slapd
  ldapwhoami -x -D "cn=${CONSOLE_USER},${USERDN}" -w "$CONSOLE_PASSWORD" -H ldap://127.0.0.1 >>"$LOG_FILE" 2>&1 \
    || die "Arayüz kullanıcısı LDAP'a bağlanamıyor (şifre şeması sorunu olabilir)."
  done_mark ldap
fi

# =============================================================================
#  5) ejabberd (XMPP)  — api/ejabberd/ejabberd.py + conf/ejabberd.yml
# =============================================================================
EJCTL="${EJABBERD_HOME}/bin/ejabberdctl"
ej_wait() { for _ in $(seq 1 30); do "$EJCTL" status >/dev/null 2>&1 && return 0; sleep 2; done; return 1; }

if ! is_done ejabberd; then
  step "5/7 ejabberd (XMPP)"
  DEBIAN_FRONTEND=noninteractive run apt-get install -y "ejabberd=${EJABBERD_PKG_VERSION}"
  run apt-mark hold ejabberd
  [[ -x "$EJCTL" ]] || die "$EJCTL bulunamadı; ejabberd paketi beklenen yere kurulmamış."
  mkdir -p "$EJABBERD_CONF_DIR"

  # TLS sertifikası (paket üretmediyse kendinden imzalı oluştur)
  if [[ ! -s "${EJABBERD_CONF_DIR}/server.pem" ]]; then
    run openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -subj "/CN=${XMPP_DOMAIN}" \
      -addext "subjectAltName=DNS:${XMPP_DOMAIN},IP:${LIDER_IP}" \
      -keyout "${WORK_DIR}/ej.key" -out "${WORK_DIR}/ej.crt"
    cat "${WORK_DIR}/ej.key" "${WORK_DIR}/ej.crt" >"${EJABBERD_CONF_DIR}/server.pem"
    rm -f "${WORK_DIR}/ej.key"
  fi
  [[ -s "${EJABBERD_CONF_DIR}/cacert.pem" ]] || openssl x509 -in "${EJABBERD_CONF_DIR}/server.pem" -out "${EJABBERD_CONF_DIR}/cacert.pem"

  [[ -f "${EJABBERD_CONF_DIR}/ejabberd.yml" && ! -f "${EJABBERD_CONF_DIR}/ejabberd.yml.orig" ]] \
    && cp -a "${EJABBERD_CONF_DIR}/ejabberd.yml" "${EJABBERD_CONF_DIR}/ejabberd.yml.orig"
  cat >"${EJABBERD_CONF_DIR}/ejabberd.yml" <<EOF
# liderahenk-kur.sh tarafından resmi conf/ejabberd.yml şablonundan üretildi
hosts:
  - "${XMPP_DOMAIN}"
auth_method: ldap
auth_use_cache: false
ldap_servers:
  - "127.0.0.1"
ldap_port: 389
ldap_rootdn: "${ADMIN_DN}"
ldap_password: "${ADMIN_PASSWORD}"
ldap_base: "${BASE_DN}"
ldap_filter: "(|(objectClass=pardusDevice)(&(objectClass=pardusAccount)(objectClass=pardusLider)))"
host_config:
  "${XMPP_DOMAIN}":
    auth_method:
      - internal
      - ldap
      - anonymous
loglevel: 4
log_rotate_size: 10485760
log_rotate_date: ""
log_rotate_count: 1
log_rate_limit: 100
certfiles:
  - "${EJABBERD_CONF_DIR}/server.pem"
ca_file: "${EJABBERD_CONF_DIR}/cacert.pem"
listen:
  -
    port: 5222
    ip: "::"
    module: ejabberd_c2s
    max_stanza_size: 262144
    shaper: c2s_shaper
    access: c2s
    starttls_required: false
  -
    port: 5269
    ip: "::"
    module: ejabberd_s2s_in
    max_stanza_size: 524288
  -
    port: 5443
    ip: "::"
    module: ejabberd_http
    tls: true
    request_handlers:
      "/admin": ejabberd_web_admin
      "/api": mod_http_api
      "/bosh": mod_bosh
      "/captcha": ejabberd_captcha
      "/upload": mod_http_upload
      "/ws": ejabberd_http_ws
      "/oauth": ejabberd_oauth
    web_admin: true
  -
    port: 5280
    ip: "::"
    module: ejabberd_http
    request_handlers:
      "/admin": ejabberd_web_admin
      "/api": mod_http_api
      "/bosh": mod_bosh
      "/captcha": ejabberd_captcha
      "/upload": mod_http_upload
      "/ws": ejabberd_http_ws
      "/oauth": ejabberd_oauth
    web_admin: true
  -
    port: 1883
    ip: "::"
    module: mod_mqtt
    backlog: 1000
s2s_use_starttls: optional
acl:
  local:
    user_regexp: ""
  loopback:
    ip:
      - 127.0.0.0/8
      - ::1/128
      - ::FFFF:127.0.0.1/128
  admin:
    user:
      - "${XMPP_ADMIN_USER}@${XMPP_DOMAIN}"
access_rules:
  local:
    allow: local
  c2s:
    deny: blocked
    allow: all
  announce:
    allow: admin
  configure:
    allow: admin
  muc_create:
    allow: local
  pubsub_createnode:
    allow: local
  trusted_network:
    allow: loopback
api_permissions:
  "console commands":
    from:
      - ejabberd_ctl
    who: all
    what: "*"
  "admin access":
    who:
      access:
        allow:
          acl: loopback
          acl: admin
      oauth:
        scope: "ejabberd:admin"
        access:
          allow:
            acl: loopback
            acl: admin
    what:
      - "*"
      - "!stop"
      - "!start"
  "public commands":
    who:
      ip: 127.0.0.1/8
    what:
      - status
      - connected_users_number
shaper:
  normal: 1000
  fast: 50000
shaper_rules:
  max_user_sessions: 10
  max_user_offline_messages:
    5000: admin
    100: all
  c2s_shaper:
    none: admin
    normal: all
  s2s_shaper: fast
max_fsm_queue: 10000
acme:
   contact: "mailto:admin@server"
   ca_url: "https://acme-v01.api.letsencrypt.org"
modules:
  mod_adhoc: {}
  mod_admin_extra: {}
  mod_announce:
    access: announce
  mod_avatar: {}
  mod_blocking: {}
  mod_bosh: {}
  mod_caps: {}
  mod_carboncopy: {}
  mod_client_state: {}
  mod_configure: {}
  mod_disco: {}
  mod_fail2ban: {}
  mod_http_api: {}
  mod_http_upload:
    put_url: https://@HOST@:5443/upload
  mod_last: {}
  mod_mam:
    assume_mam_usage: true
    default: never
  mod_mqtt: {}
  mod_muc:
    access:
      - allow
    access_admin:
      - allow: admin
    access_create: muc_create
    access_persistent: muc_create
    access_mam:
      - allow
    default_room_options:
      allow_subscription: true
      mam: false
  mod_muc_admin: {}
  mod_offline:
    access_max_user_messages: max_user_offline_messages
  mod_ping: {}
  mod_privacy: {}
  mod_private: {}
  mod_proxy65:
    access: local
    max_connections: 5
  mod_pubsub:
    access_createnode: pubsub_createnode
    plugins:
      - flat
      - pep
    force_node_config:
      storage:bookmarks:
        access_model: whitelist
  mod_push: {}
  mod_push_keepalive: {}
  mod_register:
    ip_access: trusted_network
  mod_roster:
    versioning: true
  mod_s2s_dialback: {}
  mod_shared_roster: {}
  mod_stream_mgmt:
    resend_on_timeout: if_offline
  mod_vcard: {}
  mod_vcard_xupdate: {}
  mod_version:
    show_os: false
EOF
  chmod 640 "${EJABBERD_CONF_DIR}/ejabberd.yml" "${EJABBERD_CONF_DIR}/server.pem"
  chown -R ejabberd:ejabberd "$EJABBERD_CONF_DIR" 2>/dev/null || chown -R ejabberd "$EJABBERD_CONF_DIR"

  # systemd servisi (paketin kendi unit dosyası)
  "$EJCTL" stop >>"$LOG_FILE" 2>&1 || true
  if [[ -f "${EJABBERD_HOME}/bin/ejabberd.service" ]]; then
    cp "${EJABBERD_HOME}/bin/ejabberd.service" /etc/systemd/system/
    run systemctl daemon-reload
    run systemctl enable ejabberd.service
    run systemctl restart ejabberd.service
  else
    warn "ejabberd.service bulunamadı; ejabberdctl ile başlatılıyor (yeniden başlatmada otomatik açılmayabilir)."
    run "$EJCTL" start
  fi
  ej_wait || die "ejabberd başlamadı. Bakınız: /opt/ejabberd/logs/ ve $LOG_FILE"

  for pair in "${XMPP_ADMIN_USER}:${XMPP_ADMIN_PASSWORD}" "${XMPP_LIDER_USER}:${XMPP_LIDER_PASSWORD}"; do
    u=${pair%%:*}; p=${pair#*:}
    if "$EJCTL" check_account "$u" "$XMPP_DOMAIN" >/dev/null 2>&1; then
      run "$EJCTL" change_password "$u" "$XMPP_DOMAIN" "$p"
    else
      run "$EJCTL" register "$u" "$XMPP_DOMAIN" "$p"
    fi
  done
  done_mark ejabberd
fi

# =============================================================================
#  6) Lider yapılandırması (c_config)  — mariadb.py insert_to_config()
#     Lider tüm çalışma ayarlarını bu tablodaki tek JSON kaydından okur.
# =============================================================================
if ! is_done liderconfig; then
  step "6/7 Lider yapılandırması ve dosya sunucusu"

  # Dosya sunucusu: resmi araç sunucuya SSH ile bağlanan kullanıcıyı kullanır.
  # Burada ayrı, ayrıcalıksız bir kullanıcı oluşturulur.
  id "$FS_USER" >/dev/null 2>&1 || run useradd -m -s /bin/bash "$FS_USER"
  echo "${FS_USER}:${FS_PASSWORD}" | chpasswd
  FS_HOME=$(getent passwd "$FS_USER" | cut -d: -f6)
  install -d -o "$FS_USER" -g "$FS_USER" -m 755 "${FS_HOME}/agent-files" "${FS_HOME}/plugins"
  run systemctl enable --now ssh || true
  if sshd -T 2>/dev/null | grep -qi '^passwordauthentication no'; then
    warn "SSH'ta parola girişi kapalı. Lider dosya sunucusu ${FS_USER} kullanıcısıyla parola ile bağlanır; gerekirse sshd_config'e 'Match User ${FS_USER}' + 'PasswordAuthentication yes' ekleyin."
  fi

  CFG_JSON=$(LIDER_IP="$LIDER_IP" BASE_DN="$BASE_DN" ADMIN_DN="$ADMIN_DN" ADMIN_PASSWORD="$ADMIN_PASSWORD" \
    XMPP_DOMAIN="$XMPP_DOMAIN" XMPP_LIDER_USER="$XMPP_LIDER_USER" XMPP_LIDER_PASSWORD="$XMPP_LIDER_PASSWORD" \
    FS_USER="$FS_USER" FS_PASSWORD="$FS_PASSWORD" FS_HOME="$FS_HOME" python3 - <<'PY'
import json, os
e = os.environ
ip, base = e["LIDER_IP"], e["BASE_DN"]
fs = e["FS_HOME"]
p = {
  "adAdminPassword": "", "adAdminUserName": "", "adDomainName": "", "adHostName": "",
  "adIpAddress": "", "adPort": "", "adAdminUserFullDN": "",
  "agentLdapBaseDn": f"ou=Agents,{base}", "agentLdapIdAttribute": "cn", "agentLdapJidAttribute": "uid",
  "agentLdapObjectClasses": "pardusDevice,device",
  "ahenkGroupLdapBaseDn": f"ou=Agent,ou=Groups,{base}",
  "alarmCheckReport": None, "cronIntervalEntrySize": None, "cronTaskList": None,
  "disableLocalUser": False, "domainType": "LDAP", "entrySizeLimit": None,
  "fileServerAgentFilePath": f"{fs}/agent-files/{{0}}/",
  "fileServerAgreementPath": f"{fs}/sample-agreement.txt",
  "fileServerHost": ip, "fileServerPassword": e["FS_PASSWORD"],
  "fileServerPluginPath": f"{fs}/plugins/ahenk-{{0}}_{{1}}_amd64.deb",
  "fileServerPort": 22, "fileServerProtocol": "SSH", "fileServerUsername": e["FS_USER"],
  "groupLdapBaseDn": f"ou=Groups,{base}", "groupLdapObjectClasses": "groupOfNames",
  "hotDeploymentPath": None, "ldapAllowSelfSignedCert": False, "ldapEmailAttribute": "mail",
  "ldapMailNotifierAttributes": "cn, mail, departmentNumber, uid",
  "ldapPassword": e["ADMIN_PASSWORD"], "ldapPort": "389", "ldapRootDn": base,
  "ldapSearchAttributes": "cn,objectClass,uid,liderPrivilege", "ldapServer": ip,
  "ldapUseSsl": False, "ldapUsername": e["ADMIN_DN"], "liderLocale": "tr",
  "mailAddress": None, "mailCheckPolicyCompletionPeriod": None, "mailCheckTaskCompletionPeriod": None,
  "mailHost": None, "mailPassword": None, "mailSendOnPolicyCompletion": None,
  "mailSendOnTaskCompletion": None, "mailSmtpAuth": None, "mailSmtpConnTimeout": None,
  "mailSmtpPort": None, "mailSmtpSslEnable": None, "mailSmtpStartTlsEnable": None,
  "mailSmtpTimeout": None, "mailSmtpWriteTimeout": None,
  "roleLdapObjectClasses": "sudoRole", "taskManagerCheckFutureTask": None,
  "taskManagerFutureTaskCheckPeriod": None, "userAuthorizationEnabled": True,
  "userGroupLdapBaseDn": f"ou=User,ou=Groups,{base}", "userLdapBaseDn": f"ou=Users,{base}",
  "userLdapObjectClasses": "pardusAccount,pardusLider", "userLdapPrivilegeAttribute": "liderPrivilege",
  "userLdapRolesDn": f"ou=Role,ou=Groups,{base}", "userLdapUidAttribute": "uid",
  "xmppAllowSelfSignedCert": False, "xmppHost": ip, "xmppMaxRetryConnectionCount": 5,
  "xmppPacketReplayTimeout": 10000, "xmppPassword": e["XMPP_LIDER_PASSWORD"], "xmppPingTimeout": 300,
  "xmppPort": 5222, "xmppPresencePriority": 1, "xmppResource": "Smack",
  "xmppServiceName": e["XMPP_DOMAIN"], "xmppUseCustomSsl": False, "xmppUseSsl": False,
  "xmppUsername": e["XMPP_LIDER_USER"], "xmppBoshAddress": f"http://{ip}:5280/bosh",
  "selectedRegistrationType": "DEFAULT", "sudoRoleType": "LDAP", "machineEventStatus": False,
  "machineEventDay": 0, "clientSize": 1, "adAllowSelfSignedCert": False, "adUseSSL": False,
  "adUseTLS": False, "ahenkRepoAddress": "null", "ahenkRepoKeyAddress": "null",
  "allowDynamicDNSUpdate": True, "allowVNCConnectionWithoutPermission": True,
  "clientSslPath": "null", "enableDelete4Directory": "null", "fileServerUrl": "null",
  "isTwoFactorEnabled": False, "mailPort": 587, "mailTlsEnabled": False, "otpExpiryDuration": 400000,
  "pardusRepoAddress": "", "pardusRepoComponent": "",
  "agentStatusCronJob": "0 * * * * ?", "taskCronJob": "0 */20 * * * ?",
}
s = json.dumps(p)
print(s.replace("\\", "\\\\").replace("'", "\\'"))
PY
)
  mysql -uroot "$DB_NAME" >>"$LOG_FILE" 2>&1 <<SQL
INSERT INTO c_config (config_id, create_date, modify_date, name, value)
VALUES (1, NOW(), NULL, 'liderConfigParams', '${CFG_JSON}')
ON DUPLICATE KEY UPDATE modify_date = NOW(), value = VALUES(value);
SQL
  done_mark liderconfig
fi

# =============================================================================
#  7) Tomcat + Lider 3.5  — api/lider/lider.py + conf/tomcat.service + conf/lider.properties
# =============================================================================
if ! is_done lider; then
  step "7/7 Java, Tomcat ve Lider"
  apt_install openjdk-21-jdk-headless
  JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
  getent group tomcat >/dev/null || run groupadd --system tomcat
  id tomcat >/dev/null 2>&1 || run useradd --system -s /bin/false -g tomcat -d /opt/tomcat tomcat

  TGZ="${WORK_DIR}/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
  run curl -fL --retry 3 --connect-timeout 30 -o "$TGZ" "$TOMCAT_URL"
  # Bütünlük: Apache'nin resmi SHA512 değeriyle karşılaştır (erişilebiliyorsa)
  if SUM=$(curl -fsSL --retry 2 "$TOMCAT_SHA512_URL" 2>/dev/null | awk '{print $1}') && [[ -n "$SUM" ]]; then
    if [[ "$(sha512sum "$TGZ" | awk '{print $1}')" != "$SUM" ]]; then
      (( SKIP_TOMCAT_VERIFY )) || die "Tomcat arşivinin SHA512 değeri Apache'nin yayınladığıyla uyuşmuyor. (Bilerek devam: SKIP_TOMCAT_VERIFY=1)"
      warn "Tomcat SHA512 uyuşmadı; SKIP_TOMCAT_VERIFY=1 olduğu için devam ediliyor."
    else
      log "Tomcat arşivi doğrulandı (SHA512)."
    fi
  else
    warn "Tomcat SHA512 değeri alınamadı; bütünlük doğrulaması yapılmadı."
  fi

  [[ -d /opt/tomcat/bin ]] && systemctl stop tomcat 2>/dev/null || true
  mkdir -p /opt/tomcat
  run tar xf "$TGZ" -C /opt/tomcat --strip-components=1
  rm -rf /opt/tomcat/webapps
  mkdir -p /opt/tomcat/webapps/files
  chgrp -R tomcat /opt/tomcat
  chmod -R g+r /opt/tomcat/conf; chmod g+x /opt/tomcat/conf
  chmod -R 755 /opt/tomcat/webapps
  chown -R tomcat /opt/tomcat/webapps /opt/tomcat/work /opt/tomcat/temp /opt/tomcat/logs

  cat >/etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat Web Application Container (Lider)
After=network.target mariadb.service slapd.service ejabberd.service

[Service]
Type=forking
Environment=JAVA_HOME=${JAVA_HOME}
Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid
Environment=CATALINA_HOME=/opt/tomcat
Environment=CATALINA_BASE=/opt/tomcat
Environment='CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC'
Environment='JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom'
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
User=tomcat
Group=tomcat
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  mkdir -p /etc/lider
  cat >/etc/lider/lider.properties <<EOF
################### DataSource Configuration ##########################
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver
spring.datasource.url=jdbc:mysql://127.0.0.1:3306/${DB_NAME}?useUnicode=yes&characterEncoding=UTF-8
spring.datasource.username=lider
spring.datasource.password=${DB_PASSWORD}

################### Hibernate Configuration ##########################
spring.datasource.initialization-mode=always
spring.main.banner-mode=off
logging.pattern.console=%clr(%d{yy-MM-dd E HH:mm:ss.SSS}){blue} %clr(%-5p) %clr(%logger{0}){blue} %clr(%m){faint}%n
spring.jpa.properties.hibernate.format_sql=true
spring.jpa.hibernate.ddl-auto=update
spring.jpa.properties.hibernate.current_session_context_class=org.springframework.orm.hibernate5.SpringSessionContext
logging.level.org.springframework.web= INFO
logging.level.org.hibernate= INFO
logging.level.org.hibernate.type.descriptor.sql.BasicBinder=ERROR
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQLDialect
spring.jpa.properties.hibernate.dialect.storage_engine=innodb
server.servlet.session.timeout=30m
spring.jackson.serialization.fail-on-empty-beans=false
################### Register Configuration ##########################
registrationSubscriber.class = default

################### Messaging Configuration ##########################
lider.messaging = xmpp

################### XMPP Configuration ##############################
xmpp.resource.name=Smack
xmpp.presence.priority=1

################### Plugin Configuration ############################
allow.connection.without.permission = true
lider.enableDelete4Directory = false

################### Lider Server Configuration ############################
jwt.secret = ${JWT_SECRET}
jwt.expiration = 3600
lider.url = http://${LIDER_IP}:8080

springdoc.swagger-ui.path=/api-docs
springdoc.swagger-ui.operationsSorter=method
springdoc.api-docs.resolve-schema-properties=true
springdoc.api-docs.enabled=false
springdoc.swagger-ui.enabled=false

refresh.token.expiry.seconds=86400
refresh.token.cleanup.batch-size =1000
refresh.token.cleanup.cron=0 * * * * *

# Resmi araç buraya "http://IP:8080" yazıyor; alan bir host adı beklediği ve
# guacd aynı sunucuda çalıştığı için 127.0.0.1 kullanıldı.
lider.guacamole.guacd.host=127.0.0.1
lider.guacamole.guacd.port=4822

spring.main.allow-circular-references=true
EOF
  chown root:tomcat /etc/lider /etc/lider/lider.properties
  chmod 750 /etc/lider; chmod 640 /etc/lider/lider.properties

  run curl -fL --retry 3 --connect-timeout 30 -o /opt/tomcat/webapps/ROOT.war "$LIDER_WAR_URL"
  chown -R tomcat:tomcat /opt/tomcat/webapps
  run systemctl daemon-reload
  run systemctl enable tomcat
  run systemctl restart tomcat

  # Uzak masaüstü (resmi araçta da hata olursa kurulum durmaz)
  apt_install guacd && run systemctl enable --now guacd || warn "guacd kurulamadı; uzak masaüstü özelliği çalışmayabilir."
  rm -f "$TGZ"
  done_mark lider
fi

# =============================================================================
#  Güvenlik duvarı — systemRequirements.md: 8080, 22, 5222, 5280, 3306, 389
# =============================================================================
PORTS=(22 389 5222 5280 8080); (( DB_REMOTE )) && PORTS+=(3306)
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  for p in "${PORTS[@]}"; do run ufw allow "${p}/tcp"; done
  log "ufw: ${PORTS[*]} portları açıldı."
else
  warn "Etkin bir ufw yok. Ağ güvenlik duvarınızda şu TCP portlarını açın: ${PORTS[*]}"
fi

# =============================================================================
#  Doğrulama
# =============================================================================
step "Kontroller"
FAIL=0
for s in mariadb slapd ejabberd tomcat; do
  if systemctl is-active --quiet "$s"; then log "$s çalışıyor"; else warn "$s ÇALIŞMIYOR (journalctl -u $s)"; FAIL=1; fi
done
ldapsearch -x -H ldap://127.0.0.1 -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -b "$BASE_DN" -s base dn >/dev/null 2>&1 \
  && log "LDAP sorgusu başarılı" || { warn "LDAP sorgusu başarısız"; FAIL=1; }
log "Lider web uygulaması açılıyor (ilk açılış birkaç dakika sürebilir)..."
CODE=000
for _ in $(seq 1 60); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:8080/" || true)
  [[ "$CODE" =~ ^(200|302|401)$ ]] && break; sleep 5
done
if [[ "$CODE" =~ ^(200|302|401)$ ]]; then log "Lider arayüzü yanıt veriyor (HTTP $CODE)"
else warn "Lider arayüzü 5 dakikada yanıt vermedi (HTTP $CODE). Log: /opt/tomcat/logs/catalina.out"; FAIL=1; fi

# =============================================================================
#  Erişim bilgileri
# =============================================================================
( umask 077; cat >"$CRED_FILE" <<EOF
Lider Ahenk kurulum bilgileri — $(date '+%F %T')
=====================================================
Lider arayüzü        : http://${LIDER_IP}:8080
  Kullanıcı / şifre  : ${CONSOLE_USER} / ${CONSOLE_PASSWORD}

LDAP                 : ldap://${LIDER_IP}:389   Base DN: ${BASE_DN}
  Yönetici           : ${ADMIN_DN} / ${ADMIN_PASSWORD}
  cn=config yönetici : ${CONFIG_DN} / ${ADMIN_PASSWORD}

XMPP (ejabberd)      : ${LIDER_IP}:5222   Servis adı: ${XMPP_DOMAIN}
  ${XMPP_ADMIN_USER}@${XMPP_DOMAIN} / ${XMPP_ADMIN_PASSWORD}
  ${XMPP_LIDER_USER}@${XMPP_DOMAIN} / ${XMPP_LIDER_PASSWORD}

MariaDB              : 127.0.0.1:3306   DB: ${DB_NAME}   Kullanıcı: lider / ${DB_PASSWORD}
Dosya sunucusu (SSH) : ${FS_USER}@${LIDER_IP} / ${FS_PASSWORD}

İstemci (Ahenk) kaydı: Pardus istemcide Lider deposunu ekleyip
  sudo apt install ahenk && sudo ahenk-register
  Sunucu adresi olarak ${LIDER_IP} girin.
EOF
)

printf '\n%s──────────────────────────────────────────────%s\n' "$C_B" "$C_0"
if (( FAIL )); then
  printf '%sKurulum bitti ama bazı kontroller başarısız. Log: %s%s\n' "$C_Y" "$LOG_FILE" "$C_0"
else
  printf '%sLider Ahenk kurulumu tamamlandı.%s\n' "$C_G" "$C_0"
fi
printf '  Arayüz  : http://%s:8080\n  Kullanıcı: %s\n  Tüm şifreler: %s (yalnızca root okuyabilir)\n' \
  "$LIDER_IP" "$CONSOLE_USER" "$CRED_FILE"
rm -rf "$WORK_DIR"
exit "$FAIL"
