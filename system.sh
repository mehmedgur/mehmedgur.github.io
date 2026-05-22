#!/bin/bash

################################################################################
# Pardus GNU/Linux 23 - İnteraktif Sistem Sağlık Script
# Makine: virci
# Versiyon: 3.0-INTERACTIVE-MENU
# Özellikler:
#   - Ana menü + Alt menüler (Interaktif)
#   - Her komut çalıştırılmadan önce onay sorusu
#   - Manuel çalıştırma (Tek tek seçim)
#   - Tümünü çalıştır seçeneği
#   - HTML + JSON raporlama
#   - Desktop seçim menüsü
################################################################################

set -u
SCRIPT_VERSION="3.0-INTERACTIVE-MENU"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP_FILE=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/var/log/system_health_reports"
LOG_FILE="$LOG_DIR/system_health_$TIMESTAMP_FILE.log"
HTML_REPORT="$LOG_DIR/report_$TIMESTAMP_FILE.html"
JSON_REPORT="$LOG_DIR/report_$TIMESTAMP_FILE.json"

mkdir -p "$LOG_DIR" 2>/dev/null

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# İstatistikler
CRITICAL_COUNT=0
WARNING_COUNT=0
INFO_COUNT=0
START_TIME=$(date +%s)

################################################################################
# UTILITY FONKSİYONLARI
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Bu script root yetkileriyle çalıştırılmalıdır!${NC}"
        echo "Kullanım: sudo bash $0"
        exit 1
    fi
}

ask_confirmation() {
    local cmd="$1"
    local desc="$2"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}Komutu Çalıştırmak Üzeresiniz:${NC}"
    echo ""
    echo -e "${CYAN}Açıklaması:${NC} $desc"
    echo -e "${CYAN}Komut:${NC} $cmd"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "Devam et? (E/H): " choice
    
    case $choice in
        [Ee]|[Ee][Vv][Ee][Tt])
            return 0
            ;;
        *)
            echo -e "${YELLOW}İptal edildi.${NC}"
            return 1
            ;;
    esac
}

execute_with_ask() {
    local cmd="$1"
    local desc="$2"
    
    if ask_confirmation "$cmd" "$desc"; then
        echo -e "\n${GREEN}[ÇALIŞTIRULUYOR]${NC} $desc\n"
        eval "$cmd" 2>&1 | tee -a "$LOG_FILE"
        echo ""
        ((INFO_COUNT++))
    fi
}

log_info() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[UYARI]${NC} $1" | tee -a "$LOG_FILE"
}

log_critical() {
    echo -e "${RED}[KRİTİK]${NC} $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

pause_screen() {
    read -p "Devam etmek için Enter'a basın..." -t 3
}

clear_screen() {
    clear
}

################################################################################
# KONTROL FONKSİYONLARI
################################################################################

menu_system_info() {
    clear_screen
    print_header "TEMEL SİSTEM BİLGİLERİ"
    
    echo -e "${MAGENTA}1)${NC} Makine Adı"
    echo -e "${MAGENTA}2)${NC} Dağıtım Bilgisi"
    echo -e "${MAGENTA}3)${NC} Kernel Versiyonu"
    echo -e "${MAGENTA}4)${NC} Sistem Açılış Süresi"
    echo -e "${MAGENTA}5)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1) execute_with_ask "hostname" "Makine adı sorgulanıyor" ;;
        2) execute_with_ask "cat /etc/os-release | grep PRETTY_NAME" "Dağıtım bilgisi alınıyor" ;;
        3) execute_with_ask "uname -r" "Kernel versiyonu sorgulanıyor" ;;
        4) execute_with_ask "uptime -p" "Sistem açılış süresi sorgulanıyor" ;;
        5)
            execute_with_ask "hostname" "Makine adı"
            execute_with_ask "cat /etc/os-release | grep PRETTY_NAME" "Dağıtım bilgisi"
            execute_with_ask "uname -r" "Kernel versiyonu"
            execute_with_ask "uptime -p" "Sistem açılış süresi"
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    menu_system_info
}

menu_cpu_info() {
    clear_screen
    print_header "CPU VE İŞLEMCİ"
    
    echo -e "${MAGENTA}1)${NC} CPU Bilgileri"
    echo -e "${MAGENTA}2)${NC} CPU Yükü"
    echo -e "${MAGENTA}3)${NC} Çekirdek Sayısı"
    echo -e "${MAGENTA}4)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1) execute_with_ask "lscpu" "CPU bilgileri gösteriliyor" ;;
        2) execute_with_ask "uptime" "CPU yükü gösteriliyor" ;;
        3) execute_with_ask "cat /proc/cpuinfo | grep processor | wc -l" "Çekirdek sayısı gösteriliyor" ;;
        4)
            execute_with_ask "lscpu" "CPU bilgileri"
            execute_with_ask "uptime" "CPU yükü"
            execute_with_ask "cat /proc/cpuinfo | grep processor | wc -l" "Çekirdek sayısı"
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    menu_cpu_info
}

