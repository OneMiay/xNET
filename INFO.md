# 3proxy on Debian 12

This guide installs and configures `3proxy` with:

- HTTP proxy on port `8881`
- SOCKS5 proxy on port `8882`
- username: `user`
- password: `password`

## 1. Install required packages

```bash
apt update
apt install -y git build-essential
```

## 2. Download source code

```bash
cd /root
git clone https://github.com/3proxy/3proxy.git
cd /root/3proxy
```

## 3. Build 3proxy

```bash
make -f Makefile.Linux
```

After build, the binary will be here:

```text
/root/3proxy/bin/3proxy
```

## 4. Create directories

```bash
mkdir -p /usr/local/3proxy/bin
mkdir -p /usr/local/3proxy/logs
mkdir -p /usr/local/3proxy/stat
```

## 5. Copy binary

```bash
cp /root/3proxy/bin/3proxy /usr/local/3proxy/bin/3proxy
chmod +x /usr/local/3proxy/bin/3proxy
```

## 6. Create config file

Create file:

```text
/usr/local/3proxy/3proxy.cfg
```

Put this config inside:

```cfg
daemon
pidfile /var/run/3proxy.pid

nserver 8.8.8.8
nserver 1.1.1.1

timeouts 1 5 30 60 180 1800 15 60

log /usr/local/3proxy/logs/3proxy.log D
rotate 30

users user:CL:password
auth strong

allow user
proxy -p8881

allow user
socks -p8882

flush
```

## 7. Start 3proxy manually

```bash
/usr/local/3proxy/bin/3proxy /usr/local/3proxy/3proxy.cfg
```

## 8. Check that ports are listening

```bash
ss -ltnp | grep 888
```

## 9. Enable autostart with systemd

Create file:

```text
/etc/systemd/system/3proxy.service
```

Put this content inside:

```ini
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/3proxy/bin/3proxy /usr/local/3proxy/3proxy.cfg
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/3proxy.pid
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Then run:

```bash
systemctl daemon-reload
systemctl enable 3proxy
systemctl start 3proxy
systemctl status 3proxy
```

## 10. Open firewall ports if needed

If `UFW` is enabled:

```bash
ufw allow 8881/tcp
ufw allow 8882/tcp
```

## 11. Test from Windows with curl

HTTP:

```powershell
curl.exe -x "http://user:password@SERVER_IP:8881" https://ipecho.net/plain
```

SOCKS5:

```powershell
curl.exe -x "socks5://user:password@SERVER_IP:8882" https://ipecho.net/plain
```

Replace `SERVER_IP` with your server public IP.

## 12. Useful checks

View service logs:

```bash
journalctl -u 3proxy -n 50 --no-pager
```

View proxy log:

```bash
tail -f /usr/local/3proxy/logs/3proxy.log
```
