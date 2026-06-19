#!/usr/bin/env bash
# ============================================================
#  Linux CIS Benchmark Hardening Script
#  people.inc MLOps Platform — RHEL 9 / Ubuntu 22.04
#  Author: Venkatesh Nagelli | people.inc
#  Usage : sudo bash harden.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

pass()  { echo -e "${GREEN}[PASS]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
apply() { echo -e "${BLUE}[APPLY]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash harden.sh"
  exit 1
fi

OS=$(. /etc/os-release && echo "$ID")
info "Detected OS: ${OS}"
echo ""
echo "══════════════════════════════════════════════════════"
echo "  people.inc — Linux CIS Hardening"
echo "  $(date)"
echo "══════════════════════════════════════════════════════"

# ── 1. SSH Hardening ─────────────────────────────────────────
echo ""
info "── 1. SSH Hardening ──"

SSHD_CONF="/etc/ssh/sshd_config"
cp "${SSHD_CONF}" "${SSHD_CONF}.bak.$(date +%Y%m%d)"

declare -A SSH_SETTINGS=(
  ["PermitRootLogin"]="no"
  ["PasswordAuthentication"]="no"
  ["PubkeyAuthentication"]="yes"
  ["PermitEmptyPasswords"]="no"
  ["X11Forwarding"]="no"
  ["MaxAuthTries"]="3"
  ["LoginGraceTime"]="60"
  ["ClientAliveInterval"]="300"
  ["ClientAliveCountMax"]="2"
  ["Protocol"]="2"
  ["AllowAgentForwarding"]="no"
  ["AllowTcpForwarding"]="no"
  ["UsePAM"]="yes"
  ["PrintLastLog"]="yes"
  ["Banner"]="/etc/ssh/banner"
)

for key in "${!SSH_SETTINGS[@]}"; do
  val="${SSH_SETTINGS[$key]}"
  if grep -q "^${key}" "${SSHD_CONF}"; then
    sed -i "s/^${key}.*/${key} ${val}/" "${SSHD_CONF}"
  else
    echo "${key} ${val}" >> "${SSHD_CONF}"
  fi
  apply "SSH: ${key} = ${val}"
done

# SSH Login Banner
cat > /etc/ssh/banner << 'BANNER'
***************************************************************************
  AUTHORIZED ACCESS ONLY — people.inc
  All activity is monitored and logged.
  Unauthorized access will be prosecuted.
***************************************************************************
BANNER

systemctl restart sshd
pass "SSH hardening complete"

# ── 2. Filesystem Security ────────────────────────────────────
echo ""
info "── 2. Filesystem & Mount Security ──"

# Disable unused filesystems
UNUSED_FS=(cramfs freevxfs jffs2 hfs hfsplus squashfs udf vfat)
for fs in "${UNUSED_FS[@]}"; do
  echo "install ${fs} /bin/true" >> /etc/modprobe.d/disable-unused-fs.conf
  apply "Disabled filesystem: ${fs}"
done

# Secure /tmp mount options
if mountpoint -q /tmp; then
  mount -o remount,nodev,nosuid,noexec /tmp
  apply "Remounted /tmp with nodev,nosuid,noexec"
fi

# Set sticky bit on world-writable directories
find / -xdev -type d \( -perm -0002 -a ! -perm -1000 \) 2>/dev/null | \
  xargs -I{} chmod +t {} 2>/dev/null || true
apply "Sticky bit set on world-writable directories"

pass "Filesystem hardening complete"

# ── 3. Kernel Parameters (sysctl) ────────────────────────────
echo ""
info "── 3. Kernel Parameters ──"

cat > /etc/sysctl.d/99-people-inc-hardening.conf << 'EOF'
# Network security
net.ipv4.ip_forward                 = 0
net.ipv4.conf.all.send_redirects    = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects  = 0
net.ipv4.conf.all.secure_redirects  = 0
net.ipv4.conf.all.log_martians      = 1
net.ipv4.conf.all.rp_filter         = 1
net.ipv4.tcp_syncookies             = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# IPv6 — disable if not in use
net.ipv6.conf.all.disable_ipv6     = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Kernel hardening
kernel.randomize_va_space           = 2
kernel.dmesg_restrict               = 1
kernel.kptr_restrict                = 2
kernel.sysrq                        = 0
kernel.core_uses_pid                = 1

# File descriptor limits
fs.suid_dumpable                    = 0
EOF

sysctl --system > /dev/null 2>&1
apply "Kernel parameters applied from /etc/sysctl.d/99-people-inc-hardening.conf"
pass "Kernel hardening complete"

# ── 4. Auditd — Logging ───────────────────────────────────────
echo ""
info "── 4. Audit Logging (auditd) ──"

if command -v auditd &>/dev/null || apt-get install -y auditd &>/dev/null || yum install -y auditd &>/dev/null; then

  cat > /etc/audit/rules.d/people-inc.rules << 'EOF'
# Delete all existing rules
-D

# Increase buffer size
-b 8192

# Failure mode: 1=printk, 2=panic
-f 1

# Monitor authentication
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers

# Monitor SSH
-w /etc/ssh/sshd_config -p wa -k sshd

# Privileged commands
-a always,exit -F path=/usr/bin/sudo -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged
-a always,exit -F path=/usr/bin/su -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged

# File deletions
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -k file-delete

# Network configuration changes
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/network -p wa -k system-locale

# Module loading
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules

# Kubernetes node audit
-w /var/lib/kubelet -p wa -k kubelet
-w /etc/kubernetes -p wa -k kubernetes-config

# Make rules immutable (reboot required to change)
-e 2
EOF

  service auditd restart 2>/dev/null || systemctl restart auditd 2>/dev/null || true
  apply "Auditd rules written and service restarted"
  pass "Audit logging configured"
else
  warn "auditd not available — skipping"
fi

# ── 5. Password Policy ────────────────────────────────────────
echo ""
info "── 5. Password Policy ──"

if command -v authconfig &>/dev/null; then
  authconfig --passminlen=14 --enablereqlower --enablerequpper --enablereqdigit --update 2>/dev/null || true
fi

# PAM password quality
if [[ -f /etc/pam.d/common-password ]]; then
  sed -i 's/^password.*pam_unix.so.*/password [success=1 default=ignore] pam_unix.so obscure sha512 minlen=14 remember=5/' \
    /etc/pam.d/common-password
  apply "PAM: minimum password length = 14, sha512 hashing"
fi

# Login defs
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/'  /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs
apply "Password aging: max=90d, min=7d, warn=14d"
pass "Password policy configured"

# ── 6. Disable Unused Services ───────────────────────────────
echo ""
info "── 6. Disabling Unused Services ──"

UNUSED_SERVICES=(
  "telnet" "rsh" "rlogin" "rexec"
  "nis" "tftp" "talk" "chargen"
  "daytime" "echo" "discard"
  "avahi-daemon" "cups" "nfs"
)

for svc in "${UNUSED_SERVICES[@]}"; do
  if systemctl is-active --quiet "${svc}" 2>/dev/null; then
    systemctl disable --now "${svc}" 2>/dev/null && apply "Disabled service: ${svc}" || true
  fi
done

pass "Unused services disabled"

# ── 7. File Permissions ───────────────────────────────────────
echo ""
info "── 7. Critical File Permissions ──"

declare -A FILE_PERMS=(
  ["/etc/passwd"]="644"
  ["/etc/shadow"]="000"
  ["/etc/group"]="644"
  ["/etc/gshadow"]="000"
  ["/etc/sudoers"]="440"
  ["/boot/grub2/grub.cfg"]="600"
)

for file in "${!FILE_PERMS[@]}"; do
  perm="${FILE_PERMS[$file]}"
  if [[ -f "${file}" ]]; then
    chmod "${perm}" "${file}"
    apply "Set ${file} → ${perm}"
  fi
done

pass "File permissions hardened"

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo -e "${GREEN}  ✅ people.inc Linux Hardening COMPLETE${NC}"
echo "  Run 'bash scripts/linux-hardening/audit.sh' to verify"
echo "══════════════════════════════════════════════════════"
