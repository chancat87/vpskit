#!/bin/bash
set -euo pipefail

# ============================================
# Setup complet VPS neuf
# Distributions : Ubuntu, Debian, AlmaLinux, Rocky Linux, CentOS, Fedora
# Fonctionne sur Mac, Linux et Windows (Git Bash / WSL)
# Reprend automatiquement en cas de déconnexion.
#
# Usage : bash <(curl -sL https://raw.githubusercontent.com/mariusdjen/vpskit/main/vpskit.sh)
# ============================================

# --- Couleurs ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO] $1${NC}"; }
success() { echo -e "${GREEN}[OK] $1${NC}"; }
warn()    { echo -e "${YELLOW}[WARN] $1${NC}"; }
err()     { echo -e "${RED}[ERR] $1${NC}"; }
step()    { echo -e "\n${BOLD}${YELLOW}[>] $1${NC}\n  $2\n"; }

confirm() {
    read -p "  $MSG_SETUP_NEW_STEP3_CONFIRM" REPLY
    [[ "$REPLY" == "o" || "$REPLY" == "O" || "$REPLY" == "y" || "$REPLY" == "Y" ]]
}

# Echapper les caracteres speciaux pour sed (evite l'injection de commandes)
# Echappe : \ (escape), & (back-reference), | (delimiteur)
sed_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/|/\\|/g'
}

# Fichiers temporaires a nettoyer au EXIT
# (${arr[@]+...} : un tableau vide leve "unbound variable" sous set -u avec le bash 3.2 de macOS)
_CLEANUP_FILES=()
cleanup() { rm -f ${_CLEANUP_FILES[@]+"${_CLEANUP_FILES[@]}"}; }
trap cleanup EXIT

# Lire une variable depuis un fichier key="value" de facon securisee
read_state_var() {
    local file="$1" var="$2"
    grep "^${var}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//'
}

# =========================================
# DÉTECTION DE L'ENVIRONNEMENT
# =========================================

detect_os() {
    case "$(uname -s)" in
        Darwin)  OS="mac" ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                OS="wsl"
            else
                OS="linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)  OS="windows" ;;
        *)  OS="unknown" ;;
    esac
}

detect_os

# --- Chargement de la langue ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -f "${SCRIPT_DIR}/lang.sh" ]; then
    . "${SCRIPT_DIR}/lang.sh"
else
    _LANG_TMP=$(mktemp)
    _CLEANUP_FILES+=("$_LANG_TMP")
    # shellcheck disable=SC1090
    curl -fsSL "https://raw.githubusercontent.com/mariusdjen/vpskit/main/lang.sh" -o "$_LANG_TMP" 2>/dev/null && . "$_LANG_TMP"
fi

echo ""
echo "========================================="
echo -e "  ${BOLD}VPS BOOTSTRAP${NC}"
echo "  $MSG_SETUP_BANNER_SUBTITLE"
echo "  $MSG_SETUP_BANNER_SUBTITLE2"
echo ""
echo "  $MSG_SETUP_BANNER_AUTHOR"
echo "  $MSG_SETUP_BANNER_WEBSITE"
echo "========================================="
echo ""

case "$OS" in
    mac)      info "$MSG_SETUP_OS_MAC" ;;
    linux)    info "$MSG_SETUP_OS_LINUX" ;;
    windows)  info "$MSG_SETUP_OS_WINDOWS_GITBASH" ;;
    wsl)      info "$MSG_SETUP_OS_WSL" ;;
    *)
        err "$MSG_SETUP_OS_UNKNOWN_ERR"
        echo "  $MSG_SETUP_OS_UNKNOWN_COMPAT"
        echo "  $MSG_SETUP_OS_UNKNOWN_MACOS"
        echo "  $MSG_SETUP_OS_UNKNOWN_LINUX"
        echo "  $MSG_SETUP_OS_UNKNOWN_WINDOWS"
        echo ""
        echo "  $MSG_SETUP_OS_WINDOWS_INSTALL"
        echo "    $MSG_SETUP_OS_WINDOWS_STEP1"
        echo "    $MSG_SETUP_OS_WINDOWS_STEP2"
        echo "    $MSG_SETUP_OS_WINDOWS_STEP3"
        exit 1
        ;;
esac

# --- Vérifier que ssh est disponible ---
if ! command -v ssh &>/dev/null; then
    err "$MSG_SETUP_SSH_NOT_FOUND_ERR"
    case "$OS" in
        windows)
            echo "  $MSG_SETUP_SSH_INSTALL_WINDOWS"
            echo "  $MSG_SETUP_SSH_INSTALL_WINDOWS_ALT"
            ;;
        *)
            echo "  $MSG_SETUP_SSH_INSTALL_OTHER"
            ;;
    esac
    exit 1
fi

# --- Dossier SSH ---
SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# --- Fichier de sauvegarde locale (IP, clé, user) ---
LOCAL_STATE="$SSH_DIR/.vpskit-local"
LOCAL_STATE_LEGACY="$SSH_DIR/.vps-bootstrap-local"
if [ ! -f "$LOCAL_STATE" ] && [ -f "$LOCAL_STATE_LEGACY" ]; then
    mv "$LOCAL_STATE_LEGACY" "$LOCAL_STATE"
fi

# =========================================
# FONCTION : SÉLECTION DE CLÉ SSH
# =========================================

