```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Per-IP Traffic Shaper
# GitHub Installer
# ============================================================

INSTALL_DIR="/opt/shaper"
SCRIPT_PATH="${INSTALL_DIR}/shaper.py"
SERVICE_PATH="/etc/systemd/system/shaper.service"
LOG_FILE="/var/log/shaper.log"

if [[ "${EUID}" -ne 0 ]]; then
    echo "❌ Запусти установщик от root."
    echo "   sudo bash install.sh"
    exit 1
fi

echo
echo "============================================================"
echo "        🚦 Per-IP Traffic Shaper — Installer"
echo "============================================================"
echo

echo "[1/5] Проверка зависимостей..."

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y conntrack iproute2 python3

echo "✓ Зависимости установлены"
echo

echo "[2/5] Создание директории..."

mkdir -p "${INSTALL_DIR}"

echo "✓ ${INSTALL_DIR}"
echo

echo "[3/5] Установка shaper.py..."

cat > "${SCRIPT_PATH}" << 'PYEOF'
#!/usr/bin/env python3
"""
🚦 Per-IP Traffic Shaper Agent

Читает TCP-трафик по IP через conntrack
и ограничивает скорость нарушителей через tc/HTB.
"""

import re
import time
import logging
import ipaddress
import subprocess
from datetime import datetime, timedelta
from collections import defaultdict


# ============================================================
# CONFIGURATION
# ============================================================

LIMIT_GB_PER_HOUR  = 20
SHAPE_MBIT         = 5
SHAPE_DURATION_MIN = 120
CHECK_INTERVAL_SEC = 60

MONITOR_PORTS = {
    8880,
    443,
    8443,
    8445,
    8080,
}

WHITELIST_IPS = {
    "127.0.0.1",
    "::1",
    "146.59.34.209",
}

WHITELIST_SUBNETS = [
    ipaddress.ip_network("188.72.110.0/24"),
    ipaddress.ip_network("188.72.111.0/24"),
    ipaddress.ip_network("91.231.236.0/24"),
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
]


# ============================================================
# WHITELIST
# ============================================================

def is_whitelisted(ip: str) -> bool:
    if ip in WHITELIST_IPS:
        return True

    try:
        addr = ipaddress.ip_address(ip)
        return any(addr in subnet for subnet in WHITELIST_SUBNETS)
    except ValueError:
        return False


# ============================================================
# LOGGING
# ============================================================

logging.basicConfig(
    format="%(asctime)s | %(levelname)s | %(message)s",
    level=logging.INFO,
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("/var/log/shaper.log"),
    ],
)

logger = logging.getLogger(__name__)


# ============================================================
# NETWORK INTERFACE
# ============================================================

def get_default_interface() -> str:
    try:
        result = subprocess.run(
            ["ip", "route", "show", "default"],
            capture_output=True,
            text=True,
            timeout=5,
        )

        match = re.search(r"dev\s+(\S+)", result.stdout)

        if match:
            return match.group(1)

    except Exception:
        pass

    return "ens3"


IFACE = get_default_interface()

logger.info(f"Интерфейс: {IFACE}")


# ============================================================
# CONNTRACK
# ============================================================

def get_traffic_by_ip() -> dict:
    traffic = defaultdict(int)

    try:
        result = subprocess.run(
            ["conntrack", "-L", "-p", "tcp"],
            capture_output=True,
            text=True,
            timeout=10,
        )

        for line in result.stdout.splitlines():

            src_match = re.search(r"\bsrc=(\S+)", line)
            dport_match = re.search(r"\bdport=(\d+)", line)
            bytes_match = re.search(r"\bbytes=(\d+)", line)

            if not (src_match and dport_match and bytes_match):
                continue

            src_ip = src_match.group(1)
            dport = int(dport_match.group(1))
            nbytes = int(bytes_match.group(1))

            if dport in MONITOR_PORTS and not is_whitelisted(src_ip):
                traffic[src_ip] += nbytes

    except FileNotFoundError:
        logger.error(
            "conntrack не найден! "
            "Установи: apt install conntrack"
        )

    except Exception as e:
        logger.warning(
            f"get_traffic_by_ip error: {e}"
        )

    return dict(traffic)


# ============================================================
# TC / HTB
# ============================================================

def setup_tc_root():
    result = subprocess.run(
        ["tc", "qdisc", "show", "dev", IFACE],
        capture_output=True,
        text=True,
    )

    if "htb" not in result.stdout:

        subprocess.run(
            [
                "tc",
                "qdisc",
                "add",
                "dev",
                IFACE,
                "root",
                "handle",
                "1:",
                "htb",
                "default",
                "999",
            ],
            capture_output=True,
        )

        subprocess.run(
            [
                "tc",
                "class",
                "add",
                "dev",
                IFACE,
                "parent",
                "1:",
                "classid",
                "1:999",
                "htb",
                "rate",
                "10000mbit",
            ],
            capture_output=True,
        )

        logger.info(
            "tc HTB qdisc инициализирован"
        )


def ip_to_class_id(ip: str) -> str:
    parts = ip.split(".")

    if len(parts) == 4:
        return f"1:{int(parts[2]) * 256 + int(parts[3])}"

    return "1:100"


def shape_ip(ip: str, mbit: int) -> bool:
    setup_tc_root()

    classid = ip_to_class_id(ip)

    try:

        subprocess.run(
            [
                "tc",
                "class",
                "add",
                "dev",
                IFACE,
                "parent",
                "1:",
                "classid",
                classid,
                "htb",
                "rate",
                f"{mbit}mbit",
                "ceil",
                f"{mbit}mbit",
            ],
            capture_output=True,
        )

        subprocess.run(
            [
                "tc",
                "filter",
                "add",
                "dev",
                IFACE,
                "parent",
                "1:",
                "protocol",
                "ip",
                "u32",
                "match",
                "ip",
                "dst",
                f"{ip}/32",
                "flowid",
                classid,
            ],
            capture_output=True,
        )

        logger.info(
            f"⚡ Шейпинг: {ip} → {mbit} Mbit/s "
            f"(classid {classid})"
        )

        return True

    except Exception as e:

        logger.error(
            f"shape_ip error ({ip}): {e}"
        )

        return False


def unshape_ip(ip: str) -> bool:
    classid = ip_to_class_id(ip)

    try:

        subprocess.run(
            [
                "tc",
                "filter",
                "del",
                "dev",
                IFACE,
                "parent",
                "1:",
                "protocol",
                "ip",
                "u32",
                "match",
                "ip",
                "dst",
                f"{ip}/32",
                "flowid",
                classid,
            ],
            capture_output=True,
        )

        subprocess.run(
            [
                "tc",
                "class",
                "del",
                "dev",
                IFACE,
                "classid",
                classid,
            ],
            capture_output=True,
        )

        logger.info(
            f"🟢 Шейпинг снят: {ip}"
        )

        return True

    except Exception as e:

        logger.error(
            f"unshape_ip error ({ip}): {e}"
        )

        return False


# ============================================================
# STATE
# ============================================================

shaped = {}
prev_snapshot = {}


# ============================================================
# TRAFFIC CHECK
# ============================================================

def check_and_shape():

    now = datetime.now()

    traffic = get_traffic_by_ip()

    # Remove expired shaping rules
    expired = [
        ip
        for ip, data in shaped.items()
        if data["until"] < now
    ]

    for ip in expired:

        shaped.pop(ip)

        unshape_ip(ip)

    # Process traffic
    for ip, total_bytes in traffic.items():

        if ip in shaped:
            continue

        prev = prev_snapshot.get(ip)

        if prev is None:

            prev_snapshot[ip] = {
                "bytes": total_bytes,
                "time": now,
            }

            continue

        delta_bytes = max(
            0,
            total_bytes - prev["bytes"],
        )

        delta_seconds = (
            now - prev["time"]
        ).total_seconds()

        if delta_seconds < 1:
            continue

        hourly_gb = (
            (delta_bytes / delta_seconds)
            * 3600
            / (1024 ** 3)
        )

        if hourly_gb > LIMIT_GB_PER_HOUR:

            logger.warning(
                f"🔴 АНОМАЛИЯ: {ip} — "
                f"{hourly_gb:.1f} ГБ/час"
            )

            ok = shape_ip(
                ip,
                SHAPE_MBIT,
            )

            if ok:

                shaped[ip] = {
                    "until": (
                        now
                        + timedelta(
                            minutes=SHAPE_DURATION_MIN
                        )
                    ),
                    "hourly_gb": hourly_gb,
                }

        prev_snapshot[ip] = {
            "bytes": total_bytes,
            "time": now,
        }

    if shaped:

        ips = ", ".join(
            f"{ip} до "
            f"{data['until'].strftime('%H:%M')}"
            for ip, data in shaped.items()
        )

        logger.info(
            f"Активных шейпингов: "
            f"{len(shaped)} → {ips}"
        )


# ============================================================
# MAIN
# ============================================================

def main():

    logger.info(
        f"🚦 Traffic Shaper запущен\n"
        f"   Интерфейс:  {IFACE}\n"
        f"   Порты:      {sorted(MONITOR_PORTS)}\n"
        f"   Порог:      {LIMIT_GB_PER_HOUR} ГБ/час\n"
        f"   Шейпинг:    {SHAPE_MBIT} Mbit/s "
        f"на {SHAPE_DURATION_MIN} мин\n"
        f"   Интервал:   {CHECK_INTERVAL_SEC} сек"
    )

    setup_tc_root()

    while True:

        try:
            check_and_shape()

        except Exception as e:

            logger.error(
                f"Ошибка: {e}",
                exc_info=True,
            )

        time.sleep(
            CHECK_INTERVAL_SEC
        )


if __name__ == "__main__":
    main()
PYEOF

chmod +x "${SCRIPT_PATH}"

echo "✓ ${SCRIPT_PATH}"
echo

echo "[4/5] Создание systemd сервиса..."

cat > "${SERVICE_PATH}" << 'EOF'
[Unit]
Description=Per-IP Traffic Shaper
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/shaper
ExecStart=/usr/bin/python3 /opt/shaper/shaper.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "✓ ${SERVICE_PATH}"
echo

echo "[5/5] Запуск сервиса..."

systemctl daemon-reload
systemctl enable shaper.service
systemctl restart shaper.service

sleep 2

if systemctl is-active --quiet shaper.service; then
    echo
    echo "============================================================"
    echo "              ✅ Установка завершена"
    echo "============================================================"
    echo
    echo "Сервис:     shaper.service"
    echo "Скрипт:     ${SCRIPT_PATH}"
    echo "Лог:        ${LOG_FILE}"
    echo
    echo "Статус:"
    systemctl --no-pager --full status shaper.service
    echo
    echo "Для просмотра логов:"
    echo "  journalctl -u shaper -f"
    echo
    echo "Для проверки tc:"
    echo "  tc qdisc show dev \$(ip route | grep default | awk '{print \$5}')"
    echo
else
    echo
    echo "❌ Сервис не запустился."
    echo
    echo "Проверь:"
    echo "  systemctl status shaper --no-pager"
    echo "  journalctl -u shaper -n 50 --no-pager"
    exit 1
fi
```
