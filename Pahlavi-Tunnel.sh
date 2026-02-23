#!/usr/bin/env bash
set -euo pipefail

APP_NAME="emad"
TG_ID="@emad1381"
VERSION="2.0.0"

GITHUB_REPO="github.com/emad1381/Pahlavi-tunnel"

# MUST match GitHub file name exactly:
SCRIPT_FILENAME="Pahlavi-Tunnel.sh"
SELF_URL="https://raw.githubusercontent.com/emad1381/Pahlavi-tunnel/main/${SCRIPT_FILENAME}"

PY="/opt/emad/Pahlavi.py"
PY_URL="https://raw.githubusercontent.com/emad1381/Pahlavi-tunnel/main/Pahlavi.py"

INSTALL_PATH="/usr/local/bin/emad"

BASE="/etc/emad_manager"
CONF="$BASE/profiles"
MAX=10

HC_SCRIPT="/usr/local/bin/emad-health-check"
HC_CRON_TAG="# emadHealthCheck"

# Colors
if [[ -t 1 ]]; then
  CLR_RESET="\033[0m"; CLR_DIM="\033[2m"; CLR_BOLD="\033[1m"
  CLR_RED="\033[31m"; CLR_GREEN="\033[32m"; CLR_YELLOW="\033[33m"
  CLR_CYAN="\033[36m"; CLR_WHITE="\033[97m"
else
  CLR_RESET=""; CLR_DIM=""; CLR_BOLD=""
  CLR_RED=""; CLR_GREEN=""; CLR_YELLOW=""
  CLR_CYAN=""; CLR_WHITE=""
fi

need_root(){ [[ "$(id -u)" == "0" ]] || { echo "Run as root (sudo -i)"; exit 1; }; }
pause(){ read -r -p "Press Enter to continue..." _ < /dev/tty || true; }
have(){ command -v "$1" >/dev/null 2>&1; }

print_section(){
  local title="$1"
  echo -e "${CLR_DIM}------------------------------------------------------------${CLR_RESET}" > /dev/tty
  echo -e "${CLR_CYAN}${CLR_BOLD}${title}${CLR_RESET}" > /dev/tty
  echo -e "${CLR_DIM}------------------------------------------------------------${CLR_RESET}" > /dev/tty
}

read_port(){
  local prompt="$1" default="${2:-}" value
  while true; do
    if [[ -n "$default" ]]; then
      read -r -p "${prompt} [${default}]: " value < /dev/tty
      value="${value:-$default}"
    else
      read -r -p "${prompt}: " value < /dev/tty
    fi
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 )); then
      echo "$value"
      return 0
    fi
    echo "[!] Invalid port. Enter a number between 1 and 65535." > /dev/tty
  done
}

read_yes_no(){
  local prompt="$1" default="${2:-y}" value
  while true; do
    read -r -p "${prompt} (y/n) [${default}]: " value < /dev/tty
    value="${value:-$default}"
    case "${value,,}" in
      y|yes) echo "y"; return 0 ;;
      n|no) echo "n"; return 0 ;;
      *) echo "[!] Please enter y or n." > /dev/tty ;;
    esac
  done
}

apt_try_install(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y "$@" >/dev/null 2>&1 || true
}

fetch_url_to(){
  local url="$1" out="$2"
  if have curl; then
    curl -fsSL "$url" -o "$out"
  else
    have wget || apt_try_install wget
    wget -qO "$out" "$url"
  fi
}

is_installed(){ [[ -x "$INSTALL_PATH" ]]; }

ensure(){
  mkdir -p "$CONF"
  mkdir -p "$(dirname "$PY")"
  have screen  || apt_try_install screen
  have python3 || apt_try_install python3
  have curl    || apt_try_install curl
  have figlet  || apt_try_install figlet
  have ss      || apt_try_install iproute2
  have crontab || apt_try_install cron

  if [[ ! -f "$PY" ]]; then
    echo "[*] Python core not found. Downloading: $PY_URL" > /dev/tty
    fetch_url_to "$PY_URL" "$PY"
    chmod +x "$PY" || true
  fi
  [[ -f "$PY" ]] || { echo "Missing python file: $PY"; exit 1; }
}