menu_memory_info() {
    clear_screen
    print_header "BELLEK (RAM) BİLGİLERİ"
    
    echo -e "${MAGENTA}1)${NC} Bellek Durumu"
    echo -e "${MAGENTA}2)${NC} Bellek Kullanım Yüzdesi"
    echo -e "${MAGENTA}3)${NC} En Fazla RAM Kullanan 10 Process"
    echo -e "${MAGENTA}4)${NC} Swap Alanı"
    echo -e "${MAGENTA}5)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1) execute_with_ask "free -h" "Bellek durumu gösteriliyor" ;;
        2) execute_with_ask "free | awk '/^Mem:/ {printf \"Kullanılan: %.1f%%\n\", (\$3/\$2)*100}'" "Bellek yüzdesi gösteriliyor" ;;
        3) execute_with_ask "ps aux --sort=-%mem | head -11" "En fazla RAM kullanan 10 process gösteriliyor" ;;
        4) execute_with_ask "free -h | grep Swap" "Swap alanı gösteriliyor" ;;
        5)
            execute_with_ask "free -h" "Bellek durumu"
            execute_with_ask "free | awk '/^Mem:/ {printf \"Kullanılan: %.1f%%\n\", (\$3/\$2)*100}'" "Bellek yüzdesi"
            execute_with_ask "ps aux --sort=-%mem | head -11" "En fazla RAM kullanan 10 process"
            execute_with_ask "free -h | grep Swap" "Swap alanı"
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    menu_memory_info
}

menu_disk_info() {
    clear_screen
    print_header "DİSK ALANI KONTROLÜ"
    
    echo -e "${MAGENTA}1)${NC} Disk Bölümleri"
    echo -e "${MAGENTA}2)${NC} /boot Bölümü Detayı"
    echo -e "${MAGENTA}3)${NC} İnode Kullanımı"
    echo -e "${MAGENTA}4)${NC} SMART Disk Durumu"
    echo -e "${MAGENTA}5)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1) execute_with_ask "df -h" "Disk bölümleri gösteriliyor" ;;
        2) execute_with_ask "df -h /boot && echo && df -i /boot" "/boot detay gösteriliyor" ;;
        3) execute_with_ask "df -i /" "İnode kullanımı gösteriliyor" ;;
        4) 
            if command -v smartctl &>/dev/null; then
                execute_with_ask "smartctl -H /dev/sda" "Disk SMART durumu gösteriliyor"
            else
                log_warning "smartmontools kurulu değil"
            fi
            ;;
        5)
            execute_with_ask "df -h" "Disk bölümleri"
            execute_with_ask "df -h /boot && echo && df -i /boot" "/boot detay"
            execute_with_ask "df -i /" "İnode kullanımı"
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    menu_disk_info
}

menu_gpu_info() {
    clear_screen
    print_header "GPU BİLGİLERİ (NVIDIA GeForce GTX 1650)"
    
    echo -e "${MAGENTA}1)${NC} GPU Donanımı"
    echo -e "${MAGENTA}2)${NC} Nouveau Sürücüsü"
    echo -e "${MAGENTA}3)${NC} NVIDIA Sürücüsü"
    echo -e "${MAGENTA}4)${NC} GPU Durumu (nvidia-smi)"
    echo -e "${MAGENTA}5)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1) execute_with_ask "lspci | grep -i nvidia" "GPU donanımı gösteriliyor" ;;
        2) execute_with_ask "lsmod | grep nouveau" "Nouveau sürücüsü kontrol ediliyor" ;;
        3) execute_with_ask "lsmod | grep nvidia" "NVIDIA sürücüsü kontrol ediliyor" ;;
        4)
            if command -v nvidia-smi &>/dev/null; then
                execute_with_ask "nvidia-smi" "GPU durumu gösteriliyor"
            else
                log_warning "nvidia-smi kurulu değil (CUDA toolkit gerekli)"
            fi
            ;;
        5)
            execute_with_ask "lspci | grep -i nvidia" "GPU donanımı"
            execute_with_ask "lsmod | grep nouveau" "Nouveau sürücüsü"
            execute_with_ask "lsmod | grep nvidia" "NVIDIA sürücüsü"
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    menu_gpu_info
}

