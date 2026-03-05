#!/bin/bash
# ALDZ PROTECTION VPS - MAIN INSTALLER
# JALANKAN SEBAGAI ROOT

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  ALDZ PROTECTION VPS INSTALLER v1.0  ${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"

# CEK ROOT
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: Jalankan sebagai root!${NC}"; exit 1
fi

# CEK OS
if [[ ! -f /etc/os-release ]] || ! grep -qi "ubuntu" /etc/os-release; then
    echo -e "${RED}ERROR: Hanya untuk Ubuntu 20.04/22.04${NC}"; exit 1
fi

# BACKUP DIRECTORY
BACKUP_DIR="/root/aldz-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo -e "${YELLOW}📦 Backup: $BACKUP_DIR${NC}"

# FUNGSI COPY KONFIG
copy_config() {
    local src=$1 dst=$2
    if [[ -f "$dst" ]]; then cp "$dst" "$BACKUP_DIR/" 2>/dev/null || true; fi
    cp -f "$src" "$dst"
    echo -e "${GREEN}  ✅ $dst${NC}"
}

# 1. UPDATE & DEPENDENSI
echo -e "\n${YELLOW}[1/12] Memperbarui sistem & menginstal dependensi...${NC}"
apt update && apt upgrade -y
apt install -y ufw fail2ban knockd git curl wget nano vim \
    build-essential libpam-google-authenticator nginx \
    inotify-tools aide rkhunter chkrootkit unattended-upgrades \
    iptables-persistent netfilter-persistent python3 python3-pip \
    aide-common lynis
pip3 install flask requests watchdog

# 2. SSH HARDENING + 4FA
echo -e "\n${YELLOW}[2/12] Mengkonfigurasi SSH Hardening & 4FA...${NC}"
copy_config "configs/ssh/sshd_config.aldz" "/etc/ssh/sshd_config"
copy_config "configs/modules/port-knocking/knockd.conf" "/etc/knockd.conf"

# Aktifkan PAM Google Authenticator
sed -i 's/^#auth required/auth required/' /etc/pam.d/sshd 2>/dev/null || \
    echo "auth required pam_google_authenticator.so" >> /etc/pam.d/sshd

# 3. PORT KNOCKING
echo -e "\n${YELLOW}[3/12] Mengaktifkan Port Knocking...${NC}"
INTERFACE=$(ip route get 1 | awk '{print $5;exit}')
sed -i "s/eth0/$INTERFACE/g" /etc/knockd.conf
sed -i 's/START_KNOCKD=0/START_KNOCKD=1/' /etc/default/knockd
systemctl enable knockd
systemctl restart knockd

# 4. FIREWALL UFW
echo -e "\n${YELLOW}[4/12] Mengkonfigurasi Firewall UFW...${NC}"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 7000/udp comment 'Knock port 1'
ufw allow 8000/udp comment 'Knock port 2'
ufw allow 9000/udp comment 'Knock port 3'
ufw --force enable

# 5. FAIL2BAN
echo -e "\n${YELLOW}[5/12] Mengkonfigurasi Fail2Ban...${NC}"
copy_config "configs/fail2ban/jail.local" "/etc/fail2ban/jail.local"
copy_config "configs/fail2ban/filter.d/custom-aldz.conf" "/etc/fail2ban/filter.d/custom-aldz.conf"
systemctl enable fail2ban
systemctl restart fail2ban

# 6. ANTI DEFACE WATCHER
echo -e "\n${YELLOW}[6/12] Mengaktifkan Anti Deface Watcher...${NC}"
copy_config "scripts/anti-deface-watcher.sh" "/usr/local/bin/aldz-defender"
chmod +x "/usr/local/bin/aldz-defender"

# Buat service systemd
cat > /etc/systemd/system/aldz-defender.service <<EOF
[Unit]
Description=ALDZ Anti Deface Watcher
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/aldz-defender
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
systemctl enable aldz-defender
systemctl start aldz-defender

# 7. ANTI HIJACK MONITOR
echo -e "\n${YELLOW}[7/12] Mengaktifkan Anti Hijack Monitor...${NC}"
copy_config "scripts/anti-hijack-monitor.sh" "/usr/local/bin/aldz-hijack"
chmod +x "/usr/local/bin/aldz-hijack"
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/aldz-hijack") | crontab -

# 8. ANTI BOTNET
echo -e "\n${YELLOW}[8/12] Mengaktifkan Anti Botnet Blocker...${NC}"
copy_config "scripts/anti-botnet-block.sh" "/usr/local/bin/aldz-botblock"
chmod +x "/usr/local/bin/aldz-botblock"
(crontab -l 2>/dev/null; echo "0 */6 * * * /usr/local/bin/aldz-botblock") | crontab -

# 9. KERNEL HARDENING
echo -e "\n${YELLOW}[9/12] Menerapkan Kernel Hardening...${NC}"
copy_config "configs/modules/sysctl-hardening.conf" "/etc/sysctl.d/99-aldz-hardening.conf"
sysctl -p /etc/sysctl.d/99-aldz-hardening.conf

# 10. PASSWORD PROTECTION
echo -e "\n${YELLOW}[10/12] Mengunci file password...${NC}"
chattr +i /etc/passwd /etc/shadow /etc/group /etc/gshadow 2>/dev/null || true
echo "alias aldz-unlock='chattr -i /etc/passwd /etc/shadow /etc/group /etc/gshadow'" >> /root/.bashrc

# 11. COPY TOOLS
echo -e "\n${YELLOW}[11/12] Memasang tools pendukung...${NC}"
cp tools/aldz-knocker /usr/local/bin/
cp tools/aldz-sensor /usr/local/bin/
chmod +x /usr/local/bin/aldz-*

# 12. FINAL
echo -e "\n${YELLOW}[12/12] Finalisasi & pembersihan...${NC}"
systemctl daemon-reload
ufw status verbose
fail2ban-client status

echo -e "\n${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ INSTALASI SELESAI!${NC}"
echo -e "${GREEN}⚠️  VPS AKAN REBOOT DALAM 10 DETIK${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
sleep 10
reboot