install_script(){
  echo "[*] Installing to: $INSTALL_PATH" > /dev/tty
  mkdir -p "$(dirname "$INSTALL_PATH")"

  # If executed from a file path, copy it. Otherwise download from SELF_URL.
  if [[ -f "$0" ]] && [[ "$0" != "bash" ]] && [[ "$0" != "/dev/fd/"* ]]; then
    cp -f "$0" "$INSTALL_PATH"
  else
    fetch_url_to "$SELF_URL" "$INSTALL_PATH"
  fi
  chmod +x "$INSTALL_PATH"
  echo "[+] Installed. Run: sudo emad" > /dev/tty
}

update_script(){
  echo "[*] Updating from: $SELF_URL" > /dev/tty
  local tmp; tmp="$(mktemp)"
  fetch_url_to "$SELF_URL" "$tmp"

  if ! head -n 1 "$tmp" | grep -q "bash"; then
    echo "[-] Update failed: invalid file downloaded." > /dev/tty
    rm -f "$tmp"
    return 1
  fi
  chmod +x "$tmp"

  if is_installed; then
    mv -f "$tmp" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    echo "[+] Updated successfully." > /dev/tty
    echo "[i] Reloading updated manager now..." > /dev/tty
    exec "$INSTALL_PATH"
  else
    mv -f "$tmp" "./${SCRIPT_FILENAME}"
    chmod +x "./${SCRIPT_FILENAME}"
    echo "[+] Updated file saved locally: ./${SCRIPT_FILENAME}" > /dev/tty
    echo "[i] Reloading updated local script now..." > /dev/tty
    exec "./${SCRIPT_FILENAME}"
  fi
}

disable_cron_healthcheck(){
  local tmp; tmp="$(mktemp)"
  (crontab -l 2>/dev/null || true) | grep -vF "${HC_CRON_TAG}" >"$tmp" || true
  crontab "$tmp" || true
  rm -f "$tmp"
  echo "[+] Cron disabled." > /dev/tty
}

optimize_server(){
  echo "" > /dev/tty
  echo "[*] Optimizing network settings and enabling BBR if supported..." > /dev/tty

  # Ensure tools that are commonly missing on minimal images
  have sysctl  || apt_try_install procps
  have modprobe || apt_try_install kmod
  have ss || apt_try_install iproute2

  # Cron is optional but health-check uses crontab
  have crontab || apt_try_install cron

  # Try loading BBR module (no hard fail)
  modprobe tcp_bbr >/dev/null 2>&1 || true

  if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
    echo "[+] BBR is available." > /dev/tty

    # Apply runtime settings
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true

    # Persist settings (idempotent, separate file)
    local conf="/etc/sysctl.d/99-emad.conf"
    cat > "$conf" <<'EOF'
# emad tunnel - network tuning
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Socket buffer ceilings (reasonable defaults)
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF

    sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1 || true

    echo "[+] Applied sysctl tuning." > /dev/tty
    echo "[i] tcp_congestion_control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" > /dev/tty
    echo "[i] default_qdisc:         $(sysctl -n net.core.default_qdisc 2>/dev/null)" > /dev/tty
  else
    echo "[!] BBR is NOT available on this kernel." > /dev/tty
    echo "[i] Available: $(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)" > /dev/tty
    echo "[i] Hint: upgrade kernel to use BBR." > /dev/tty
  fi
}

uninstall_script(){
  disable_cron_healthcheck >/dev/null 2>&1 || true
  rm -f "$HC_SCRIPT" >/dev/null 2>&1 || true
  rm -f "$INSTALL_PATH" >/dev/null 2>&1 || true
  echo "[+] Uninstalled: $INSTALL_PATH" > /dev/tty
}

