# 🚦 Per-IP Traffic Shaper

Простой Linux-агент для автоматического ограничения скорости отдельных IP-адресов при обнаружении аномально высокого TCP-трафика.

Агент использует:

* **conntrack** — получение статистики TCP-соединений;
* **tc / HTB** — ограничение скорости;
* **systemd** — постоянный запуск и автоматический рестарт;
* **Python 3** — логика мониторинга.

---

## ⚡ Быстрая установка

Установка выполняется одной командой:

```bash
curl -fsSL https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/install.sh | bash
```

Или:

```bash
wget -qO- https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/install.sh | bash
```

> Замените `USERNAME/REPOSITORY` на адрес вашего GitHub-репозитория.

Для запуска через `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/install.sh | sudo bash
```

---

## 📦 Установка из GitHub

Если репозиторий уже клонирован:

```bash
git clone https://github.com/USERNAME/REPOSITORY.git
cd REPOSITORY
chmod +x install.sh
sudo ./install.sh
```

---

## 🔧 Что делает установщик

`install.sh` автоматически:

1. Проверяет запуск от `root`.
2. Устанавливает необходимые пакеты:

   * `conntrack`
   * `iproute2`
   * `python3`
3. Создаёт:

```text
/opt/shaper/
```

4. Устанавливает:

```text
/opt/shaper/shaper.py
```

5. Создаёт systemd unit:

```text
/etc/systemd/system/shaper.service
```

6. Включает автоматический запуск:

```bash
systemctl enable shaper
```

7. Запускает сервис:

```bash
systemctl restart shaper
```

---

## ⚙️ Конфигурация

Основные параметры находятся в начале:

```python
LIMIT_GB_PER_HOUR  = 20
SHAPE_MBIT         = 5
SHAPE_DURATION_MIN = 120
CHECK_INTERVAL_SEC = 60
```

### Порог

```python
LIMIT_GB_PER_HOUR = 20
```

IP считается нарушителем, если рассчитанная скорость трафика превышает:

```text
20 GB/hour
```

### Ограничение

```python
SHAPE_MBIT = 5
```

Для обнаруженного IP устанавливается ограничение:

```text
5 Mbit/s
```

### Продолжительность

```python
SHAPE_DURATION_MIN = 120
```

Ограничение действует:

```text
120 минут
```

После истечения времени правило `tc` удаляется.

### Интервал проверки

```python
CHECK_INTERVAL_SEC = 60
```

Проверка выполняется каждые:

```text
60 секунд
```

---

## 🌐 Мониторируемые порты

По умолчанию отслеживаются:

```python
MONITOR_PORTS = {
    8880,
    443,
    8443,
    8445,
    8080,
}
```

Чтобы изменить список:

```python
MONITOR_PORTS = {
    443,
    8443,
}
```

---

## 🟢 Whitelist

Отдельные IP можно исключить из мониторинга:

```python
WHITELIST_IPS = {
    "127.0.0.1",
    "::1",
    "146.59.34.209",
}
```

Поддерживаются также целые подсети:

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

---

## 📁 Файлы

После установки:

```text
/opt/shaper/
└── shaper.py
```

Systemd:

```text
/etc/systemd/system/shaper.service
```

Лог приложения:

```text
/var/log/shaper.log
```

---

## 🔍 Проверка сервиса

Статус:

```bash
systemctl status shaper --no-pager
```

Проверка, запущен ли сервис:

```bash
systemctl is-active shaper
```

Проверка автозапуска:

```bash
systemctl is-enabled shaper
```

---

## 📜 Просмотр логов

В реальном времени:

```bash
journalctl -u shaper -f
```

Последние 50 строк:

```bash
journalctl -u shaper -n 50 --no-pager
```

Лог самого приложения:

```bash
tail -f /var/log/shaper.log
```

---

## 🚦 Проверка tc

Посмотреть root qdisc:

```bash
tc qdisc show dev $(ip route | grep default | awk '{print $5}')
```

Посмотреть классы:

```bash
tc class show dev $(ip route | grep default | awk '{print $5}')
```

Посмотреть фильтры:

```bash
tc filter show dev $(ip route | grep default | awk '{print $5}')
```

---

## 🌐 Проверка conntrack

Количество TCP-соединений:

```bash
conntrack -L -p tcp | wc -l
```

Посмотреть соединения:

```bash
conntrack -L -p tcp
```

---

## 🔄 Управление сервисом

Запустить:

```bash
systemctl start shaper
```

Остановить:

```bash
systemctl stop shaper
```

Перезапустить:

```bash
systemctl restart shaper
```

Отключить автозапуск:

```bash
systemctl disable shaper
```

Включить автозапуск:

```bash
systemctl enable shaper
```

---

## 🗑️ Удаление

Остановить и удалить systemd-сервис:

```bash
systemctl disable --now shaper
rm -f /etc/systemd/system/shaper.service
systemctl daemon-reload
```

Удалить файлы шейпера:

```bash
rm -rf /opt/shaper
```

Удалить лог:

```bash
rm -f /var/log/shaper.log
```

При необходимости удалить зависимости:

```bash
apt remove -y conntrack
```

---

## 🧠 Как работает

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
                    │     Python       │
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

Агент каждые 60 секунд получает статистику TCP-соединений через `conntrack`, группирует трафик по исходному IP и рассчитывает приблизительный объём трафика за час.

Если расчётный показатель превышает установленный порог, для IP создаётся `tc` HTB-класс и фильтр с ограничением скорости.

После окончания периода ограничения правило удаляется.

---

## ⚠️ Требования

Поддерживается Linux-система с:

* `systemd`
* `iproute2`
* `conntrack`
* `python3`
* root-доступом

Установка рассчитана на Debian/Ubuntu-подобные системы с `apt`.

---

## 📄 License

MIT License

```
```