menu_network_info() {
    clear_screen
    print_header "AĞ BAĞLANTISI KONTROLÜ"
    
    echo -e "${MAGENTA}1)${NC} Ağ Arayüzleri"
    echo -e "${MAGENTA}2)${NC} IP Adresleri"
    echo -e "${MAGENTA}3)${NC} Gateway ve Yönlendirme"
    echo -e "${MAGENTA}4)${NC} DNS Yapılandırması"
    echo -e "${MAGENTA}5)${NC} Açık Portlar"
    echo -e "${MAGENTA}6)${NC} İnternet Bağlantı Testi"
    echo -e "${MAGENTA}7)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1) execute_with_ask "ip link show" "Ağ arayüzleri gösteriliyor" ;;
        2) execute_with_ask "ip addr show" "IP adresleri gösteriliyor" ;;
        3) execute_with_ask "ip route show" "Gateway ve yönlendirme gösteriliyor" ;;
        4) execute_with_ask "cat /etc/resolv.conf | grep nameserver" "DNS yapılandırması gösteriliyor" ;;
        5) execute_with_ask "ss -tlnp | grep LISTEN" "Açık portlar gösteriliyor" ;;
        6) execute_with_ask "ping -c 3 8.8.8.8" "İnternet bağlantısı test ediliyor" ;;
        7)
            execute_with_ask "ip link show" "Ağ arayüzleri"
            execute_with_ask "ip addr show" "IP adresleri"
            execute_with_ask "ip route show" "Gateway ve yönlendirme"
            execute_with_ask "cat /etc/resolv.conf | grep nameserver" "DNS yapılandırması"
            execute_with_ask "ss -tlnp | grep LISTEN" "Açık portlar"
            execute_with_ask "ping -c 3 8.8.8.8" "İnternet bağlantısı"
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    menu_network_info
}

menu_services_info() {
    clear_screen
    print_header "SERVİS DURUMU"
    
    echo -e "${MAGENTA}1)${NC} Başarısız Servisler"
    echo -e "${MAGENTA}2)${NC} SSH Servisi"
    echo -e "${MAGENTA}3)${NC} Networking Servisi"
    echo -e "${MAGENTA}4)${NC} Cron Servisi"
    echo -e "${MAGENTA}5)${NC} Systemd Timer'ları"
    echo -e "${MAGENTA}6)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1) execute_with_ask "systemctl list-units --failed --all --no-legend" "Başarısız servisler gösteriliyor" ;;
        2) execute_with_ask "systemctl status ssh" "SSH servisi durumu gösteriliyor" ;;
        3) execute_with_ask "systemctl status networking" "Networking servisi durumu gösteriliyor" ;;
        4) execute_with_ask "systemctl status cron" "Cron servisi durumu gösteriliyor" ;;
        5) execute_with_ask "systemctl list-timers --all" "Systemd timer'ları gösteriliyor" ;;
        6)
            execute_with_ask "systemctl list-units --failed --all --no-legend" "Başarısız servisler"
            execute_with_ask "systemctl status ssh" "SSH servisi"
            execute_with_ask "systemctl status networking" "Networking servisi"
            execute_with_ask "systemctl status cron" "Cron servisi"
            execute_with_ask "systemctl list-timers --all" "Systemd timer'ları"
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    menu_services_info
}

menu_security_info() {
    clear_screen
    print_header "GÜVENLİK DENETİMİ"
    
    echo -e "${MAGENTA}1)${NC} Firewall Durumu (UFW)"
    echo -e "${MAGENTA}2)${NC} AppArmor Durumu"
    echo -e "${MAGENTA}3)${NC} Sudo Kullanım Geçmişi"
    echo -e "${MAGENTA}4)${NC} SUID Dosyaları"
    echo -e "${MAGENTA}5)${NC} SSH Yapılandırması"
    echo -e "${MAGENTA}6)${NC} Paket Bağımlılıkları"
    echo -e "${MAGENTA}7)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1) execute_with_ask "ufw status" "Firewall durumu gösteriliyor" ;;
        2) execute_with_ask "aa-enabled 2>&1" "AppArmor durumu gösteriliyor" ;;
        3) execute_with_ask "tail -10 /var/log/auth.log 2>/dev/null" "Sudo kullanım geçmişi gösteriliyor" ;;
        4) execute_with_ask "find / -perm -4000 2>/dev/null | wc -l" "SUID dosya sayısı gösteriliyor" ;;
        5) execute_with_ask "grep -E 'Port|PermitRootLogin|PasswordAuthentication' /etc/ssh/sshd_config" "SSH yapılandırması gösteriliyor" ;;
        6) execute_with_ask "apt check" "Paket bağımlılıkları kontrol ediliyor" ;;
        7)
            execute_with_ask "ufw status" "Firewall durumu"
            execute_with_ask "aa-enabled 2>&1" "AppArmor durumu"
            execute_with_ask "tail -10 /var/log/auth.log 2>/dev/null" "Sudo kullanım geçmişi"
            execute_with_ask "find / -perm -4000 2>/dev/null | wc -l" "SUID dosya sayısı"
            execute_with_ask "grep -E 'Port|PermitRootLogin|PasswordAuthentication' /etc/ssh/sshd_config" "SSH yapılandırması"
            execute_with_ask "apt check" "Paket bağımlılıkları"
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    menu_security_info
}