# Info (best-effort)
get_public_ip(){ [[ "${EMAD_FAST_BANNER:-1}" == "1" ]] && { echo ""; return 0; }; curl -fsSL --max-time 2 https://api.ipify.org 2>/dev/null || true; }
get_ipinfo_field(){
  local field="$1" ip="$2"
  [[ -n "$ip" ]] || { echo ""; return 0; }
  local json
  json="$(curl -fsSL --max-time 4 "https://ipinfo.io/${ip}/json" 2>/dev/null || true)"
  [[ -n "$json" ]] || { echo ""; return 0; }
  echo "$json" | tr -d '\n' | sed -n "s/.*\"${field}\":[ ]*\"\\([^\"]*\\)\".*/\\1/p" | head -n1
}
get_location_string(){
  local ip city region country
  ip="$(get_public_ip)"
  city="$(get_ipinfo_field city "$ip")"
  region="$(get_ipinfo_field region "$ip")"
  country="$(get_ipinfo_field country "$ip")"
  if [[ -n "$city" || -n "$region" || -n "$country" ]]; then
    echo "${city}${city:+, }${region}${region:+, }${country}"
  else
    echo "Unknown"
  fi
}
get_datacenter_string(){
  local ip org
  ip="$(get_public_ip)"
  org="$(get_ipinfo_field org "$ip")"
  [[ -n "$org" ]] && echo "$org" || echo "Unknown"
}

# Profiles
pick_role(){
  while true; do
    printf "1) EU\n2) IRAN\n" > /dev/tty
    read -r -p "Select: " x < /dev/tty
    if [[ "$x" == "1" ]]; then echo "eu"; return 0; fi
    if [[ "$x" == "2" ]]; then echo "iran"; return 0; fi
    echo "Invalid." > /dev/tty
  done
}
slot_status(){ local role="$1" i="$2"; [[ -f "$CONF/${role}${i}.env" ]] && echo "[saved]" || echo "(empty)"; }
pick_slot(){
  local role="$1"
  echo "" > /dev/tty
  echo "Select ${role} slot (1..${MAX}):" > /dev/tty
  echo "--------------------------------" > /dev/tty
  for i in $(seq 1 "$MAX"); do
    printf "  %s) %s%s %s\n" "$i" "$role" "$i" "$(slot_status "$role" "$i")" > /dev/tty
  done
  echo "--------------------------------" > /dev/tty
  read -r -p "Slot number: " slot < /dev/tty
  [[ "$slot" =~ ^[0-9]+$ ]] && [[ "$slot" -ge 1 ]] && [[ "$slot" -le "$MAX" ]] || { echo "Invalid"; exit 1; }
  echo "${role}${slot}"
}
edit_profile(){
  local prof="$1" f="$CONF/${prof}.env" role="${prof%%[0-9]*}"
  print_section "Editing profile: $prof"

  if [[ "$role" == "eu" ]]; then
    read -r -p "Iran IP: " IRAN_IP < /dev/tty
    BRIDGE="$(read_port 'Bridge port' '7000')"
    SYNC="$(read_port 'Sync port' '7001')"
    cat >"$f" <<EOF
ROLE=eu
IRAN_IP=$IRAN_IP
BRIDGE=$BRIDGE
SYNC=$SYNC
EOF
  else
    BRIDGE="$(read_port 'Bridge port' '7000')"
    SYNC="$(read_port 'Sync port' '7001')"
    AS="$(read_yes_no 'Auto-Sync ports from EU?' 'y')"
    if [[ "$AS" == "y" ]]; then
      cat >"$f" <<EOF
ROLE=iran
BRIDGE=$BRIDGE
SYNC=$SYNC
AUTO_SYNC=true
PORTS=
EOF
    else
      read -r -p "Manual ports CSV (e.g. 80,443,2083): " PORTS < /dev/tty
      cat >"$f" <<EOF
ROLE=iran
BRIDGE=$BRIDGE
SYNC=$SYNC
AUTO_SYNC=false
PORTS=$PORTS
EOF
    fi
  fi
  echo "[+] Saved $f" > /dev/tty
}

session_name(){ echo "emad_$1"; }
is_running(){
  local prof="$1" s; s="$(session_name "$prof")"
  screen -ls 2>/dev/null | grep -q "\.${s}[[:space:]]"
}
run_slot(){
  local prof="$1" f="$CONF/${prof}.env"
  [[ -f "$f" ]] || { echo "Profile not found: $prof" > /dev/tty; return 1; }
  # shellcheck disable=SC1090
  source "$f"
  local s; s="$(session_name "$prof")"
  screen -S "$s" -X quit >/dev/null 2>&1 || true

  if [[ "$ROLE" == "eu" ]]; then
    screen -dmS "$s" bash -lc "ulimit -n ${ULIMIT_NOFILE:-65535} >/dev/null 2>&1 || true; printf '1\n%s\n%s\n%s\n' '$IRAN_IP' '$BRIDGE' '$SYNC' | PAHLAVI_POOL="${PAHLAVI_POOL:-0}" python3 '$PY'"
  else
    if [[ "${AUTO_SYNC:-true}" == "true" ]]; then
      screen -dmS "$s" bash -lc "ulimit -n ${ULIMIT_NOFILE:-65535} >/dev/null 2>&1 || true; printf '2\n%s\n%s\ny\n' '$BRIDGE' '$SYNC' | PAHLAVI_POOL="${PAHLAVI_POOL:-0}" python3 '$PY'"
    else
      screen -dmS "$s" bash -lc "ulimit -n ${ULIMIT_NOFILE:-65535} >/dev/null 2>&1 || true; printf '2\n%s\n%s\nn\n%s\n' '$BRIDGE' '$SYNC' '${PORTS:-}' | PAHLAVI_POOL="${PAHLAVI_POOL:-0}" python3 '$PY'"
    fi
  fi
  echo "[+] Started: $s" > /dev/tty
}
stop_slot(){ local prof="$1" s; s="$(session_name "$prof")"; screen -S "$s" -X quit >/dev/null 2>&1 || true; echo "[+] Stopped: $s" > /dev/tty; }
restart_slot(){ local prof="$1"; stop_slot "$prof" >/dev/null 2>&1 || true; sleep 0.5; run_slot "$prof"; }
status_slot(){
  local prof="$1" f="$CONF/${prof}.env"
  [[ -f "$f" ]] || { echo "Profile not found: $prof" > /dev/tty; return 1; }
  local st="${CLR_RED}OFF${CLR_RESET}"
  if is_running "$prof"; then st="${CLR_GREEN}ON${CLR_RESET}"; fi
  echo -e "Profile: $prof | Running: $st" > /dev/tty
}
delete_slot(){
  local prof="$1" f="$CONF/${prof}.env"
  stop_slot "$prof" >/dev/null 2>&1 || true
  if [[ -f "$f" ]]; then rm -f "$f"; echo "[+] Deleted: $f" > /dev/tty; else echo "[-] Not found: $f" > /dev/tty; fi
}
logs_slot(){ local prof="$1" s; s="$(session_name "$prof")"; echo "[i] Attach: $s (Ctrl+A then D)" > /dev/tty; screen -r "$s" || true; }

install_healthcheck_script(){
  cat >"$HC_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail
PY="${PY}"
CONF="${CONF}"
MAX="${MAX}"
session_name(){ echo "emad_\$1"; }
is_running(){ local prof="\$1" s; s="\$(session_name "\$prof")"; screen -ls 2>/dev/null | grep -q "\\.\${s}[[:space:]]"; }
start_from_profile(){
  local prof="\$1" f="\${CONF}/\${prof}.env"
  [[ -f "\$f" ]] || return 0
  # shellcheck disable=SC1090
  source "\$f"
  local s; s="\$(session_name "\$prof")"
  screen -S "\$s" -X quit >/dev/null 2>&1 || true
  if [[ "\${ROLE}" == "eu" ]]; then
    screen -dmS "\$s" bash -lc "ulimit -n ${ULIMIT_NOFILE:-65535} >/dev/null 2>&1 || true; printf '1\\n%s\\n%s\\n%s\\n' '\${IRAN_IP}' '\${BRIDGE}' '\${SYNC}' | PAHLAVI_POOL="\${PAHLAVI_POOL:-0}" python3 '\${PY}'"
  else
    if [[ "\${AUTO_SYNC:-true}" == "true" ]]; then
      screen -dmS "\$s" bash -lc "ulimit -n ${ULIMIT_NOFILE:-65535} >/dev/null 2>&1 || true; printf '2\\n%s\\n%s\\ny\\n' '\${BRIDGE}' '\${SYNC}' | PAHLAVI_POOL="\${PAHLAVI_POOL:-0}" python3 '\${PY}'"
    else
      screen -dmS "\$s" bash -lc "ulimit -n ${ULIMIT_NOFILE:-65535} >/dev/null 2>&1 || true; printf '2\\n%s\\n%s\\nn\\n%s\\n' '\${BRIDGE}' '\${SYNC}' '\${PORTS:-}' | PAHLAVI_POOL="\${PAHLAVI_POOL:-0}" python3 '\${PY}'"
    fi
  fi
}
[[ -f "\$PY" ]] || exit 0
for role in eu iran; do
  for i in \$(seq 1 "\$MAX"); do
    prof="\${role}\${i}"
    [[ -f "\${CONF}/\${prof}.env" ]] || continue
    if ! is_running "\$prof"; then start_from_profile "\$prof" >/dev/null 2>&1 || true; fi
  done
done
EOF
  chmod +x "$HC_SCRIPT"
}
enable_cron_healthcheck(){
  install_healthcheck_script

  echo "" > /dev/tty
  read -r -p "Enter interval in minutes (default: 1): " interval < /dev/tty || true
  interval=${interval:-1}

  if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
    echo "[!] Invalid number. Using default 1 minute." > /dev/tty
    interval=1
  fi
  if [ "$interval" -lt 1 ]; then interval=1; fi

  local line="*/$interval * * * * ${HC_SCRIPT} >/dev/null 2>&1 ${HC_CRON_TAG}"
  local tmp; tmp="$(mktemp)"
  (crontab -l 2>/dev/null || true) | grep -vF "${HC_CRON_TAG}" >"$tmp" || true
  echo "$line" >>"$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  echo "[+] Cron enabled (every $interval minute(s))." > /dev/tty
}

test_tunnel(){
  local role prof f bridge sync iran_ip attempts timeout_s
  print_section "Test Tunnel (Smart Pre-check)"
  role="$(pick_role)"
  prof="$(pick_slot "$role")"
  f="$CONF/${prof}.env"
  [[ -f "$f" ]] || { echo "Profile not found: $prof" > /dev/tty; return 1; }

  # shellcheck disable=SC1090
  source "$f"

  bridge="${BRIDGE:-7000}"
  sync="${SYNC:-7001}"
  attempts=3
  timeout_s=2.5

  if [[ "${ROLE:-}" != "eu" ]]; then
    echo "[i] Selected profile is IRAN. Looking for paired EU slot..." > /dev/tty
    local slot eu_prof eu_file
    slot="${prof//[!0-9]/}"
    eu_prof="eu${slot}"
    eu_file="$CONF/${eu_prof}.env"
    if [[ -f "$eu_file" ]]; then
      # shellcheck disable=SC1090
      source "$eu_file"
      echo "[i] Using paired EU profile: $eu_prof" > /dev/tty
      bridge="${BRIDGE:-$bridge}"
      sync="${SYNC:-$sync}"
    else
      echo "[!] No paired EU profile found for slot $slot." > /dev/tty
      echo "[!] Tip: run Test Tunnel using an EU profile for end-to-end remote check." > /dev/tty
      echo "[i] Local sanity checks:" > /dev/tty
      if ss -lntp 2>/dev/null | awk '{print $4}' | grep -E ":(${bridge}|${sync})$" >/dev/null 2>&1; then
        echo "[+] Bridge/Sync ports are in use on this host (${bridge}/${sync}) - likely listener is active." > /dev/tty
        echo "[i] Listener details:" > /dev/tty
        ss -lntp 2>/dev/null | grep -E ":(${bridge}|${sync})\b" > /dev/tty || true
      else
        echo "[~] Bridge/Sync ports seem free on this host (${bridge}/${sync})." > /dev/tty
        echo "[i] If this is the IRAN side, start tunnel first so EU can connect." > /dev/tty
      fi
      return 0
    fi
  fi

  iran_ip="${IRAN_IP:-}"
  if [[ -z "$iran_ip" ]]; then
    echo "[!] Missing IRAN_IP in selected/paired EU profile." > /dev/tty
    return 1
  fi

  echo "[i] Target IRAN IP: $iran_ip" > /dev/tty
  echo "[i] Testing bridge=${bridge} sync=${sync} attempts=${attempts}" > /dev/tty

  IRAN_IP="$iran_ip" BRIDGE_PORT="$bridge" SYNC_PORT="$sync" ATTEMPTS="$attempts" TIMEOUT_S="$timeout_s" \
  python3 - <<'PY' > /dev/tty
import os, socket, time

host = os.environ["IRAN_IP"]
ports = [("Bridge", int(os.environ["BRIDGE_PORT"])), ("Sync", int(os.environ["SYNC_PORT"]))]
attempts = int(os.environ.get("ATTEMPTS", "3"))
timeout_s = float(os.environ.get("TIMEOUT_S", "2.5"))

def probe(h, p):
    t0 = time.perf_counter()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout_s)
    try:
        s.connect((h, p))
        dt = (time.perf_counter() - t0) * 1000
        return True, dt, "ok"
    except Exception as e:
        return False, None, str(e)
    finally:
        try: s.close()
        except Exception: pass

try:
    infos = socket.getaddrinfo(host, None)
    ips = sorted({i[4][0] for i in infos})
    print(f"[+] DNS/resolve OK: {host} -> {', '.join(ips[:4])}")
except Exception as e:
    print(f"[-] DNS/resolve failed for {host}: {e}")
    raise SystemExit(2)

overall_ok = True
score = 0
max_score = len(ports) * attempts

for label, port in ports:
    ok_count = 0
    rtts = []
    last_err = ""
    for _ in range(attempts):
        ok, rtt, err = probe(host, port)
        if ok:
            ok_count += 1
            rtts.append(rtt)
            score += 1
        else:
            last_err = err
        time.sleep(0.15)

    if ok_count:
        avg = sum(rtts) / len(rtts)
        print(f"[+] {label} port {port}: reachable ({ok_count}/{attempts}), avg RTT={avg:.1f} ms")
    else:
        overall_ok = False
        print(f"[-] {label} port {port}: unreachable ({ok_count}/{attempts}) | last error: {last_err}")
        if "timed out" in last_err.lower():
            print(f"[i] Hint for {label}:{port} -> likely firewall/security-group/routing drop.")
        elif "refused" in last_err.lower():
            print(f"[i] Hint for {label}:{port} -> host reachable but no listener on that port.")

ratio = (score / max_score) * 100 if max_score else 0
print(f"[i] Tunnel readiness score: {score}/{max_score} ({ratio:.0f}%)")

if ratio >= 100:
    print("[+] SMART RESULT: Excellent. Tunnel creation should work.")
elif ratio >= 70:
    print("[~] SMART RESULT: Likely workable but unstable risk exists.")
elif ratio > 0:
    print("[~] SMART RESULT: Partial connectivity. Fix firewall/routing before creating tunnel.")
else:
    print("[-] SMART RESULT: Not ready. Tunnel creation will likely fail.")

if not overall_ok:
    print("[i] Next checks: open ports on IRAN firewall/provider panel, verify DNAT/security-group, then re-test.")
    raise SystemExit(1)
PY
}