select_ssh_key() {
    KEYS=()
    for key in "$SSH_DIR"/*; do
        if [ -f "$key" ] && [[ "$key" != *.pub ]] && [[ "$(basename "$key")" != "config"* ]] && [[ "$(basename "$key")" != "known_hosts"* ]] && [[ "$(basename "$key")" != ".vpskit"* ]] && [[ "$(basename "$key")" != ".vps-bootstrap"* ]]; then
            if [ -f "${key}.pub" ]; then
                KEYS+=("$key")
            fi
        fi
    done

    if [ ${#KEYS[@]} -gt 0 ]; then
        info "$MSG_SETUP_SSH_KEYS_FOUND"
        echo ""
        for i in "${!KEYS[@]}"; do
            KEYNAME=$(basename "${KEYS[$i]}")
            KEYTYPE=$(awk '{print $1}' "${KEYS[$i]}.pub" | sed 's/ssh-//')
            NUM=$((i + 1))
            echo "  ${NUM}) ${KEYNAME} (${KEYTYPE})"
        done
        NEW_NUM=$((${#KEYS[@]} + 1))
        echo ""
        echo -e "  ${NEW_NUM}) ${YELLOW}${MSG_SETUP_SSH_KEY_CREATE_NEW}${NC}"
        echo ""
        read -p "  $(printf "$MSG_SETUP_SSH_KEY_PROMPT_CHOICE" "$NEW_NUM")" KEY_CHOICE

        if [[ "$KEY_CHOICE" == "$NEW_NUM" ]]; then
            read -p "  $MSG_SETUP_SSH_KEY_PROMPT_NEW_NAME" CUSTOM_KEY_NAME
            CUSTOM_KEY_NAME=${CUSTOM_KEY_NAME:-vps}
            SSH_KEY="$SSH_DIR/$CUSTOM_KEY_NAME"
            ssh-keygen -t ed25519 -C "vpskit" -f "$SSH_KEY"
            success "$(printf "$MSG_SETUP_SSH_KEY_CREATED" "$SSH_KEY")"
        elif [[ "$KEY_CHOICE" =~ ^[0-9]+$ ]] && [ "$KEY_CHOICE" -ge 1 ] && [ "$KEY_CHOICE" -le "${#KEYS[@]}" ]; then
            SSH_KEY="${KEYS[$((KEY_CHOICE - 1))]}"
            success "$(printf "$MSG_SETUP_SSH_KEY_SELECTED" "$(basename "$SSH_KEY")")"
        else
            echo -e "${RED}${MSG_SETUP_SSH_KEY_INVALID_CHOICE}${NC}"
            exit 1
        fi
    else
        info "$MSG_SETUP_SSH_NO_KEY_FOUND"
        echo ""
        read -p "  $MSG_SETUP_SSH_KEY_PROMPT_NAME" CUSTOM_KEY_NAME
        if [[ -n "$CUSTOM_KEY_NAME" ]]; then
            SSH_KEY="$SSH_DIR/$CUSTOM_KEY_NAME"
        else
            SSH_KEY="$SSH_DIR/id_ed25519"
        fi
        ssh-keygen -t ed25519 -C "vpskit" -f "$SSH_KEY"
        success "$(printf "$MSG_SETUP_SSH_KEY_CREATED_NEW" "$SSH_KEY")"
    fi
}

# Explique l'echec de l'envoi de la cle et quitte
copy_key_failed() {
    local log="$1"
    echo ""
    if grep -qiE "password change required|required to change your password|password has expired" "$log" 2>/dev/null; then
        err "$MSG_SETUP_NEW_STEP3_PASSWORD_CHANGE_ERR"
        echo ""
        echo "  $MSG_SETUP_NEW_STEP3_PASSWORD_CHANGE_HINT1"
        echo ""
        echo -e "    ${GREEN}ssh ${INITIAL_USER}@${VPS_IP}${NC}"
        echo ""
        echo "  $MSG_SETUP_NEW_STEP3_PASSWORD_CHANGE_HINT2"
    else
        err "$MSG_SETUP_NEW_STEP3_COPY_FAILED"
        echo ""
        echo "  $MSG_SETUP_NEW_STEP3_COPY_FAILED_HINT"
        echo "  ssh-copy-id -i '${SSH_KEY}.pub' ${INITIAL_USER}@${VPS_IP}"
    fi
    exit 1
}

# =========================================
# CHOIX DU MODE
# =========================================

MODE=""

# Si une session locale existe, proposer la reprise directe
if [ -f "$LOCAL_STATE" ]; then
    VPS_IP=$(read_state_var "$LOCAL_STATE" "VPS_IP")
    SSH_KEY=$(read_state_var "$LOCAL_STATE" "SSH_KEY")
    USERNAME=$(read_state_var "$LOCAL_STATE" "USERNAME")
    INITIAL_USER=$(read_state_var "$LOCAL_STATE" "INITIAL_USER") || true
    if [[ -n "${VPS_IP:-}" && -n "${SSH_KEY:-}" && -n "${USERNAME:-}" ]]; then
        echo ""
        warn "$MSG_SETUP_SESSION_DETECTED"
        echo "    $(printf "$MSG_SETUP_SESSION_IP" "$VPS_IP")"
        echo "    $(printf "$MSG_SETUP_SESSION_KEY" "$(basename "$SSH_KEY")")"
        echo "    $(printf "$MSG_SETUP_SESSION_USER" "$USERNAME")"
        echo ""
        read -p "  $MSG_SETUP_SESSION_RESUME_PROMPT" RESUME_REPLY
        if [[ "$RESUME_REPLY" == "o" || "$RESUME_REPLY" == "O" || "$RESUME_REPLY" == "y" || "$RESUME_REPLY" == "Y" ]]; then
            MODE="update"
        fi
    fi
fi

# Sinon, demander le mode
if [ -z "$MODE" ]; then
    echo ""
    echo "  $MSG_SETUP_MODE_NEW"
    echo "  $MSG_SETUP_MODE_UPDATE"
    echo ""
    read -p "  $MSG_SETUP_MODE_PROMPT" MODE_CHOICE
    case "$MODE_CHOICE" in
        2) MODE="update" ;;
        *) MODE="new" ;;
    esac
fi

# =========================================
# MODE 1 : NOUVEAU VPS
# =========================================

if [ "$MODE" = "new" ]; then

    echo ""
    echo -e "${BOLD}${MSG_SETUP_NEW_PART1_TITLE}${NC}"

    # --- Clé SSH ---
    step "$MSG_SETUP_NEW_STEP1_TITLE" "$(echo -e "$MSG_SETUP_NEW_STEP1_DESC")"

    select_ssh_key

    echo ""
    info "$MSG_SETUP_NEW_PUBKEY_INFO"
    echo ""
    echo "  $(cat "${SSH_KEY}.pub")"
    echo ""

    # --- IP du serveur ---
    step "$MSG_SETUP_NEW_STEP2_TITLE" "$(echo -e "$MSG_SETUP_NEW_STEP2_DESC")"

    read -p "  $MSG_SETUP_NEW_IP_PROMPT" VPS_IP

    if [[ -z "$VPS_IP" ]]; then
        err "$MSG_SETUP_NEW_IP_REQUIRED_ERR"
        exit 1
    fi

    if ! echo "$VPS_IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        err "$(printf "$MSG_SETUP_NEW_IP_INVALID_ERR" "$VPS_IP")"
        echo "  $MSG_SETUP_NEW_IP_FORMAT"
        exit 1
    fi

    # --- Compte initial du serveur ---
    echo ""
    read -p "  $MSG_SETUP_NEW_INITIAL_USER_PROMPT" INITIAL_USER
    INITIAL_USER=${INITIAL_USER:-root}

    # --- Envoyer la clé SSH ---
    step "$MSG_SETUP_NEW_STEP3_TITLE" "$(echo -e "$MSG_SETUP_NEW_STEP3_DESC")"

    if confirm; then
        # La sortie est conservee pour reconnaitre le cas du mot de passe a changer
        # au premier login (Hetzner et d'autres hebergeurs) : la commande distante
        # est refusee avec "Password change required but no TTY available".
        COPY_LOG=$(mktemp)
        _CLEANUP_FILES+=("$COPY_LOG")
        if command -v ssh-copy-id &>/dev/null; then
            if ! ssh-copy-id -i "${SSH_KEY}.pub" "${INITIAL_USER}@${VPS_IP}" 2>&1 | tee "$COPY_LOG"; then
                copy_key_failed "$COPY_LOG"
            fi
        else
            info "$MSG_SETUP_NEW_STEP3_MANUAL_SEND"
            if ! ssh "${INITIAL_USER}@${VPS_IP}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" < "${SSH_KEY}.pub" 2>&1 | tee "$COPY_LOG"; then
                copy_key_failed "$COPY_LOG"
            fi
        fi
        success "$MSG_SETUP_NEW_STEP3_SUCCESS"
    else
        warn "$MSG_SETUP_NEW_STEP3_SKIPPED"
    fi

    # --- Test de connexion ---
    echo ""
    info "$MSG_SETUP_NEW_CONNTEST_INFO"
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "${INITIAL_USER}@${VPS_IP}" "echo ok" &>/dev/null; then
        success "$MSG_SETUP_NEW_CONNTEST_OK"
    else
        err "$MSG_SETUP_NEW_CONNTEST_ERR"
        exit 1
    fi

    # --- Nom d'utilisateur ---
    echo ""
    echo -e "${BOLD}${MSG_SETUP_NEW_PART2_TITLE}${NC}"
    echo ""

    read -p "$MSG_SETUP_NEW_USERNAME_PROMPT" USERNAME
    USERNAME=${USERNAME:-deploy}

    SSH_USER="$INITIAL_USER"
    if [ "$INITIAL_USER" = "root" ]; then
        USE_SUDO=false
    else
        USE_SUDO=true
    fi

# =========================================
# MODE 2 : MISE À JOUR D'UN VPS EXISTANT
# =========================================

elif [ "$MODE" = "update" ]; then

    echo ""
    echo -e "${BOLD}${MSG_SETUP_UPDATE_TITLE}${NC}"

    # Si pas de session sauvegardée, demander les infos
    if [ -z "${SSH_KEY:-}" ]; then
        echo ""
        select_ssh_key
    fi

    if [ -z "${VPS_IP:-}" ]; then
        echo ""
        read -p "  $MSG_SETUP_UPDATE_IP_PROMPT" VPS_IP
        if [[ -z "$VPS_IP" ]]; then
            err "$MSG_SETUP_UPDATE_IP_REQUIRED_ERR"
            exit 1
        fi
        if ! echo "$VPS_IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
            err "$(printf "$MSG_SETUP_UPDATE_IP_INVALID_ERR" "$VPS_IP")"
            echo "  $MSG_SETUP_UPDATE_IP_FORMAT"
            exit 1
        fi
    fi

    if [ -z "${USERNAME:-}" ]; then
        read -p "  $MSG_SETUP_UPDATE_USERNAME_PROMPT" USERNAME
        USERNAME=${USERNAME:-deploy}
    fi

    # --- Test de connexion (user d'abord, root en fallback) ---
    echo ""
    info "$MSG_SETUP_UPDATE_CONNTEST_INFO"
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "${USERNAME}@${VPS_IP}" "echo ok" &>/dev/null; then
        SSH_USER="$USERNAME"
        USE_SUDO=true
        success "$(printf "$MSG_SETUP_UPDATE_CONNTEST_USER_OK" "$USERNAME")"
    elif ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "root@${VPS_IP}" "echo ok" &>/dev/null; then
        SSH_USER="root"
        USE_SUDO=false
        success "$MSG_SETUP_UPDATE_CONNTEST_ROOT_OK"
    elif [[ -n "${INITIAL_USER:-}" && "$INITIAL_USER" != "root" && "$INITIAL_USER" != "$USERNAME" ]] && \
         ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "${INITIAL_USER}@${VPS_IP}" "echo ok" &>/dev/null; then
        SSH_USER="$INITIAL_USER"
        USE_SUDO=true
        success "$(printf "$MSG_SETUP_UPDATE_CONNTEST_USER_OK" "$INITIAL_USER")"
    else
        err "$(printf "$MSG_SETUP_UPDATE_CONNTEST_ERR" "$USERNAME")"
        echo "  $MSG_SETUP_UPDATE_CONNTEST_HINT"
        exit 1
    fi

fi

# --- Sauvegarder la session locale ---
printf 'VPS_IP="%s"\nSSH_KEY="%s"\nUSERNAME="%s"\nINITIAL_USER="%s"\n' \
    "$VPS_IP" "$SSH_KEY" "$USERNAME" "${INITIAL_USER:-root}" > "$LOCAL_STATE"
chmod 600 "$LOCAL_STATE"

# =========================================
# PARTIE 2 : SÉCURISATION DU VPS (avec reprise)
# =========================================

# Créer le script distant dans un fichier temporaire
# (évite les conflits de parsing avec les case/esac dans $(cat << ...))
TMPSCRIPT=$(mktemp)
_CLEANUP_FILES+=("$TMPSCRIPT")
cat > "$TMPSCRIPT" << 'REMOTE_EOF'
#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

CURRENT_STEP="$RMSG_SETUP_STARTING"

# Error handler: logs the specific step where setup was aborted
_step_abort() {
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        echo ""
        if [ "$CURRENT_STEP" = "$RMSG_SETUP_STARTING" ]; then
            echo -e "${RED}[ERR] $RMSG_SETUP_ABORTED_GENERIC${NC}"
        else
            echo -e "${RED}[ERR] $(printf "$RMSG_SETUP_ABORTED_STEP" "$CURRENT_STEP")${NC}"
        fi
        echo -e "${RED}[ERR] $RMSG_SETUP_ABORT_HINT${NC}"
        echo -e "${RED}[ERR] $RMSG_SETUP_ABORT_RESUME${NC}"
    fi
}
trap _step_abort EXIT

USERNAME="__USERNAME__"
PROGRESS_FILE="/root/.vpskit-progress"
PROGRESS_FILE_LEGACY="/root/.vps-bootstrap-progress"

# Migrate legacy progress file if present (one-time)
if [ ! -f "$PROGRESS_FILE" ] && [ -f "$PROGRESS_FILE_LEGACY" ]; then
    mv "$PROGRESS_FILE_LEGACY" "$PROGRESS_FILE"
fi

# Créer le fichier de progression s'il n'existe pas
touch "$PROGRESS_FILE"

# =========================================
# DÉTECTION DE LA DISTRIBUTION
# =========================================

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_NAME="${NAME:-$ID}"
        case "$ID" in
            ubuntu|debian)
                DISTRO_FAMILY="debian"
                ;;
            almalinux|rocky|centos|rhel|fedora)
                DISTRO_FAMILY="rhel"
                ;;
            *)
                DISTRO_FAMILY="unknown"
                ;;
        esac
    else
        DISTRO_FAMILY="unknown"
        DISTRO_NAME="unknown"
    fi
}

detect_distro

if [ "$DISTRO_FAMILY" = "unknown" ]; then
    echo -e "${RED}[ERR] $(printf "$RMSG_SETUP_DISTRO_UNKNOWN_ERR" "${DISTRO_NAME}")${NC}"
    echo "  $RMSG_SETUP_DISTRO_SUPPORTED"
    echo "  $RMSG_SETUP_DISTRO_DEBIAN"
    echo "  $RMSG_SETUP_DISTRO_RHEL"
    exit 1
fi

echo -e "${BLUE}[INFO] $(printf "$RMSG_SETUP_DISTRO_DETECTED" "${DISTRO_NAME}" "${DISTRO_FAMILY}")${NC}"

# =========================================
# FONCTIONS D'ABSTRACTION
# =========================================

pkg_update() {
    case "$DISTRO_FAMILY" in
        debian)  apt update && apt upgrade -y ;;
        rhel)    dnf update -y ;;
    esac
}

pkg_install() {
    case "$DISTRO_FAMILY" in
        debian)  apt install -y "$@" ;;
        rhel)    dnf install -y "$@" ;;
    esac
}

# Garantit qu'un paquet indispensable est present (installe seulement si absent)
ensure_pkg() {
    local pkg="$1"
    if command -v "$pkg" >/dev/null 2>&1; then
        return 0
    fi
    case "$DISTRO_FAMILY" in
        debian)
            apt-get update
            pkg_install "$pkg"
            ;;
        rhel)
            pkg_install "$pkg"
            ;;
    esac
}

sudo_group() {
    case "$DISTRO_FAMILY" in
        debian)  echo "sudo" ;;
        rhel)    echo "wheel" ;;
    esac
}

create_user() {
    local user="$1"
    local grp
    grp=$(sudo_group)
    case "$DISTRO_FAMILY" in
        debian)
            adduser --disabled-password --gecos "" "$user"
            ;;
        rhel)
            useradd -m -s /bin/bash "$user"
            ;;
    esac
    usermod -aG "$grp" "$user"
    echo "$user ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$user"
    chmod 440 "/etc/sudoers.d/$user"
}

# Force une directive sshd : remplace la ligne (commentee ou non), sinon l'ajoute
set_sshd_option() {
    local key="$1" value="$2"
    if grep -qE "^#?[[:space:]]*${key}[[:space:]]" /etc/ssh/sshd_config; then
        sed -i "s/^#\{0,1\}[[:space:]]*${key}[[:space:]].*/${key} ${value}/" /etc/ssh/sshd_config
    else
        echo "${key} ${value}" >> /etc/ssh/sshd_config
    fi
}