menu_benchmark_info() {
    clear_screen
    print_header "PERFORMANS BENCHMARKLERİ"
    
    echo -e "${MAGENTA}1)${NC} CPU Benchmark"
    echo -e "${MAGENTA}2)${NC} Disk Yazma Hızı"
    echo -e "${MAGENTA}3)${NC} Disk Okuma Hızı"
    echo -e "${MAGENTA}4)${NC} Network Latency"
    echo -e "${MAGENTA}5)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1)
            if command -v sysbench &>/dev/null; then
                execute_with_ask "sysbench cpu --cpu-max-prime=5000 run" "CPU Benchmark çalıştırılıyor"
            else
                log_warning "sysbench kurulu değil (apt install sysbench)"
            fi
            ;;
        2) execute_with_ask "dd if=/dev/zero of=/tmp/test_write bs=1M count=100 2>&1 | tail -5 && rm /tmp/test_write" "Disk yazma hızı test ediliyor" ;;
        3) execute_with_ask "dd if=/tmp/test_read of=/dev/null bs=1M 2>&1 | tail -5" "Disk okuma hızı test ediliyor" ;;
        4) execute_with_ask "ping -c 5 8.8.8.8" "Network latency test ediliyor" ;;
        5)
            if command -v sysbench &>/dev/null; then
                execute_with_ask "sysbench cpu --cpu-max-prime=5000 run" "CPU Benchmark"
            fi
            execute_with_ask "dd if=/dev/zero of=/tmp/test_write bs=1M count=100 2>&1 | tail -5 && rm /tmp/test_write" "Disk yazma hızı"
            execute_with_ask "ping -c 5 8.8.8.8" "Network latency"
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    menu_benchmark_info
}

menu_process_info() {
    clear_screen
    print_header "PROCESS ANALİZİ"
    
    echo -e "${MAGENTA}1)${NC} En Fazla CPU Kullanan 10 Process"
    echo -e "${MAGENTA}2)${NC} En Fazla RAM Kullanan 10 Process"
    echo -e "${MAGENTA}3)${NC} Toplam Process Sayısı"
    echo -e "${MAGENTA}4)${NC} Açık Dosya Descriptor Sayısı"
    echo -e "${MAGENTA}5)${NC} Process Ağacı"
    echo -e "${MAGENTA}6)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1) execute_with_ask "ps aux --sort=-%cpu | head -11" "En fazla CPU kullanan 10 process gösteriliyor" ;;
        2) execute_with_ask "ps aux --sort=-%mem | head -11" "En fazla RAM kullanan 10 process gösteriliyor" ;;
        3) execute_with_ask "ps aux | wc -l" "Toplam process sayısı gösteriliyor" ;;
        4) execute_with_ask "lsof 2>/dev/null | wc -l" "Açık dosya descriptor sayısı gösteriliyor" ;;
        5) execute_with_ask "pstree -p 1 2>/dev/null | head -50" "Process ağacı gösteriliyor" ;;
        6)
            execute_with_ask "ps aux --sort=-%cpu | head -11" "En fazla CPU kullanan 10 process"
            execute_with_ask "ps aux --sort=-%mem | head -11" "En fazla RAM kullanan 10 process"
            execute_with_ask "ps aux | wc -l" "Toplam process sayısı"
            execute_with_ask "lsof 2>/dev/null | wc -l" "Açık dosya descriptor sayısı"
            execute_with_ask "pstree -p 1 2>/dev/null | head -50" "Process ağacı"
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    menu_process_info
}

################################################################################
# DESKTOP ORTAMI SEÇİMİ
################################################################################

detect_desktops() {
    echo -e "\n${MAGENTA}🔍 Kurulu Desktop Ortamları Taranıyor...${NC}\n"
    
    local desktops=()
    
    if dpkg -l 2>/dev/null | grep -q "plasma-desktop"; then
        desktops+=("kde")
        echo -e "${CYAN}✓ KDE Plasma${NC}"
    fi
    
    if dpkg -l 2>/dev/null | grep -q "gnome-desktop"; then
        desktops+=("gnome")
        echo -e "${CYAN}✓ GNOME${NC}"
    fi
    
    if dpkg -l 2>/dev/null | grep -q "xfce4-session"; then
        desktops+=("xfce")
        echo -e "${CYAN}✓ XFCE${NC}"
    fi
    
    if dpkg -l 2>/dev/null | grep -q "lxde-core"; then
        desktops+=("lxde")
        echo -e "${CYAN}✓ LXDE${NC}"
    fi
    
    if dpkg -l 2>/dev/null | grep -q "cinnamon-session"; then
        desktops+=("cinnamon")
        echo -e "${CYAN}✓ Cinnamon${NC}"
    fi
    
    echo "${desktops[@]}"
}