print_banner(){
  local loc dc inst
  loc="$(get_location_string)"
  dc="$(get_datacenter_string)"
  inst="${CLR_RED}NOT INSTALLED${CLR_RESET}"
  if is_installed; then inst="${CLR_GREEN}INSTALLED${CLR_RESET}"; fi

  echo -e "${CLR_CYAN}${CLR_BOLD}"
  if have figlet; then
    figlet -f slant "$APP_NAME" 2>/dev/null || figlet "$APP_NAME" 2>/dev/null || true
  else
    echo "$APP_NAME"
  fi
  echo -e "${CLR_RESET}"

  echo -e "${CLR_GREEN}Version:${CLR_RESET} v${VERSION}"
  echo -e "${CLR_GREEN}GitHub:${CLR_RESET} ${GITHUB_REPO}"
  echo -e "${CLR_GREEN}Telegram ID:${CLR_RESET} ${TG_ID}"
  echo -e "${CLR_DIM}============================================================${CLR_RESET}"
  echo -e "${CLR_CYAN}Location:${CLR_RESET} ${loc}"
  echo -e "${CLR_CYAN}Datacenter:${CLR_RESET} ${dc}"
  echo -e "${CLR_CYAN}Script:${CLR_RESET} ${inst}"
  echo -e "${CLR_DIM}============================================================${CLR_RESET}"
}

