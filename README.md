# 🚦 Per-IP Traffic Shaper

Linux-агент для автоматического контроля TCP-трафика по IP-адресам и временного ограничения скорости IP при обнаружении аномально высокого потребления трафика.

Агент использует:

* **conntrack** — получение статистики TCP-соединений;
* **tc / HTB** — ограничение скорости;
* **systemd** — постоянный запуск и автоматический рестарт;
* **Python 3** — логика мониторинга.

---

## ⚡ Быстрая установка

Установка на сервер выполняется одной командой:

```bash
curl -fsSL https://raw.githubusercontent.com/vozduh443/Traffic-Shaper/main/install.sh | bash
```

Если команда выполняется не от `root`:

```bash
curl -fsSL https://raw.githubusercontent.com/vozduh443/Traffic-Shaper/main/install.sh | sudo bash
```

Альтернативный вариант через `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/vozduh443/Traffic-Shaper/main/install.sh | sudo bash
```

Установщик автоматически установит зависимости, создаст конфигурацию, systemd-сервис и запустит шейпер.

---

## 📦 Установка через Git

Если нужно сначала скачать репозиторий:

```bash
git clone https://github.com/vozduh443/Traffic-Shaper.git
cd Traffic-Shaper
chmod +x install.sh
sudo ./install.sh
```

Репозиторий:

https://github.com/vozduh443/Traffic-Shaper

---

## 🔧 Что делает установщик

`install.sh` автоматически:

1. Проверяет наличие root-доступа.
2. Обновляет список пакетов.
3. Устанавливает необходимые зависимости:

   * `conntrack`
   * `iproute2`
   * `python3`
4. Создаёт директорию:

```text
/opt/shaper/
```

5. Устанавливает шейпер:

```text
/opt/shaper/shaper.py
```

6. Создаёт systemd-сервис:

```text
/etc/systemd/system/shaper.service
```

7. Включает автоматический запуск после перезагрузки:

```bash
systemctl enable shaper
```

8. Запускает сервис:

```bash
systemctl restart shaper
```

---

# ⚙️ Конфигурация

Основные параметры находятся в начале `shaper.py`:

```python
LIMIT_GB_PER_HOUR  = 20
SHAPE_MBIT         = 5
SHAPE_DURATION_MIN = 120
CHECK_INTERVAL_SEC = 60
```

---

## 📊 Порог трафика

```python
LIMIT_GB_PER_HOUR = 20
```

Порог:

```text
20 GB/hour
```

Если расчётная скорость потребления IP превышает установленный порог, IP считается аномальным и для него включается ограничение.

---

## 🚦 Ограничение скорости

```python
SHAPE_MBIT = 5
```

Для IP, превысившего установленный порог:

```text
5 Mbit/s
```

Ограничение реализуется через `tc` и HTB.

---

## ⏱ Продолжительность ограничения

```python
SHAPE_DURATION_MIN = 120
```

Ограничение устанавливается на:

```text
120 минут
```

После истечения времени агент автоматически удаляет соответствующий `tc` filter/class.

---

## 🔄 Интервал проверки

```python
CHECK_INTERVAL_SEC = 60
```

Проверка выполняется каждые:

```text
60 секунд
```

---

# 🌐 Мониторируемые порты

По умолчанию контролируются TCP-соединения на следующих портах:

```python
MONITOR_PORTS = {
    8880,
    443,
    8443,
    8445,
    8080,
}
```

Чтобы изменить список портов, отредактируйте:

```python
MONITOR_PORTS = {
    443,
    8443,
}
```

Например, только HTTPS:

```python
MONITOR_PORTS = {
    443,
}
```

После изменения конфигурации перезапустите сервис:

```bash
systemctl restart shaper
```

---

# 🟢 Whitelist

IP-адреса из whitelist не участвуют в проверке и не будут ограничиваться шейпером.

Текущий список:

```python
WHITELIST_IPS = {
    "127.0.0.1",
    "::1",
    "146.59.34.209",
}
```

---

## 🟢 Whitelist подсетей

Можно исключать целые подсети:

```python
WHITELIST_SUBNETS = [
    ipaddress.ip_network("188.72.110.0/24"),
    ipaddress.ip_network("188.72.111.0/24"),
    ipaddress.ip_network("91.231.236.0/24"),
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
]
```

Чтобы добавить свою подсеть:

```python
ipaddress.ip_network("203.0.113.0/24"),
```

Или отдельный IP:

```python
WHITELIST_IPS = {
    "127.0.0.1",
    "::1",
    "146.59.34.209",
    "203.0.113.10",
}
```

После изменения:

```bash
systemctl restart shaper
```

---

# 📁 Файлы после установки

Основной скрипт:

```text
/opt/shaper/shaper.py
```

Systemd unit:

```text
/etc/systemd/system/shaper.service
```

Лог приложения:

```text
/var/log/shaper.log
```

---

# 🔍 Проверка сервиса

Показать подробный статус:

```bash
systemctl status shaper --no-pager
```

Проверить, запущен ли сервис:

```bash
systemctl is-active shaper
```

Проверить автозапуск:

```bash
systemctl is-enabled shaper
```

Ожидаемый результат:

```text
active
```

и:

```text
enabled
```

---

# 📜 Логи

## Логи systemd в реальном времени

```bash
journalctl -u shaper -f
```

Остановить просмотр:

```text
Ctrl+C
```

---

## Последние 50 строк

```bash
journalctl -u shaper -n 50 --no-pager
```

---

## Все логи текущего запуска

```bash
journalctl -u shaper -b --no-pager
```

---

## Лог приложения

```bash
tail -f /var/log/shaper.log
```

Последние 50 строк:

```bash
tail -n 50 /var/log/shaper.log
```

---

# 🚦 Проверка tc