menu_desktop() {
    clear_screen
    print_header "DESKTOP ORTAMI SEÇİMİ"
    
    local desktops=($(detect_desktops))
    
    if [[ ${#desktops[@]} -eq 0 ]]; then
        log_critical "Kurulu desktop ortamı bulunamadı!"
        pause_screen
        return
    fi
    
    local current=$(echo $XDG_CURRENT_DESKTOP | tr ',' '\n' | head -1)
    echo -e "${GREEN}Mevcut Desktop: $current${NC}\n"
    
    local i=1
    declare -A desktop_map
    
    for desktop in "${desktops[@]}"; do
        case $desktop in
            kde) echo -e "${MAGENTA}$i)${NC} KDE Plasma" ;;
            gnome) echo -e "${MAGENTA}$i)${NC} GNOME" ;;
            xfce) echo -e "${MAGENTA}$i)${NC} XFCE" ;;
            lxde) echo -e "${MAGENTA}$i)${NC} LXDE" ;;
            cinnamon) echo -e "${MAGENTA}$i)${NC} Cinnamon" ;;
        esac
        desktop_map[$i]=$desktop
        ((i++))
    done
    
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim (0-$((i-1))): " choice
    
    if [[ "$choice" -eq 0 ]]; then
        return
    fi
    
    if [[ -n "${desktop_map[$choice]}" ]]; then
        change_desktop "${desktop_map[$choice]}"
    else
        log_critical "Hatalı seçim!"
    fi
    
    pause_screen
    menu_desktop
}

change_desktop() {
    local target_desktop="$1"
    local session_name=""
    
    case $target_desktop in
        kde) session_name="plasmawayland" ;;
        gnome) session_name="ubuntu" ;;
        xfce) session_name="xfce" ;;
        lxde) session_name="LXDE" ;;
        cinnamon) session_name="cinnamon" ;;
    esac
    
    if [[ -f /etc/gdm3/daemon.conf ]]; then
        sed -i "s/Session=.*/Session=$session_name/" /etc/gdm3/daemon.conf
        log_info "GDM session değiştirildi: $session_name"
    elif [[ -f /etc/lightdm/lightdm.conf ]]; then
        sed -i "s/session=.*/session=$session_name/" /etc/lightdm/lightdm.conf
        log_info "LightDM session değiştirildi: $session_name"
    fi
    
    echo -e "\n${GREEN}✓ Desktop ortamı değiştirildi: $target_desktop${NC}"
    echo -e "${YELLOW}Yeniden giriş yap!${NC}"
}

################################################################################
# RAPORLAMA
################################################################################