manage_slot_menu(){
  local prof="$1"
  while true; do
    echo "" > /dev/tty
    echo -e "${CLR_YELLOW}${CLR_BOLD}Manage slot:${CLR_RESET} ${prof}" > /dev/tty
    echo "1) Show profile" > /dev/tty
    echo "2) Start" > /dev/tty
    echo "3) Stop" > /dev/tty
    echo "4) Restart" > /dev/tty
    echo "5) Status" > /dev/tty
    echo "6) Logs" > /dev/tty
    echo "7) Delete slot" > /dev/tty
    echo "0) Back" > /dev/tty
    read -r -p "Select: " c < /dev/tty
    case "$c" in
      1) cat "$CONF/${prof}.env" 2>/dev/null > /dev/tty || echo "Profile not found." > /dev/tty; pause ;;
      2) run_slot "$prof"; pause ;;
      3) stop_slot "$prof"; pause ;;
      4) restart_slot "$prof"; pause ;;
      5) status_slot "$prof"; pause ;;
      6) logs_slot "$prof" ;;
      7) delete_slot "$prof"; pause ;;
      0) return ;;
      *) echo "Invalid." > /dev/tty ;;
    esac
  done
}

# ===================== Main =====================
need_root
ensure

while true; do
  clear || true
  print_banner

  echo -e "${CLR_WHITE}${CLR_BOLD}1.${CLR_RESET} Create or update profile"
  echo -e "${CLR_WHITE}${CLR_BOLD}2.${CLR_RESET} Manage tunnel and slots"
  echo -e "${CLR_WHITE}${CLR_BOLD}3.${CLR_RESET} Enable auto health-check (cron)"
  echo -e "${CLR_WHITE}${CLR_BOLD}4.${CLR_RESET} Disable auto health-check (cron)"
  echo -e "${CLR_WHITE}${CLR_BOLD}5.${CLR_RESET} Install script (system-wide)"
  echo -e "${CLR_WHITE}${CLR_BOLD}6.${CLR_RESET} Update script (self-update)"
  echo -e "${CLR_WHITE}${CLR_BOLD}7.${CLR_RESET} Uninstall script"
  echo -e "${CLR_WHITE}${CLR_BOLD}8.${CLR_RESET} Optimize server (BBR + sysctl)"
  echo -e "${CLR_WHITE}${CLR_BOLD}9.${CLR_RESET} Test Tunnel (smart pre-check)"
  echo -e "${CLR_WHITE}${CLR_BOLD}0.${CLR_RESET} Exit"
  echo -e "${CLR_DIM}------------------------------------------------------------${CLR_RESET}"

  read -r -p "Select: " c < /dev/tty
  case "$c" in
    1) role="$(pick_role)"; prof="$(pick_slot "$role")"; edit_profile "$prof"; pause ;;
    2) role="$(pick_role)"; prof="$(pick_slot "$role")"; manage_slot_menu "$prof" ;;
    3) enable_cron_healthcheck; pause ;;
    4) disable_cron_healthcheck; pause ;;
    5) install_script; pause ;;
    6) update_script; pause ;;
    7) uninstall_script; pause ;;
    8) optimize_server; pause ;;
    9) test_tunnel; pause ;;
    0) exit 0 ;;
    *) echo "Invalid."; sleep 1 ;;
  esac
done