Определить основной сетевой интерфейс:

```bash
ip route | grep default
```

Например:

```text
default via 192.168.1.1 dev ens3
```

В данном случае интерфейс:

```text
ens3
```

---

## Проверить qdisc

Автоматически определить интерфейс:

```bash
tc qdisc show dev $(ip route | grep default | awk '{print $5}')
```

---

## Проверить классы HTB

```bash
tc class show dev $(ip route | grep default | awk '{print $5}')
```

---

## Проверить фильтры

```bash
tc filter show dev $(ip route | grep default | awk '{print $5}')
```

Если IP был ограничен, в выводе появится соответствующий `u32` filter и HTB class.

---

# 🌐 Проверка conntrack

Количество TCP-соединений:

```bash
conntrack -L -p tcp | wc -l
```

Посмотреть текущие TCP-соединения:

```bash
conntrack -L -p tcp
```

Проверить, что conntrack установлен:

```bash
which conntrack
```

Ожидаемый результат:

```text
/usr/sbin/conntrack
```

---

# 🔄 Управление сервисом

## Запустить

```bash
systemctl start shaper
```

## Остановить

```bash
systemctl stop shaper
```

## Перезапустить

```bash
systemctl restart shaper
```

## Включить автозапуск

```bash
systemctl enable shaper
```

## Отключить автозапуск

```bash
systemctl disable shaper
```

## Перезапустить после изменения конфигурации

```bash
systemctl restart shaper
```

---

# 🧪 Быстрая диагностика

Если шейпер не работает:

```bash
systemctl status shaper --no-pager
```

Затем:

```bash
journalctl -u shaper -n 50 --no-pager
```

Проверить наличие Python:

```bash
python3 --version
```

Проверить conntrack:

```bash
conntrack --version
```

Проверить tc:

```bash
tc -V
```

Проверить интерфейс:

```bash
ip route show default
```

Проверить qdisc:

```bash
tc qdisc show
```

---

# 🧠 Как работает

Упрощённая схема:

```text
                    ┌──────────────────┐
                    │      Client      │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │    conntrack     │
                    │  TCP statistics  │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  Traffic Shaper  │
                    │      Python      │
                    └────────┬─────────┘
                             │
                     > 20 GB/hour ?
                         /       \
                       NO         YES
                       │           │
                       ▼           ▼
                    Ignore    ┌──────────┐
                              │ tc / HTB │
                              └────┬─────┘
                                   │
                                   ▼
                              5 Mbit/s
                              120 minutes
```

Агент с заданным интервалом получает статистику TCP-соединений через `conntrack`.

Для каждого IP рассчитывается объём переданного трафика за измерительный интервал и пересчитывается в приблизительное значение GB/hour.

Если рассчитанное значение превышает:

```text
20 GB/hour
```

для IP создаётся ограничивающий HTB-класс:

```text
5 Mbit/s
```

Ограничение действует:

```text
120 минут
```

После истечения времени правило удаляется.

---

# 🔄 Автоматическое восстановление

Сервис работает через systemd с автоматическим рестартом.

При сбое процесса systemd перезапустит шейпер.

Проверить настройки:

```bash
systemctl cat shaper
```

---

# 🗑️ Удаление

Остановить и отключить сервис:

```bash
systemctl disable --now shaper
```

Удалить systemd unit:

```bash
rm -f /etc/systemd/system/shaper.service
systemctl daemon-reload
```

Удалить шейпер:

```bash
rm -rf /opt/shaper
```

Удалить лог:

```bash
rm -f /var/log/shaper.log
```

---

## Удаление conntrack

Если `conntrack` больше не используется другими сервисами:

```bash
apt remove -y conntrack
```

> Не удаляйте `conntrack`, если он используется другими компонентами сервера.

---

# ⚠️ Требования

Система должна иметь:

* Linux;
* systemd;
* Python 3;
* `iproute2`;
* `conntrack`;
* root-доступ;
* пакетный менеджер `apt`.

Установщик рассчитан прежде всего на:

* Debian;
* Ubuntu;
* другие Debian-based системы с `apt`.

---

# ⚠️ Важные замечания

Шейпер работает на уровне сетевого интерфейса через `tc`.

Поэтому перед использованием на production-сервере рекомендуется проверить:

```bash
ip route show default
```

и:

```bash
tc qdisc show
```

Также учитывайте, что установка собственного root `qdisc` может взаимодействовать с уже существующей конфигурацией `tc`.

Если на сервере уже используется сложная конфигурация `tc`, её следует проверить перед запуском.

---

# 📌 Текущая конфигурация по умолчанию

| Параметр          |                    Значение |
| ----------------- | --------------------------: |
| Порог             |                  20 GB/hour |
| Ограничение       |                    5 Mbit/s |
| Длительность      |                   120 минут |
| Интервал проверки |                   60 секунд |
| Порты             | 8880, 443, 8443, 8445, 8080 |
| Директория        |               `/opt/shaper` |
| Скрипт            |     `/opt/shaper/shaper.py` |
| Service           |            `shaper.service` |
| Лог               |       `/var/log/shaper.log` |

---

# 📂 Структура

```text
Traffic-Shaper/
├── install.sh
└── README.md
```

После установки на сервере:

```text
/opt/shaper/
└── shaper.py

/etc/systemd/system/
└── shaper.service

/var/log/
└── shaper.log
```

---

# 🚀 One-Line Install

Для быстрого развёртывания:

```bash
curl -fsSL https://raw.githubusercontent.com/vozduh443/Traffic-Shaper/main/install.sh | sudo bash
```

После установки проверить:

```bash
systemctl status shaper --no-pager
```

И посмотреть работу в реальном времени:

```bash
journalctl -u shaper -f
```

---

## 📄 License

MIT License