restart_ssh() {
    # Pas de "systemctl list-units | grep -q" : sous pipefail, grep -q ferme le
    # tube avant la fin de l'ecriture et systemctl sort en 141 une fois sur deux.
    systemctl restart sshd 2>/dev/null || systemctl restart ssh
}

setup_firewall() {
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install ufw
            ufw default deny incoming
            ufw default allow outgoing
            ufw allow 22/tcp
            ufw allow 80/tcp
            ufw allow 443/tcp
            ufw --force enable
            ;;
        rhel)
            # Absent des images cloud minimales (ex. AlmaLinux chez Hetzner)
            pkg_install firewalld
            systemctl start firewalld
            systemctl enable firewalld
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            # Ouvert par defaut sur RHEL, inutile ici (port 9090)
            firewall-cmd --permanent --remove-service=cockpit >/dev/null 2>&1 || true
            firewall-cmd --reload
            ;;
    esac
}

setup_caddy() {
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install debian-keyring debian-archive-keyring apt-transport-https curl
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
            apt update
            apt install -y caddy
            ;;
        rhel)
            dnf install -y 'dnf-command(copr)'
            dnf copr enable -y @caddy/caddy
            dnf install -y caddy
            ;;
    esac
    # Le paquet Debian demarre Caddy tout seul, pas le paquet copr
    systemctl enable --now caddy
}