generate_reports() {
    clear_screen
    print_header "RAPORLAR OLUŞTURULUYOR"
    
    # HTML Rapor
    cat > "$HTML_REPORT" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pardus Linux - Sistem Sağlık Raporu</title>
    <style>
        body { font-family: 'Segoe UI', Arial; margin: 0; padding: 20px; background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); color: #333; }
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 10px; box-shadow: 0 10px 40px rgba(0,0,0,0.3); overflow: hidden; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }
        .header h1 { margin: 0; font-size: 2.5em; }
        .content { padding: 30px; }
        .section { margin-bottom: 30px; border-left: 4px solid #667eea; padding-left: 20px; }
        .section h2 { color: #667eea; margin-top: 0; }
        .summary-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-bottom: 30px; }
        .stat-box { text-align: center; padding: 20px; border-radius: 8px; color: white; font-weight: bold; }
        .stat-critical { background: linear-gradient(135deg, #dc3545, #c82333); }
        .stat-warning { background: linear-gradient(135deg, #ffc107, #e0a800); }
        .stat-success { background: linear-gradient(135deg, #28a745, #1e7e34); }
        .stat-number { font-size: 2em; margin-bottom: 5px; }
        .footer { background: #f8f9fa; padding: 20px; text-align: center; color: #666; border-top: 1px solid #ddd; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🖥️ Pardus GNU/Linux Sistem Sağlık Raporu</h1>
            <p>Makine: <strong>virci</strong> | Tarih: <strong>REPORT_DATE</strong></p>
        </div>
        <div class="content">
            <div class="summary-stats">
                <div class="stat-box stat-critical">
                    <div class="stat-number">CRITICAL_COUNT</div>
                    <div>Kritik Sorun</div>
                </div>
                <div class="stat-box stat-warning">
                    <div class="stat-number">WARNING_COUNT</div>
                    <div>Uyarı</div>
                </div>
                <div class="stat-box stat-success">
                    <div class="stat-number">INFO_COUNT</div>
                    <div>Başarılı İşlem</div>
                </div>
            </div>
            <div class="section">
                <h2>✓ Tarama Tamamlandı</h2>
                <p>Sistem kontrolleri başarıyla tamamlanmıştır. Detaylı bilgiler için JSON raporunu inceleyebilirsiniz.</p>
                <p><strong>Rapor Tarihi:</strong> REPORT_DATE</p>
                <p><strong>Toplam İşlem Süresi:</strong> SCAN_DURATION saniye</p>
            </div>
        </div>
        <div class="footer">
            <p>🔧 Pardus GNU/Linux Sistem Sağlık Raporu | Otomatik Oluşturuldu</p>
        </div>
    </div>
</body>
</html>
HTMLEOF

    # JSON Rapor
    cat > "$JSON_REPORT" << JSONEOF
{
  "metadata": {
    "version": "$SCRIPT_VERSION",
    "timestamp": "$(date -Iseconds)",
    "machine": "$(hostname)",
    "kernel": "$(uname -r)",
    "distro": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
  },
  "summary": {
    "successful_operations": $INFO_COUNT,
    "scan_duration_seconds": $(($(date +%s) - $START_TIME))
  },
  "system_info": {
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "uptime": "$(uptime -p 2>/dev/null || echo 'N/A')",
    "cpu_cores": "$(nproc 2>/dev/null || echo 'N/A')",
    "total_ram_gb": "$(free -g 2>/dev/null | awk '/^Mem:/ {print $2}' || echo 'N/A')",
    "available_ram_gb": "$(free -g 2>/dev/null | awk '/^Mem:/ {print $7}' || echo 'N/A')",
    "disk_usage_percent": "$(df / 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo 'N/A')"
  }
}
JSONEOF

    log_info "HTML Rapor oluşturuldu: $HTML_REPORT"
    log_info "JSON Rapor oluşturuldu: $JSON_REPORT"
}

view_reports() {
    clear_screen
    print_header "RAPORLAR"
    
    echo -e "${MAGENTA}1)${NC} HTML Raporu Aç (Firefox)"
    echo -e "${MAGENTA}2)${NC} JSON Raporu Göster"
    echo -e "${MAGENTA}3)${NC} Log Dosyasını Göster"
    echo -e "${MAGENTA}4)${NC} Rapor Dosyaları Listele"
    echo -e "${MAGENTA}0)${NC} Geri"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1)
            firefox "$HTML_REPORT" 2>/dev/null &
            log_info "HTML raporu Firefox'ta açılıyor..."
            ;;
        2)
            echo ""
            cat "$JSON_REPORT" | jq . 2>/dev/null || cat "$JSON_REPORT"
            ;;
        3)
            echo ""
            tail -50 "$LOG_FILE"
            ;;
        4)
            echo ""
            echo -e "${CYAN}Rapor Dosyaları:${NC}"
            ls -lh "$LOG_DIR"/ 2>/dev/null
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" ;;
    esac
    
    pause_screen
    view_reports
}

################################################################################
# TÜMÜNÜ ÇALIŞTIR
################################################################################

run_all() {
    clear_screen
    print_header "TÜMÜ BİRLİKTE ÇALIŞTIRILACAK"
    
    echo -e "${YELLOW}Bu işlem tüm kontrolleri sırayla çalıştıracak.${NC}"
    echo -e "${YELLOW}Her kontrol için onay sorulacak.${NC}\n"
    
    read -p "Devam et? (E/H): " choice
    case $choice in
        [Ee]|[Ee][Vv][Ee][Tt]) ;;
        *) return ;;
    esac
    
    # Sistem Bilgileri
    print_header "TEMEL SİSTEM BİLGİLERİ"
    execute_with_ask "hostname" "Makine adı"
    execute_with_ask "cat /etc/os-release | grep PRETTY_NAME" "Dağıtım bilgisi"
    execute_with_ask "uname -r" "Kernel versiyonu"
    
    # CPU
    print_header "CPU VE İŞLEMCİ"
    execute_with_ask "lscpu" "CPU bilgileri"
    execute_with_ask "uptime" "CPU yükü"
    
    # Bellek
    print_header "BELLEK (RAM)"
    execute_with_ask "free -h" "Bellek durumu"
    execute_with_ask "ps aux --sort=-%mem | head -11" "En fazla RAM kullanan 10 process"
    
    # Disk
    print_header "DİSK ALANI"
    execute_with_ask "df -h" "Disk bölümleri"
    execute_with_ask "df -i /" "İnode kullanımı"
    
    # GPU
    print_header "GPU"
    execute_with_ask "lspci | grep -i nvidia" "GPU donanımı"
    
    # Ağ
    print_header "AĞ BAĞLANTISI"
    execute_with_ask "ip link show" "Ağ arayüzleri"
    execute_with_ask "ip addr show" "IP adresleri"
    
    # Servisler
    print_header "SERVİSLER"
    execute_with_ask "systemctl list-units --failed --all --no-legend" "Başarısız servisler"
    
    # Güvenlik
    print_header "GÜVENLİK"
    execute_with_ask "ufw status" "Firewall durumu"
    
    # Process
    print_header "PROCESS ANALİZİ"
    execute_with_ask "ps aux --sort=-%cpu | head -11" "En fazla CPU kullanan 10 process"
    
    print_header "RAPORLAR OLUŞTURULUYOR"
    generate_reports
    
    echo -e "\n${GREEN}✓ Tüm kontroller tamamlandı!${NC}"
    pause_screen
}

################################################################################
# SORUN TESPİTİ VE ÖNERİLER
################################################################################

detect_issues() {
    local issues=()
    
    # /boot kontrolü
    local boot_usage=$(df /boot 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ -n "$boot_usage" && $boot_usage -gt 80 ]]; then
        issues+=("/boot bölümü %$boot_usage dolu")
    fi
    
    # Disk alanı kontrolü
    local disk_usage=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ -n "$disk_usage" && $disk_usage -gt 85 ]]; then
        issues+=("Kök disk bölümü %$disk_usage dolu")
    fi
    
    # Firewall kontrolü
    if ! ufw status 2>/dev/null | grep -q "active"; then
        issues+=("Firewall (UFW) aktif değil")
    fi
    
    # Paket sorunları
    if ! apt check 2>&1 | grep -q "ok"; then
        issues+=("Paket bağımlılıkları sorunlu")
    fi
    
    # Bellek kullanımı
    local mem_usage=$(free | awk '/^Mem:/ {printf "%.0f", ($3/$2)*100}')
    if [[ $mem_usage -gt 85 ]]; then
        issues+=("Bellek kullanımı %$mem_usage (çok yüksek)")
    fi
    
    # SMART disk durumu
    if command -v smartctl &>/dev/null; then
        if ! smartctl -H /dev/sda 2>/dev/null | grep -q "PASSED"; then
            issues+=("Disk SMART durumu uyarılı")
        fi
    fi
    
    # systemd hataları
    if systemctl list-units --failed --all --no-legend 2>/dev/null | grep -q "failed"; then
        local failed_count=$(systemctl list-units --failed --all --no-legend 2>/dev/null | wc -l)
        issues+=("$failed_count başarısız systemd servisi")
    fi
    
    # Eski paketler
    local upgradable=$(apt list --upgradable 2>/dev/null | wc -l)
    if [[ $upgradable -gt 10 ]]; then
        issues+=("$upgradable güncellenebilir paket")
    fi
    
    # /tmp temizliği
    local tmp_mb=$(du -sm /tmp 2>/dev/null | awk '{print $1}')
    if [[ $tmp_mb -gt 500 ]]; then
        issues+=("/tmp dizini $(du -sh /tmp | awk '{print $1}') yer kaplıyor")
    fi
    
    # Kernel güncellemeleri
    if [[ -f /var/run/reboot-required ]]; then
        issues+=("Sistem yeniden başlatılması gerekiyor")
    fi
    
    # SSH yapılandırması
    if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
        issues+=("SSH: Root giriş izin verilmiş (Güvenlik riski)")
    fi
    
    echo "${issues[@]}"
}

