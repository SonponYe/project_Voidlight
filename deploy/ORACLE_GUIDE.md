# Putting Akira on a real server (Oracle Cloud, free)

By the end of this, anyone can open the game, type your server's address, and
play — without you having to host from your own PC.

**What you'll end up with:** a small always-on computer in Oracle's data centre
running the Akira server as a service. It starts by itself at boot and restarts
if it crashes.

**Honest warnings first**
- Nothing here has been run on a real Linux machine yet — the server has only run
  on Windows, headless, with real clients. Expect to hit at least one snag; the
  *If something goes wrong* section at the bottom covers the likely ones, and
  you can paste any error to me.
- Oracle can **reclaim Always Free machines that sit idle** (their docs: busy
  less than a set share of CPU over 7 days — [see Oracle's current rule](https://docs.oracle.com/iaas/Content/FreeTier/resourceref.htm)).
  A game server that's mostly empty looks idle. You'd get an email first and can
  restart a stopped machine, but check it now and then. Some people upgrade the
  account to "Pay As You Go" (still free within the free limits) to avoid this —
  read Oracle's current terms before deciding.
- Oracle asks for a **credit/debit card** to sign up. It's for identity; free
  resources aren't charged. Pick the **Always Free** shapes only (below).

**Do it in this order, and don't skip a stage:** 1 → get it running on plain
`ws://` and test it with a friend → *then*, only if you want browser play, do
stage 2 (a domain and `wss://`).

---

## Stage 0 — Build the server file (on your Windows PC)

1. Make sure the export templates are installed (you already did this for the
   Windows build) and that **`export_presets.cfg` is in the project folder**.
2. Double-click **`export_server.bat`** in the project folder. Its Godot is 4.7.2,
   so it needs 4.7.2 templates. If it complains, open the project in your
   editor instead: *Project → Export → "Linux Server (arm64)" → Export Project*
   (untick "Export With Debug"). Save it to `builds/server/akira_server.arm64`.
3. You should now have `builds/server/akira_server.arm64` (and `.x86_64`). Which
   one you need depends on the machine you pick in Stage 1 — **ARM → arm64**.

## Stage 1 — A free machine on Oracle Cloud

### 1.1 Sign up
Go to <https://www.oracle.com/cloud/free/> → *Start for free*. Choose your
**home region** carefully — it can't be changed later, and the free machines
only exist there. Pick one close to your players.

### 1.2 Create the machine
Console → *Compute → Instances → Create instance*.

| Setting | Choose |
|---|---|
| Image | **Ubuntu 24.04** (or 22.04) |
| Shape | *Change shape → Ampere → **VM.Standard.A1.Flex***, **1 OCPU, 6 GB** is plenty (a match is tiny; the Always Free allowance is up to 4 OCPU / 24 GB in total) |
| Networking | leave the defaults, **make sure "Assign a public IPv4 address" is on** |
| SSH keys | *Generate a key pair* and **download both files** — you can't get the private key again. Put them somewhere safe, e.g. `C:\Users\<you>\.ssh\` |

If it says **"Out of host capacity"**, the free ARM machines are temporarily full
in your region. Try again later (it can take hours or days), or use the free
**VM.Standard.E2.1.Micro** (AMD, small) — then use the **x86_64** build instead.
A game server this small runs fine on it.

When it's *Running*, copy its **Public IP address**. We'll call it `SERVER_IP`.

### 1.3 Open the port in Oracle's network (the cloud firewall)
Console → *Networking → Virtual cloud networks →* your network → *Subnets →*
your subnet → *Security Lists → Default Security List → Add Ingress Rules*:

| Source CIDR | IP Protocol | Destination port |
|---|---|---|
| `0.0.0.0/0` | TCP | `9050` |

(There are two firewalls: this one in Oracle's console and one on the machine
itself. The setup script handles the second.)

### 1.4 Copy the files to the machine
In PowerShell on your PC, from the project folder (use *your* key path and IP;
the default login name on Ubuntu images is `ubuntu`):

```powershell
$KEY = "C:\Users\<you>\.ssh\ssh-key-2026-xx-xx.key"
scp -i $KEY builds\server\akira_server.arm64 deploy\setup_server.sh deploy\akira-server.service ubuntu@SERVER_IP:~
```

The first time, it asks *"Are you sure you want to continue connecting?"* — type
`yes`. If it complains the key is "too open" (Windows file permissions): right
click the key → Properties → Security → Advanced → disable inheritance, and keep
only yourself with read access.

### 1.5 Run the setup script on the machine
```powershell
ssh -i $KEY ubuntu@SERVER_IP
```
Then, on the server:
```bash
bash setup_server.sh
```
It creates an unprivileged `akira` user, installs the server and a service that
restarts it, and opens the machine's firewall for port 9050. At the end it shows
the service status. You want to see **`active (running)`** and a line like
`[server] dedicated server listening on port 9050 (max 5 players, plain ws://)`.

Watch it live any time with `journalctl -u akira-server -f` (Ctrl+C to stop).

### 1.6 Play on it
In the game: **Online → Join a game → type `SERVER_IP`** (the port 9050 is
assumed) → Connect. You'll land in a lobby with no "host" — the **first person
in** is the room leader and gets *Start*. Have a friend do the same from their
own house. Play a round, then a second round from the same room.

If it works: **Stage 1 is done.** Tell your friends the address.

---

## Stage 2 — Browser play, or encryption (`wss://`) — only if you need it

Browsers refuse to talk to plain `ws://` from a secure (`https://`) page, which
is what itch.io and most hosts use. So **browser play needs a domain name and a
certificate.** Desktop players don't need any of this.

### 2.1 A domain name
Any domain works. The cheapest zero-cost way is a free subdomain from
<https://www.duckdns.org> (e.g. `akira-play.duckdns.org`) pointing at
`SERVER_IP`. Wait a few minutes after creating it, then check from your PC:
`nslookup akira-play.duckdns.org` should show your `SERVER_IP`.

### 2.2 Open ports 80 and 443
Do **1.3 again** for TCP **443** and TCP **80** (80 is only used while getting
the certificate). Then on the server open them on the machine too:
```bash
bash setup_server.sh 9050 443 80
```
(Re-running is safe; it only adds missing rules.)

### 2.3 Get a free certificate (Let's Encrypt)
On the server (replace the domain):
```bash
sudo apt update && sudo apt install -y certbot
sudo certbot certonly --standalone -d akira-play.duckdns.org
```
Give it an email when asked and accept the terms. It saves the certificate in
`/etc/letsencrypt/live/akira-play.duckdns.org/`.

### 2.4 Hand the certificate to the server, and renew automatically
The Akira server runs as a normal user and can't read Let's Encrypt's folder, so
a small hook copies the certificate where it can, and restarts the server
whenever it's renewed. From your PC, copy `deploy\renew-hook.sh` up
(`scp -i $KEY deploy\renew-hook.sh ubuntu@SERVER_IP:~`), then on the server:
```bash
sudo install -m 755 renew-hook.sh /etc/letsencrypt/renewal-hooks/deploy/akira.sh
sudo RENEWED_LINEAGE=/etc/letsencrypt/live/akira-play.duckdns.org /etc/letsencrypt/renewal-hooks/deploy/akira.sh
```
Certbot renews by itself (a timer) about every two months and runs the hook.
Check renewal works any time with `sudo certbot renew --dry-run`.

### 2.5 Tell the server to use TLS
```bash
echo 'AKIRA_ARGS="--port=443 --tls-cert=/etc/akira/certs/fullchain.pem --tls-key=/etc/akira/certs/privkey.pem"' | sudo tee /etc/akira/server.env
sudo systemctl restart akira-server
journalctl -u akira-server -n 5 --no-pager
```
You want `... listening on port 443 (max 5 players, wss:// TLS)`. If it says the
TLS files couldn't be read, check `ls -l /etc/akira/certs`.

Players now join by typing **`wss://akira-play.duckdns.org`** (or
`akira-play.duckdns.org:443` — port 443 implies TLS). Plain `SERVER_IP` no
longer works against this server: it speaks only `wss://` now.

### 2.6 The browser build
Export the **Web** preset (`export_web.bat`) and upload the folder to itch.io as
an HTML5 game (or any `https://` host). A browser page always connects with
`wss://`, so players type the domain. The browser will ask permission for the
**microphone** the first time voice is used. **None of the browser side has been
tried yet** — test it with one friend before announcing it.

---

## Day-to-day

| I want to… | On the server |
|---|---|
| See who's connected / what's happening | `journalctl -u akira-server -f` |
| Restart it | `sudo systemctl restart akira-server` |
| Stop / start it | `sudo systemctl stop akira-server` / `start` |
| Check it's alive after a reboot | `systemctl status akira-server` |
| Change the port or options | edit `/etc/akira/server.env`, then restart |

**Putting a new version of the game on the server** (do this every time you
change the game, and have everyone update their copy too — old and new versions
can't play together):
1. Re-export the server build (Stage 0).
2. `scp -i $KEY builds\server\akira_server.arm64 ubuntu@SERVER_IP:~`
3. On the server:
   ```bash
   sudo systemctl stop akira-server
   sudo install -m 755 ~/akira_server.arm64 /opt/akira/akira_server
   sudo systemctl start akira-server
   ```
   (Use `.x86_64` if your machine is AMD.) Restarting ends any match in
   progress, so pick a quiet moment.

---

## If something goes wrong

| Symptom | Most likely cause |
|---|---|
| The game says it can't connect / times out | Both firewalls: the Oracle console rule (1.3) **and** the machine's (`bash setup_server.sh` again). Test the port from your PC: `Test-NetConnection SERVER_IP -Port 9050` should say `TcpTestSucceeded : True`. |
| `connection refused` (instantly) | The service isn't running: `systemctl status akira-server`, then `journalctl -u akira-server -n 30`. |
| `Exec format error` in the log | Wrong CPU build: ARM machine needs `.arm64`, AMD needs `.x86_64`. |
| `Permission denied` on `scp` | Wrong key, wrong login name (try `ubuntu`, or `opc` on Oracle Linux), or the key's Windows permissions (see 1.4). |
| Service restarts every few seconds | `journalctl -u akira-server -n 50` — send me those lines. |
| TLS: "certificate" errors in the game | The domain you typed must match the certificate exactly; check `sudo certbot certificates`. |
| Works for you, not your friend | They need the same game version, and (for a domain) DNS can take a while to spread. |
| The machine vanished or stopped | Oracle's idle reclaim (see the warning at the top) — check your email and the Instances page, and start it again. |

**Keep the private key and your Oracle login safe**; anyone with the key can
control the server.
