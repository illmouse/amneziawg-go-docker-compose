# AmneziaWG Docker Compose VPN

Этот репозиторий содержит **Docker-набор для AmneziaWG** — VPN, похожий на WireGuard, используя контейнер [amneziavpn/amneziawg-go](https://hub.docker.com/r/amneziavpn/amneziawg-go/tags).

Конфигурации сервера и клиента создаются динамически, ключи управляются автоматически, что делает систему удобной и повторно используемой.

> [!NOTE]
> Данная конфигурация рассчитана на использование официального контейнера, поэтому все настройки его работы выполняются вне контейнера.

> [!IMPORTANT]
> Автоматическая конфигурация рассчитана на работу только с одним пиром ввиду специфики решаемой задачи.

---

## Особенности

- Автоматическая генерация серверных и клиентских ключей при первом запуске.
- Динамическая генерация конфигураций сервера и клиента на основе переменных окружения.
- Клиентская конфигурация (`./config/peer.conf`) готова к использованию.
- Логи выводятся в `docker logs` а так же в `./logs/amneziawg.log`.
- Повторное использование: после генерации ключей и конфигов контейнер просто запускает VPN без повторной генерации.

---

## Переменные окружения (`.env`)
 
```bash
# .env

# Опциональные параметры со значениями по-умолчанию
WG_IFACE=wg0                      # Name of the VPN interface inside the container
WG_ADDRESS=10.100.0.1/24          # Server IP and subnet
WG_CLIENT_ADDR=10.100.0.2/32      # Client IP
WG_PORT=13440                     # VPN port to accept connections
WG_ENDPOINT=                      # Публичный адрес хоста, на котором будут приниматься подключения. Определяется автоматически через ifconfig.me

# Автоматическе генерируемые переменные
Jc=3                           
Jmin=1
Jmax=50
S1=25
S2=72
H1=1411927821
H2=1212681123
H3=1327217326
H4=1515483925
````

**Примечания:**

* Параметры `Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `H1-H4` важны для работы VPN. Будут сгенерированы случайные при первом запуске скрипта setup.sh. Можно задать свои. Подробнее в [документации](https://docs.amnezia.org/documentation/amnezia-wg/#%D0%BF%D0%B0%D1%80%D0%B0%D0%BC%D0%B5%D1%82%D1%80%D1%8B-%D0%BA%D0%BE%D0%BD%D1%84%D0%B8%D0%B3%D1%83%D1%80%D0%B0%D1%86%D0%B8%D0%B8)

---

## Как это работает

1. **Первый запуск:**

   * Контейнер проверяет ключи и конфиги в `/etc/amneziawg`
   * Если чего-то нет, генерирует:

     * Серверные ключи (`privatekey`, `publickey`, `presharedkey`)
     * Клиентский ключ (`client_privatekey`)
     * Серверный конфиг (`wg0.conf`)
     * Клиентский конфиг (`peer.conf`)
   * Устанавливает права `600` для всех ключей.
   * Запускает VPN-интерфейс (`WG_IFACE`) и применяет NAT/iptables через него.

2. **Последующие запуски:**

   * Контейнер находит существующие ключи/конфиги и пропускает генерацию ключей.
   * Новая конфигурация генерируется с найденными ключами или генерируются новые.
   * Новая конфигурация сравнивается с существующей и заменяется если они различаются.
   * Запускает VPN и применяет NAT/iptables.

3. **Клиентская конфигурация:**

   * Доступна в `/etc/amneziawg/peer.conf`.
   * Можно скопировать на клиентское устройство для подключения.

---

## Пример Docker Compose

```yaml
services:
  amneziawg:
    image: amneziavpn/amneziawg-go:0.2.15
    container_name: amneziawg
    env_file:
      - .env
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - ${WG_PORT}:${WG_PORT}/udp
    volumes:
      - ./config:/etc/amneziawg
      - ./logs:/var/log/amneziawg
      - ./entrypoint.sh:/entrypoint.sh:ro
    entrypoint: ["/entrypoint.sh"]
    healthcheck:
      test: ["CMD", "sh", "-c", "ip link show wg0 && awg show wg0 2>/dev/null | grep -q listening"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    restart: always
    networks:
      awg:

networks:
   awg:
```

**Примечания:**

* `./config` используется для хранения ключей и конфигураций. Если директория пуста, контейнер автоматически создаст ключи и конфиги.
* `./logs` используется для хранения логов приложения.

---

## Использование

1. **Запустите скрипт конфигурации инсталляции:**

```bash
chmod +x setup.sh && ./setup.sh
```

Что делает скрипт:
- включает IP forwarding в /etc/sysctl.conf
- копирует скрипт мониторинга в /usr/local/bin/amneziawg-monitor.sh
- добавляет крон джобу для запуска скрипта в /etc/cron.d/amneziawg-monitor
- проверяет вывод скрипта мониторинга
- при отсутствии файла .env формирует файл автоматически генерируя переменные
- выводит конфигурацию для настройки клиента в консоль

2. **Получение клиентской конфигурации:**

В конце работы скрипта выводится конфигурация для настройки на стороне пира.

Файл с конфигурацией можно найти в `./config/peer.conf`

Пример вывода скрипта конфигурации:
```bash
[SETUP] Configuring IP forwarding in sysctl...
[SETUP] IP forwarding already enabled in sysctl.conf
[SETUP] Applying sysctl settings...
[SETUP] Sysctl settings applied successfully
[SETUP] IP forwarding is enabled (net.ipv4.ip_forward=1)
[SETUP] Creating .env file with generated obfuscation values
[SETUP] Generated obfuscation values:
[SETUP]   JC=3, JMIN=50, JMAX=1000
[SETUP]   S1=124, S2=52
[SETUP]   H1=7799, H2=16627, H3=7319, H4=10232
[WARNING] WG_ENDPOINT is not set or empty in .env file
[SETUP] Detecting public IP address...
[SETUP] Detected public IP: <external_ip>
[SETUP] WG_ENDPOINT has been set to: <external_ip>
[SETUP] Copying amneziawg-monitor.sh to /usr/local/bin/
[SETUP] Copying amneziawg-monitor to /etc/cron.d/
[SETUP] Making entrypoint.sh executable
[SETUP] Starting Docker Compose from current directory
[+] Running 1/1
 ✔ Container amneziawg  Started                                                                            11.4s 
[SETUP] Waiting for container to initialize...
[SETUP] Testing monitor script...
amneziawg
[SETUP] Monitor script executed successfully
[SETUP] Checking container status...
CONTAINER ID   IMAGE                            COMMAND            CREATED          STATUS                                     PORTS                                             NAMES
1a7a42d203ac   amneziavpn/amneziawg-go:0.2.15   "/entrypoint.sh"   34 seconds ago   Up Less than a second (health: starting)   0.0.0.0:13440->13440/udp, [::]:13440->13440/udp   amneziawg
[SETUP] Setup complete!
[SETUP] - IP forwarding configured in /etc/sysctl.conf
[SETUP] - Monitor script: /usr/local/bin/amneziawg-monitor.sh
[SETUP] - Cron job: /etc/cron.d/amneziawg-monitor
[SETUP] - Container logs: docker logs amneziawg
[SETUP] - .env file configured with WG_ENDPOINT and obfuscation values
[SETUP] Output peer configuration...
[Interface]
PrivateKey = <client_private_key>
Address = 10.100.0.2/32
DNS = 9.9.9.9,149.112.112.112
Jc = 3
Jmin = 1
Jmax = 50
S1 = 124
S2 = 52
H1 = 7799
H2 = 16627
H3 = 7319
H4 = 10232

[Peer]
PublicKey = <server_public_key>
PresharedKey = <preshared_key>
Endpoint = <external_ip>:13440
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

---

## Важные замечания

* Для полной регенерации VPN-конфигурации можно удалить содержимое `./config`. При следующем запуске контейнер создаст новые ключи и конфиги.
* Убедитесь, что UDP-порт (`WG_PORT`) открыт на роутере/фаерволе для подключения клиентов.