menu_recommendations() {
    clear_screen
    print_header "ÖNERİLEN İŞLEMLER"
    
    local issues_array=($(detect_issues))
    
    if [[ ${#issues_array[@]} -eq 0 ]]; then
        echo -e "${GREEN}✓ Sistem sağlıklı görünüyor!${NC}"
        echo -e "${GREEN}✓ Herhangi bir sorun tespit edilmedi!${NC}\n"
        pause_screen
        return
    fi
    
    echo -e "${RED}⚠️  Tespit Edilen Sorunlar:${NC}\n"
    
    local i=1
    for issue in "${issues_array[@]}"; do
        echo -e "${MAGENTA}$i)${NC} $issue"
        ((i++))
    done
    
    # Çözüm önerileri hazırla
    local solutions_list=()
    declare -a solution_desc
    
    local boot_usage=$(df /boot 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ -n "$boot_usage" && $boot_usage -gt 80 ]]; then
        solutions_list+=("apt autoremove && apt autoclean && apt clean")
        solution_desc[${#solutions_list[@]}-1]="Eski kernel ve paketleri temizle"
    fi
    
    local disk_usage=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ -n "$disk_usage" && $disk_usage -gt 85 ]]; then
        solutions_list+=("du -sh /* | sort -rh | head -10")
        solution_desc[${#solutions_list[@]}-1]="Büyük dosyaları göster"
    fi
    
    if ! ufw status 2>/dev/null | grep -q "active"; then
        solutions_list+=("ufw enable")
        solution_desc[${#solutions_list[@]}-1]="Firewall'ı aç"
    fi
    
    if ! apt check 2>&1 | grep -q "ok"; then
        solutions_list+=("apt --fix-broken install && apt -y upgrade")
        solution_desc[${#solutions_list[@]}-1]="Kırık paketleri düzelt ve güncelle"
    fi
    
    if systemctl list-units --failed --all --no-legend 2>/dev/null | grep -q "failed"; then
        solutions_list+=("systemctl list-units --failed")
        solution_desc[${#solutions_list[@]}-1]="Başarısız servisleri göster"
    fi
    
    local upgradable=$(apt list --upgradable 2>/dev/null | wc -l)
    if [[ $upgradable -gt 10 ]]; then
        solutions_list+=("apt update && apt upgrade -y")
        solution_desc[${#solutions_list[@]}-1]="Tüm paketleri güncelle"
    fi
    
    local tmp_mb=$(du -sm /tmp 2>/dev/null | awk '{print $1}')
    if [[ $tmp_mb -gt 500 ]]; then
        solutions_list+=("rm -rf /tmp/* && rm -rf /var/tmp/*")
        solution_desc[${#solutions_list[@]}-1]="/tmp dizinini temizle"
    fi
    
    if [[ -f /var/run/reboot-required ]]; then
        solutions_list+=("sudo reboot")
        solution_desc[${#solutions_list[@]}-1]="Sistem yeniden başlat"
    fi
    
    if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
        solutions_list+=("sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart ssh")
        solution_desc[${#solutions_list[@]}-1]="SSH güvenliğini arttır (Root giriş kapat)"
    fi
    
    if [[ ${#solutions_list[@]} -eq 0 ]]; then
        echo -e "\n${GREEN}✓ Sorunlar tespit edildi ancak otomatik çözüm bulunamadı.${NC}"
        pause_screen
        return
    fi
    
    echo ""
    echo -e "${YELLOW}📋 Önerilen Çözümler:${NC}\n"
    
    i=1
    for idx in "${!solutions_list[@]}"; do
        echo -e "${MAGENTA}$((idx+1)))${NC} ${solution_desc[$idx]}"
        echo "    ${CYAN}→ ${solutions_list[$idx]}${NC}"
        echo ""
    done
    
    echo -e "${MAGENTA}A)${NC} Hepsi Birlikte Çalıştır"
    echo -e "${MAGENTA}S)${NC} Seçili Çalıştır"
    echo -e "${MAGENTA}0)${NC} Geri Dön"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        [Aa])
            clear_screen
            print_header "ÇÖZÜMLER UYGULANIYYOR"
            echo ""
            for idx in "${!solutions_list[@]}"; do
                execute_with_ask "${solutions_list[$idx]}" "${solution_desc[$idx]}"
                echo ""
            done
            echo -e "\n${GREEN}✓ Tüm çözümler uygulandı!${NC}"
            pause_screen
            ;;
        [Ss])
            clear_screen
            echo -e "\n${CYAN}Hangi çözümü çalıştırmak istiyorsunuz?${NC}\n"
            for idx in "${!solutions_list[@]}"; do
                echo -e "${MAGENTA}$((idx+1)))${NC} ${solution_desc[$idx]}"
            done
            echo ""
            read -p "Seçim (1-${#solutions_list[@]}): " sel
            
            if [[ $sel -ge 1 && $sel -le ${#solutions_list[@]} ]]; then
                selected_idx=$((sel-1))
                execute_with_ask "${solutions_list[$selected_idx]}" "${solution_desc[$selected_idx]}"
            else
                log_warning "Hatalı seçim!"
            fi
            pause_screen
            ;;
        0) return ;;
        *) echo -e "${RED}Hatalı seçim!${NC}" && pause_screen && menu_recommendations ;;
    esac
    
    menu_recommendations
}

################################################################################
# ANA MENU
################################################################################

main_menu() {
    clear_screen
    
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Pardus GNU/Linux - Sistem Sağlık Aracı      ║${NC}"
    echo -e "${CYAN}║  Makine: virci                                ║${NC}"
    echo -e "${CYAN}║  Sürüm: $SCRIPT_VERSION                       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}ANA MENU${NC}\n"
    
    echo -e "${MAGENTA}KONTROLLER:${NC}"
    echo -e "${MAGENTA}1)${NC}  Sistem Bilgileri"
    echo -e "${MAGENTA}2)${NC}  CPU Analizi"
    echo -e "${MAGENTA}3)${NC}  Bellek (RAM) Analizi"
    echo -e "${MAGENTA}4)${NC}  Disk Analizi"
    echo -e "${MAGENTA}5)${NC}  GPU Bilgileri"
    echo -e "${MAGENTA}6)${NC}  Ağ Kontrolü"
    echo -e "${MAGENTA}7)${NC}  Servis Durumu"
    echo -e "${MAGENTA}8)${NC}  Güvenlik Denetimi"
    echo -e "${MAGENTA}9)${NC}  Benchmark Testleri"
    echo -e "${MAGENTA}10)${NC} Process Analizi"
    
    echo ""
    echo -e "${MAGENTA}İŞLEMLER:${NC}"
    echo -e "${MAGENTA}11)${NC} Tümünü Çalıştır"
    echo -e "${MAGENTA}12)${NC} Raporları Görüntüle"
    echo -e "${MAGENTA}13)${NC} Desktop Ortamı Seçimi"
    echo -e "${MAGENTA}14)${NC} Önerilen İşlemler"
    
    echo ""
    echo -e "${MAGENTA}0)${NC}  Çıkış"
    echo ""
    read -p "Seçim: " choice
    
    case $choice in
        1) menu_system_info ;;
        2) menu_cpu_info ;;
        3) menu_memory_info ;;
        4) menu_disk_info ;;
        5) menu_gpu_info ;;
        6) menu_network_info ;;
        7) menu_services_info ;;
        8) menu_security_info ;;
        9) menu_benchmark_info ;;
        10) menu_process_info ;;
        11) run_all ;;
        12) view_reports ;;
        13) menu_desktop ;;
        14) menu_recommendations ;;
        0)
            echo -e "\n${GREEN}Çıkılıyor...${NC}\n"
            exit 0
            ;;
        *)
            echo -e "${RED}Hatalı seçim!${NC}"
            pause_screen
            ;;
    esac
    
    main_menu
}

################################################################################
# BAŞLANGICI
################################################################################

check_root
main_menu