install_docker() {
    case "$DISTRO_FAMILY" in
        debian)
            curl -fsSL https://get.docker.com | sh
            ;;
        rhel)
            # get.docker.com refuse AlmaLinux et Rocky ("Unsupported distribution") :
            # on passe par le depot Docker officiel (centos pour la famille RHEL)
            local repo_os="centos"
            [ "$DISTRO_ID" = "fedora" ] && repo_os="fedora"
            dnf install -y dnf-plugins-core
            dnf config-manager --add-repo "https://download.docker.com/linux/${repo_os}/docker-ce.repo"
            dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            systemctl enable --now docker
            ;;
    esac
}

setup_auto_updates() {
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install unattended-upgrades
            echo 'Unattended-Upgrade::Automatic-Reboot "false";' > /etc/apt/apt.conf.d/51auto-upgrades
            dpkg-reconfigure -f noninteractive unattended-upgrades
            ;;
        rhel)
            pkg_install dnf-automatic
            sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
            systemctl enable --now dnf-automatic.timer
            ;;
    esac
}

setup_motd() {
    local MOTD_SCRIPT='#!/bin/bash
GREEN='"'"'\033[0;32m'"'"'
YELLOW='"'"'\033[1;33m'"'"'
RED='"'"'\033[0;31m'"'"'
BOLD='"'"'\033[1m'"'"'
NC='"'"'\033[0m'"'"'

HOSTNAME=$(hostname)
OS=$(. /etc/os-release && echo "$PRETTY_NAME")
UPTIME=$(uptime -p 2>/dev/null | sed "s/up //" || echo "N/A")
LOAD=$(cat /proc/loadavg | awk "{print \$1, \$2, \$3}")
CPU_CORES=$(nproc)

RAM_TOTAL=$(free -m | awk "/Mem:/ {print \$2}")
RAM_USED=$(free -m | awk "/Mem:/ {print \$3}")
if [ "$RAM_TOTAL" -gt 0 ] 2>/dev/null; then
    RAM_PCT=$((RAM_USED * 100 / RAM_TOTAL))
else
    RAM_PCT=0
fi

SWAP_TOTAL=$(free -m | awk "/Swap:/ {print \$2}")
SWAP_USED=$(free -m | awk "/Swap:/ {print \$3}")
if [ "$SWAP_TOTAL" -gt 0 ] 2>/dev/null; then
    SWAP_PCT=$((SWAP_USED * 100 / SWAP_TOTAL))
else
    SWAP_PCT=0
fi

DISK_TOTAL=$(df -h / | awk "NR==2 {print \$2}")
DISK_USED=$(df -h / | awk "NR==2 {print \$3}")
DISK_PCT=$(df / | awk "NR==2 {print \$5}" | tr -d "%")

IP=$(hostname -I 2>/dev/null | awk "{print \$1}" || echo "N/A")

if command -v docker &>/dev/null; then
    DOCKER_COUNT=$(docker ps -q 2>/dev/null | wc -l | tr -d " ")
    DOCKER_LINE="  Docker     : __MOTD_DOCKER__"
else
    DOCKER_LINE=""
fi

color_pct() {
    if [ "$1" -lt 60 ]; then echo -e "${GREEN}${1}%${NC}"
    elif [ "$1" -lt 85 ]; then echo -e "${YELLOW}${1}%${NC}"
    else echo -e "${RED}${1}%${NC}"
    fi
}

echo ""
echo "========================================="
echo -e "  ${BOLD}${HOSTNAME}${NC} - ${OS}"
echo "========================================="
echo ""
echo "  Uptime     : ${UPTIME}"
echo "  Load       : ${LOAD}"
echo ""
echo "  CPU        : ${CPU_CORES} __MOTD_CORES__"
echo -e "  RAM        : ${RAM_USED} __MOTD_RAM_UNIT__ / ${RAM_TOTAL} __MOTD_RAM_UNIT__ ($(color_pct $RAM_PCT))"
echo -e "  Swap       : ${SWAP_USED} __MOTD_RAM_UNIT__ / ${SWAP_TOTAL} __MOTD_RAM_UNIT__ ($(color_pct $SWAP_PCT))"
echo -e "  __MOTD_DISK__     : ${DISK_USED} / ${DISK_TOTAL} ($(color_pct $DISK_PCT))"
echo ""
echo "  IP         : ${IP}"
if [ -n "$DOCKER_LINE" ]; then
    echo "$DOCKER_LINE"
fi
echo "========================================="
echo ""
'

    # Remplacer les placeholders MOTD par les labels traduits
    MOTD_DOCKER_LABEL=$(printf "$RMSG_MOTD_DOCKER" "\${DOCKER_COUNT}")
    MOTD_SCRIPT="${MOTD_SCRIPT//__MOTD_CORES__/$RMSG_MOTD_CORES}"
    MOTD_SCRIPT="${MOTD_SCRIPT//__MOTD_RAM_UNIT__/$RMSG_MOTD_RAM_UNIT}"
    MOTD_SCRIPT="${MOTD_SCRIPT//__MOTD_DISK__/$RMSG_MOTD_DISK}"
    MOTD_SCRIPT="${MOTD_SCRIPT//__MOTD_DOCKER__/$MOTD_DOCKER_LABEL}"

    case "$DISTRO_FAMILY" in
        debian)
            chmod -x /etc/update-motd.d/* 2>/dev/null || true
            echo "$MOTD_SCRIPT" > /etc/update-motd.d/99-vps-dashboard
            chmod +x /etc/update-motd.d/99-vps-dashboard
            ;;
        rhel)
            echo "$MOTD_SCRIPT" > /etc/profile.d/vps-dashboard.sh
            chmod +x /etc/profile.d/vps-dashboard.sh
            ;;
    esac
}

# =========================================
# PROGRESSION ET INTERACTION
# =========================================

is_done() {
    grep -q "^$1$" "$PROGRESS_FILE" 2>/dev/null
}

mark_done() {
    echo "$1" >> "$PROGRESS_FILE"
}

confirm_step() {
    CURRENT_STEP="$1"
    echo ""
    echo -e "${YELLOW}[>] $1${NC}"
    echo "  $2"
    echo ""
    read -p "  $RMSG_SETUP_STEP_EXECUTE_PROMPT" REPLY
    [[ "$REPLY" == "o" || "$REPLY" == "O" || "$REPLY" == "y" || "$REPLY" == "Y" ]]
}

done_step() {
    echo -e "  ${GREEN}[OK] $1${NC}"
}

skip_step() {
    echo -e "  ${GREEN}[OK] $1 $RMSG_SETUP_STEP_ALREADY_DONE${NC}"
}

# =========================================
# ÉTAPES DE SÉCURISATION
# =========================================

# === Prérequis obligatoire : sudo ===
# Executé à chaque run (non lié au fichier de progression) car sudo est requis
# par l'étape 2 et par tous les scripts vpskit ultérieurs.
CURRENT_STEP="$RMSG_SETUP_PREREQ_TITLE"
if command -v sudo >/dev/null 2>&1; then
    echo -e "  ${GREEN}[OK] $RMSG_SETUP_PREREQ_SUDO_OK${NC}"
else
    echo -e "${YELLOW}[INFO] $RMSG_SETUP_PREREQ_SUDO_INSTALL${NC}"
    ensure_pkg sudo
    echo -e "  ${GREEN}[OK] $RMSG_SETUP_PREREQ_SUDO_DONE${NC}"
fi

# === 1/9 ===
if is_done "step1"; then
    skip_step "$RMSG_SETUP_STEP1_TITLE"
elif confirm_step "$RMSG_SETUP_STEP1_TITLE" "$RMSG_SETUP_STEP1_DESC"; then
    pkg_update
    pkg_install git curl wget
    mark_done "step1"
    done_step "$RMSG_SETUP_STEP1_DONE"
fi

# === 2/9 ===
if is_done "step2"; then
    skip_step "$(printf "$RMSG_SETUP_STEP2_TITLE" "$USERNAME")"
elif confirm_step "$(printf "$RMSG_SETUP_STEP2_TITLE" "$USERNAME")" "$RMSG_SETUP_STEP2_DESC"; then
    if ! id "$USERNAME" &>/dev/null; then
        create_user "$USERNAME"
        done_step "$(printf "$RMSG_SETUP_STEP2_CREATED" "$USERNAME")"
    else
        echo -e "  ${BLUE}[INFO] $(printf "$RMSG_SETUP_STEP2_ALREADY_EXISTS" "$USERNAME")${NC}"
        SUDO_GRP=$(sudo_group)
        if ! groups "$USERNAME" | grep -q "$SUDO_GRP"; then
            usermod -aG "$SUDO_GRP" "$USERNAME"
            echo -e "  ${BLUE}[INFO] $(printf "$RMSG_SETUP_STEP2_GROUP_ADDED" "$SUDO_GRP")${NC}"
        fi
        if [ ! -f "/etc/sudoers.d/$USERNAME" ]; then
            echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
            chmod 440 "/etc/sudoers.d/$USERNAME"
            echo -e "  ${BLUE}[INFO] $RMSG_SETUP_STEP2_SUDOERS_ADDED${NC}"
        fi
        done_step "$(printf "$RMSG_SETUP_STEP2_DONE_EXISTING" "$USERNAME")"
    fi
    mark_done "step2"
fi

# === 3/9 ===
if is_done "step3"; then
    skip_step "$(printf "$RMSG_SETUP_STEP3_TITLE" "$USERNAME")"
elif confirm_step "$(printf "$RMSG_SETUP_STEP3_TITLE" "$USERNAME")" "$(printf "$RMSG_SETUP_STEP3_DESC" "$USERNAME")"; then
    mkdir -p "/home/$USERNAME/.ssh"
    if [ -f /root/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ]; then
        cp /root/.ssh/authorized_keys "/home/$USERNAME/.ssh/"
    elif [ "__SSH_USER__" != "root" ] && [ -f "/home/__SSH_USER__/.ssh/authorized_keys" ] && [ -s "/home/__SSH_USER__/.ssh/authorized_keys" ]; then
        cp "/home/__SSH_USER__/.ssh/authorized_keys" "/home/$USERNAME/.ssh/"
    else
        touch "/home/$USERNAME/.ssh/authorized_keys"
    fi
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
    chmod 700 "/home/$USERNAME/.ssh"
    chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
    mark_done "step3"
    done_step "$(printf "$RMSG_SETUP_STEP3_DONE" "$USERNAME")"
fi

# === 4/9 ===
if is_done "step4"; then
    skip_step "$RMSG_SETUP_STEP4_TITLE"
elif confirm_step "$RMSG_SETUP_STEP4_TITLE" "$RMSG_SETUP_STEP4_DESC"; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    set_sshd_option PermitRootLogin no
    set_sshd_option PasswordAuthentication no
    set_sshd_option PubkeyAuthentication yes
    # Les images cloud (cloud-init) deposent un fichier dans sshd_config.d/ qui est
    # inclus en tete de sshd_config : la premiere valeur lue gagne, donc il ecrase
    # les notres. On depose un fichier trie avant (00-) avec les memes directives.
    if grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
        mkdir -p /etc/ssh/sshd_config.d
        printf 'PermitRootLogin no\nPasswordAuthentication no\nPubkeyAuthentication yes\n' > /etc/ssh/sshd_config.d/00-vpskit-hardening.conf
        chmod 600 /etc/ssh/sshd_config.d/00-vpskit-hardening.conf
    fi
    if sshd -t 2>/dev/null; then
        restart_ssh
        # Verifier la configuration effective, pas seulement le fichier
        SSHD_EFFECTIVE=$(sshd -T 2>/dev/null || true)
        if grep -qx "passwordauthentication no" <<< "$SSHD_EFFECTIVE" && grep -qx "permitrootlogin no" <<< "$SSHD_EFFECTIVE"; then
            mark_done "step4"
            done_step "$RMSG_SETUP_STEP4_DONE"
        else
            echo -e "${YELLOW}[WARN] $RMSG_SETUP_STEP4_NOT_EFFECTIVE_WARN${NC}"
            echo "  $RMSG_SETUP_STEP4_NOT_EFFECTIVE_HINT"
        fi
    else
        echo -e "${RED}[ERR] $RMSG_SETUP_STEP4_INVALID_CONFIG_ERR${NC}"
        cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        restart_ssh
        echo -e "${YELLOW}[WARN] $RMSG_SETUP_STEP4_RESTORED_WARN${NC}"
    fi
fi

# === 5/9 ===
if is_done "step5"; then
    skip_step "$RMSG_SETUP_STEP5_TITLE"
elif confirm_step "$RMSG_SETUP_STEP5_TITLE" "$RMSG_SETUP_STEP5_DESC"; then
    setup_firewall
    mark_done "step5"
    done_step "$RMSG_SETUP_STEP5_DONE"
fi

# === Fail2ban ===
if is_done "step_fail2ban"; then
    skip_step "$RMSG_SETUP_FAIL2BAN_TITLE"
elif confirm_step "$RMSG_SETUP_FAIL2BAN_TITLE" "$RMSG_SETUP_FAIL2BAN_DESC"; then
    if [ "$DISTRO_FAMILY" = "rhel" ]; then
        pkg_install epel-release 2>/dev/null || true
    fi
    pkg_install fail2ban

    cat > /etc/fail2ban/jail.local << 'F2B_BLOCK'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
backend = systemd
F2B_BLOCK

    systemctl enable --now fail2ban
    mark_done "step_fail2ban"
    done_step "$RMSG_SETUP_FAIL2BAN_DONE"
fi

# === 6/9 ===
if is_done "step6"; then
    skip_step "$RMSG_SETUP_STEP6_TITLE"
elif confirm_step "$RMSG_SETUP_STEP6_TITLE" "$RMSG_SETUP_STEP6_DESC"; then
    if ! command -v docker &>/dev/null; then
        install_docker
        usermod -aG docker "$USERNAME"
        done_step "$RMSG_SETUP_STEP6_INSTALLED"
    else
        done_step "$RMSG_SETUP_STEP6_ALREADY"
    fi

    # Rotation des logs Docker (evite que les logs remplissent le disque)
    if [ ! -f /etc/docker/daemon.json ] || ! grep -q "max-size" /etc/docker/daemon.json 2>/dev/null; then
        mkdir -p /etc/docker
        # Certains hebergeurs (Hetzner) ne donnent que des resolveurs IPv6 dans
        # /etc/resolv.conf : docker run se rabat sur des DNS publics mais pas
        # docker build, qui echoue alors en "DNS: transient error".
        DOCKER_DNS_LINE=""
        if ! grep -qE '^nameserver[[:space:]]+[0-9]+\.' /etc/resolv.conf 2>/dev/null; then
            DOCKER_DNS_LINE='    "dns": ["1.1.1.1", "8.8.8.8"],'
        fi
        # "ip" : les ports publies (-p 3000:3000, ports: dans compose) ecoutent sur
        # 127.0.0.1 au lieu de 0.0.0.0. Docker ajoute ses propres regles iptables
        # qui passent devant ufw/firewalld, donc sans cela toute app avec un
        # "ports:" est joignable depuis Internet malgre le firewall. Caddy parle
        # a localhost, rien ne change pour lui. Pour exposer volontairement un
        # port : "0.0.0.0:3000:3000".
        cat > /etc/docker/daemon.json << DOCKER_LOG_BLOCK
{
${DOCKER_DNS_LINE}
    "ip": "127.0.0.1",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
DOCKER_LOG_BLOCK
        # Ligne vide laissee par l'absence de "dns"
        sed -i '/^$/d' /etc/docker/daemon.json
        systemctl restart docker 2>/dev/null || true
        done_step "$RMSG_SETUP_STEP6_LOG_ROTATION"
        done_step "$RMSG_SETUP_STEP6_LOCAL_PORTS"
    fi

    mark_done "step6"
fi

# === 7/9 ===
if is_done "step7"; then
    skip_step "$RMSG_SETUP_STEP7_TITLE"
elif confirm_step "$RMSG_SETUP_STEP7_TITLE" "$RMSG_SETUP_STEP7_DESC"; then
    if ! command -v caddy &>/dev/null; then
        setup_caddy
        done_step "$RMSG_SETUP_STEP7_INSTALLED"
    else
        done_step "$RMSG_SETUP_STEP7_ALREADY"
    fi
    mark_done "step7"
fi

# === 8/9 ===
if is_done "step8"; then
    skip_step "$RMSG_SETUP_STEP8_TITLE"
elif confirm_step "$RMSG_SETUP_STEP8_TITLE" "$RMSG_SETUP_STEP8_DESC"; then
    setup_auto_updates
    mark_done "step8"
    done_step "$RMSG_SETUP_STEP8_DONE"
fi

# === 9/9 ===
if is_done "step9"; then
    skip_step "$RMSG_SETUP_STEP9_TITLE"
elif confirm_step "$RMSG_SETUP_STEP9_TITLE" "$RMSG_SETUP_STEP9_DESC"; then
    setup_motd
    mark_done "step9"
    done_step "$RMSG_SETUP_STEP9_DONE"
fi

# === Dossier apps ===
mkdir -p "/home/$USERNAME/apps"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/apps"

echo ""
echo "========================================="
echo -e "  ${GREEN}${RMSG_SETUP_FINAL_TITLE}${NC}"
echo "========================================="
echo ""
echo "  $(printf "$RMSG_SETUP_FINAL_DISTRO" "$DISTRO_NAME")"
echo ""
echo "  $RMSG_SETUP_FINAL_INSTALLED"
echo "    [OK] $USERNAME (sudo)"
echo "    [OK] SSH key only"
echo "    [OK] Root disabled"
echo "    [OK] Firewall (22, 80, 443)"
echo "    [OK] Fail2ban (anti-brute-force)"
echo "    [OK] Docker + log rotation"
echo "    [OK] Caddy (reverse proxy + SSL)"
echo "    [OK] Git"
echo "    [OK] Auto updates"
echo "    [OK] MOTD dashboard"
echo "========================================="
REMOTE_EOF

# =========================================
# INJECTION DES MESSAGES DE LANGUE
# =========================================

inject_lang_into_remote "$TMPSCRIPT"

# Remplacer le placeholder USERNAME (compatible macOS et Linux)
SAFE_USERNAME=$(sed_escape "$USERNAME")
SAFE_SSH_USER=$(sed_escape "$SSH_USER")
if [ "$OS" = "mac" ]; then
    sed -i '' "s|__USERNAME__|$SAFE_USERNAME|g" "$TMPSCRIPT"
    sed -i '' "s|__SSH_USER__|$SAFE_SSH_USER|g" "$TMPSCRIPT"
else
    sed -i "s|__USERNAME__|$SAFE_USERNAME|g" "$TMPSCRIPT"
    sed -i "s|__SSH_USER__|$SAFE_SSH_USER|g" "$TMPSCRIPT"
fi

# Envoyer le script sur le serveur et l'exécuter (nom aleatoire pour eviter les attaques symlink)
REMOTE_TMP=$(ssh -i "$SSH_KEY" -o BatchMode=yes "${SSH_USER}@${VPS_IP}" "mktemp /tmp/vps-XXXXXXXXXX.sh")
if ! scp -i "$SSH_KEY" "$TMPSCRIPT" "${SSH_USER}@${VPS_IP}:${REMOTE_TMP}"; then
    err "$MSG_SETUP_SCP_ERR"
    rm -f "$TMPSCRIPT"
    exit 1
fi
rm -f "$TMPSCRIPT"

# Vérifier que sudo existe à distance : sans lui, "sudo bash ..." échouerait
# avant le démarrage du script (impossible à réparer depuis l'intérieur).
if [ "$USE_SUDO" = true ]; then
    if ! ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "${SSH_USER}@${VPS_IP}" command -v sudo &>/dev/null; then
        err "$(printf "$MSG_SETUP_SUDO_MISSING_ERR" "${SSH_USER}@${VPS_IP}")"
        echo "  $MSG_SETUP_SUDO_MISSING_HINT"
        exit 1
    fi
fi

if [ "$USE_SUDO" = true ]; then
    REMOTE_CMD="sudo bash '${REMOTE_TMP}'"
else
    REMOTE_CMD="bash '${REMOTE_TMP}'"
fi
if ! ssh -t -i "$SSH_KEY" "${SSH_USER}@${VPS_IP}" "chmod 700 '${REMOTE_TMP}' && ${REMOTE_CMD}; _rc=\$?; rm -f '${REMOTE_TMP}'; exit \$_rc"; then
    err "$MSG_SETUP_REMOTE_ERR"
    echo "  $MSG_SETUP_REMOTE_ERR_HINT"
    exit 1
fi

# =========================================
# PARTIE 3 : INSTRUCTIONS POST-SETUP
# =========================================

echo ""
echo -e "${BOLD}${MSG_SETUP_POSTSETUP_TITLE}${NC}"
echo ""
echo "  $MSG_SETUP_POSTSETUP_CONNECT_HINT"
echo ""
echo -e "    ${GREEN}ssh ${USERNAME}@${VPS_IP}${NC}"
echo ""

if [[ "$SSH_KEY" != "$SSH_DIR/id_ed25519" ]]; then
    echo "  $MSG_SETUP_POSTSETUP_SPECIFIC_KEY"
    echo ""
    echo -e "    ${GREEN}ssh -i ${SSH_KEY} ${USERNAME}@${VPS_IP}${NC}"
    echo ""
fi

echo "  $MSG_SETUP_POSTSETUP_SHORTCUT_OFFER"
echo "  $MSG_SETUP_POSTSETUP_SHORTCUT_EXPLAIN"
echo ""
read -p "  $MSG_SETUP_POSTSETUP_SHORTCUT_PROMPT" CREATE_CONFIG
if [[ "$CREATE_CONFIG" == "o" || "$CREATE_CONFIG" == "O" || "$CREATE_CONFIG" == "y" || "$CREATE_CONFIG" == "Y" ]]; then
    read -p "  $MSG_SETUP_POSTSETUP_ALIAS_PROMPT" SSH_ALIAS
    SSH_ALIAS=${SSH_ALIAS:-vps}

    {
        echo ""
        echo "Host $SSH_ALIAS"
        echo "    HostName ${VPS_IP}"
        echo "    User ${USERNAME}"
        echo "    IdentityFile ${SSH_KEY}"
    } >> "$SSH_DIR/config"
    chmod 600 "$SSH_DIR/config"

    success "$MSG_SETUP_POSTSETUP_SHORTCUT_OK"
    echo ""
    echo -e "    ${GREEN}ssh ${SSH_ALIAS}${NC}"
else
    info "$MSG_SETUP_POSTSETUP_SHORTCUT_SKIP"
fi

echo ""
echo "  $MSG_SETUP_POSTSETUP_APPS_DIR"
echo ""
echo "========================================="
echo -e "  ${GREEN}${MSG_SETUP_POSTSETUP_DONE_TITLE}${NC}"
echo "========================================="
