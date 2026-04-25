# traffic-counters.sh

Скрипт `traffic-counters.sh` создает таблицу и счетчики в `nftables` для учета трафика:

- по TCP-портам `8881` и `8882`
- по WireGuard-порту `51820`
- по OpenVPN-порту `64249`
- по отдельным клиентам WireGuard
- по подсетям или адресам OpenVPN

## Что понадобится

- Linux-сервер с установленным `nftables`
- права `root`
- Bash
- желательно `numfmt` для красивого вывода размеров

Проверить наличие `nft` можно так:

```bash
nft --version
```

Если `nftables` не установлен:

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install nftables
```

### CentOS / Rocky / AlmaLinux

```bash
sudo dnf install nftables
```

### Arch Linux

```bash
sudo pacman -S nftables
```

При необходимости включите сервис:

```bash
sudo systemctl enable --now nftables
```

## Установка скрипта

1. Скопируйте файл [traffic-counters.sh](D:/Work/xNET/traffic-counters.sh) на Linux-сервер.
2. Сделайте его исполняемым:

```bash
chmod +x traffic-counters.sh
```

3. При необходимости откройте файл и измените параметры в начале:

```bash
TABLE_FAMILY="inet"
TABLE_NAME="trafficmon"

WG_CLIENTS=("10.7.0.2")
OVPN_CLIENTS=("10.8.0.0/24")
```

### Что можно менять

- `TABLE_FAMILY` и `TABLE_NAME` задают имя таблицы `nftables`
- `WG_CLIENTS` содержит IP-адреса клиентов WireGuard
- `OVPN_CLIENTS` содержит IP-адреса или подсети клиентов OpenVPN

Пример для нескольких клиентов:

```bash
WG_CLIENTS=("10.7.0.2" "10.7.0.3" "10.7.0.4")
OVPN_CLIENTS=("10.8.0.10" "10.8.0.11" "10.8.0.0/24")
```

## Как работает скрипт

Скрипт создает таблицу `inet trafficmon` и три цепочки:

- `input`
- `output`
- `forward`

В эти цепочки добавляются правила со счетчиками:

- входящий трафик на нужные порты
- исходящий трафик с нужных портов
- трафик в `forward` по адресам клиентов

Счетчики накапливают число байт, после чего скрипт может показать статистику.

## Команды использования

### Установить правила и счетчики

```bash
sudo ./traffic-counters.sh install
```

Что делает команда:

- удаляет старую таблицу `trafficmon`, если она уже есть
- создает новую таблицу
- создает все счетчики
- добавляет правила учета

Важно: команда `install` пересоздает таблицу полностью. Если счетчики уже накопили статистику, она будет потеряна.

### Показать статистику

```bash
sudo ./traffic-counters.sh show
```

Будет выведена статистика по:

- портам
- WireGuard
- OpenVPN
- клиентам WireGuard
- клиентам OpenVPN
- итоговым `TOTAL RX` и `TOTAL TX`

Если таблица еще не установлена, скрипт покажет:

```text
Not installed
```

### Сбросить счетчики

```bash
sudo ./traffic-counters.sh reset
```

Что делает команда:

- обнуляет все счетчики
- правила остаются на месте
- таблица остается на месте

Используйте это, если хотите начать новый период учета, не переустанавливая правила.

### Удалить правила и таблицу

```bash
sudo ./traffic-counters.sh remove
```

Что делает команда:

- удаляет таблицу `trafficmon`
- удаляет все счетчики
- удаляет все правила, созданные скриптом

## Пример рабочего цикла

```bash
sudo ./traffic-counters.sh install
sudo ./traffic-counters.sh show
sudo ./traffic-counters.sh reset
sudo ./traffic-counters.sh show
sudo ./traffic-counters.sh remove
```

## Пример запуска по расписанию

Если нужно периодически смотреть статистику:

```bash
watch -n 5 'sudo ./traffic-counters.sh show'
```

Это будет обновлять вывод каждые 5 секунд.

## Автозапуск после перезагрузки

Если правила должны восстанавливаться после перезагрузки, можно добавить запуск в `systemd`.

Пример юнита `/etc/systemd/system/traffic-counters.service`:

```ini
[Unit]
Description=Traffic Counters for nftables
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/root/traffic-counters.sh install
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Дальше:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now traffic-counters.service
```

Перед этим убедитесь, что путь в `ExecStart` указан правильно.

## Как читать статистику

- `*_rx` означает входящий трафик
- `*_tx` означает исходящий трафик
- `p8881_rx` означает байты, пришедшие на TCP-порт `8881`
- `p8881_tx` означает байты, отправленные с TCP-порта `8881`
- `wg_rx` и `wg_tx` показывают трафик WireGuard по UDP-порту `51820`
- `ovpn_rx` и `ovpn_tx` показывают трафик OpenVPN по UDP-порту `64249`
- `wg_<ip>_rx` и `wg_<ip>_tx` показывают трафик конкретного клиента WireGuard
- `ovpn_<ip>_rx` и `ovpn_<ip>_tx` показывают трафик адреса или подсети OpenVPN

## Важные замечания

- Скрипт считает трафик в байтах, а при наличии `numfmt` выводит его в удобном виде
- Для работы нужны права администратора, иначе команды `nft` завершатся ошибкой
- В именах счетчиков используются IP-адреса и подсети как часть имени

Последний пункт важен: символ `/` в имени счетчика для `OVPN_CLIENTS=("10.8.0.0/24")` может не поддерживаться в имени объекта `nftables` на некоторых системах. Если увидите ошибку при `install`, лучше заменить подсети на безопасные текстовые имена в логике скрипта или учитывать клиентов по отдельным IP

## Проверка вручную

Посмотреть созданные объекты можно командами:

```bash
sudo nft list table inet trafficmon
sudo nft list counters table inet trafficmon
```

## Если что-то не работает

Проверьте по порядку:

1. Есть ли `nftables` в системе
2. Запускается ли скрипт от `root`
3. Совпадают ли порты WireGuard и OpenVPN с реальными настройками сервера
4. Верно ли указаны IP-адреса клиентов
5. Не конфликтуют ли ваши текущие правила `nftables` с новыми цепочками

## Кратко

- `install` — создать таблицу, правила и счетчики
- `show` — показать накопленную статистику
- `reset` — обнулить счетчики
- `remove` — удалить все, что создал скрипт
