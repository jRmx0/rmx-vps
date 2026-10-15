# RMX-SERVER (rmx-vps) — access & hardening log

| | |
|---|---|
| Server | RMX-SERVER / VPS-1, `45.81.252.43`, hostname `vps3124` |
| OS | Ubuntu 24.04.5 LTS, kernel `6.8.0-147-generic` (after reboot) |
| Host key | ED25519 `SHA256:OHYSCh1xGk1SAUt6brhpWSneyloXz8wfp35j+VipXqI` |
| Admin user | `rmx` (sudo, no password; in group `docker`) |
| Admin PC | Windows 11, PowerShell, OpenSSH client |
| Setup date | 2026-10-14 (times in UTC) |
| Domain | `rmx.lt` (`@` A → this IP; `api`, `mqtt`, `www` CNAME → `rmx.lt.`) |
| Public ports | 22 (SSH), 80 + 443 (Caddy). See [§10](#10-docker--services) |

**This repo:** `README.md` (this file) describes the current state. [`CHANGELOG.md`](CHANGELOG.md) gets one dated entry per change. [`config/`](config/) holds copies of the server's config files, pulled with the commands in [§9](#9-updating-this-repo). [`services/`](services/) holds the Docker Compose stack, run from the server clone (see [§10](#10-docker--services)).

> No secrets in this repo: no passwords, private keys or tokens. `.gitignore` blocks common key files.

---

## 1. How to connect

From the Windows PC:

```powershell
ssh rmx-vps          # logs in as rmx with the key
sudo -i              # become root (no password)
```

Other ways in:

| Way in | Who | Requirements |
|---|---|---|
| `ssh rmx-vps` | `rmx` | Private key `~/.ssh/rmx-vps_ed25519` + its passphrase (or key loaded in ssh-agent) |
| Provider dashboard → **Terminal** tab | `root` | Root password; works **only** because sshd allows root+password from `45.81.252.94` |
| Anything else (e.g. `ssh root@45.81.252.43`) | — | **Refused** (`Permission denied (publickey)`) |

> ⚠️ Back up `%USERPROFILE%\.ssh\rmx-vps_ed25519` and remember the passphrase. If both the key and the dashboard terminal are lost, only the provider's console / rescue system can get you back in.

---

## 2. Local (Windows PC) setup

| Item | Value |
|---|---|
| `%USERPROFILE%\.ssh\` | Created (did not exist before) |
| Private key | `%USERPROFILE%\.ssh\rmx-vps_ed25519` (ed25519, passphrase-protected) |
| Public key | `%USERPROFILE%\.ssh\rmx-vps_ed25519.pub` — `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIELxb1opNw3MfIQJzUkGWRN68rBZSQbQrYgbbyFl45PY rmx-vps` |
| Key fingerprint | `SHA256:buE5PPY/pKGsMMYHrQLaRnG598ltv5jkqxvSpYVDZn4` |
| ssh-agent service | Changed from *Disabled/Stopped* → **Automatic/Running**; key added with `ssh-add` |
| `known_hosts` | Server host key added on first connect |

`%USERPROFILE%\.ssh\config` (new file):

```
Host rmx-vps
    HostName 45.81.252.43
    User rmx
    IdentityFile ~/.ssh/rmx-vps_ed25519
    IdentitiesOnly yes
```

---

## 3. Server state found before setup

- Only access: `root` + password (via keyboard-interactive/PAM).
- `/etc/ssh/sshd_config` line 47 had **`PubkeyAuthentication no`** — keys were refused entirely.
- `PermitRootLogin yes`, `KbdInteractiveAuthentication yes` (main file);
  `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf` had `PasswordAuthentication no`, but passwords still worked through keyboard-interactive.
- No firewall (ufw inactive), no fail2ban.
- Only public listener: sshd on port 22.
- Packages already up to date; a reboot was pending (newer kernel).

---

## 4. Changes made (in order)

| # | Time (UTC) | Change |
|---|---|---|
| 1 | ~19:24 | Public key appended to `/root/.ssh/authorized_keys` (via password login) |
| 2 | ~19:26 | `sshd_config` line 47 → `PubkeyAuthentication yes`, `systemctl reload ssh`. Backup: `/etc/ssh/sshd_config.bak-pubkey-off` (original file) |
| 3 | ~19:28 | `apt-get update && apt-get upgrade` — nothing to upgrade (3 phased: apparmor, libapparmor1, open-vm-tools) |
| 4 | ~19:29 | User `rmx` created (no password, shell `/bin/bash`, groups `sudo`) |
| 5 | ~19:29 | `/etc/sudoers.d/rmx` = `rmx ALL=(ALL) NOPASSWD:ALL` (root:root, 0440, checked with `visudo -c`) |
| 6 | ~19:29 | `/home/rmx/.ssh/authorized_keys` = same public key (rmx:rmx, dir 0700, file 0600) |
| 7 | ~19:49 | SSH hardening (see §5). Backup: `/etc/ssh/sshd_config.bak-pre-hardening`. Tested with a 5-min auto-rollback timer (`ssh-rollback`), cancelled after a fresh `ssh rmx-vps` login succeeded |
| 8 | ~19:51 | `ufw allow OpenSSH`, `ufw enable` |
| 9 | ~19:51 | `fail2ban` installed and enabled (default `sshd` jail) |
| 10 | ~19:56 | Rebooted → kernel `6.8.0-87` → `6.8.0-147`; everything verified after boot |
| 11 | ~20:04 | Dashboard terminal exception: root+password from `45.81.252.94` only (see §5). Backup: `/etc/ssh/sshd_config.bak-pre-dashboard`. IP whitelisted in fail2ban |
| 12 | ~20:06 | `/root/.ssh/authorized_keys` emptied — no key logs in as root any more |

---

## 5. Current SSH configuration

**`/etc/ssh/sshd_config.d/00-hardening.conf`** (new; read first, so it wins):

```
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
```

**`/etc/ssh/sshd_config`** (edited to match, so the file isn't misleading):

```
PermitRootLogin no                    # line 42
PubkeyAuthentication yes              # line 47
PasswordAuthentication no             # line 66
KbdInteractiveAuthentication no       # line 71

# appended at end of file:
# Provider dashboard web terminal (SSH bridge) - root password from this IP only
Match Address 45.81.252.94
    PermitRootLogin yes
    PasswordAuthentication yes
    KbdInteractiveAuthentication yes
```

> The `Match` block must stay at the **end** of the main file. Don't put it in `sshd_config.d/`: the drop-ins are included at the top of the main file, so a `Match` there would also apply to every setting after it.

Effective result (`sshd -T -C user=root,addr=…`):

| From | Root login | Password | Key |
|---|---|---|---|
| `45.81.252.94` (dashboard) | yes | yes | yes (but root has no keys) |
| anywhere else | **no** | **no** | yes (`rmx` only) |

Backups in `/etc/ssh/`:

| File | Contents |
|---|---|
| `sshd_config.bak-pubkey-off` | Original file (keys disabled, root+password open) |
| `sshd_config.bak-pre-hardening` | Keys enabled, before hardening |
| `sshd_config.bak-pre-dashboard` | Hardened, before the dashboard `Match` block |

---

## 6. Firewall & fail2ban

**ufw** — active, starts at boot:

```
Default: deny (incoming), allow (outgoing), disabled (routed)
22/tcp (OpenSSH)        ALLOW IN    Anywhere
22/tcp (OpenSSH (v6))   ALLOW IN    Anywhere (v6)
```

```
80/tcp                  ALLOW IN    Anywhere        # HTTP (Caddy, ACME)
443/tcp                 ALLOW IN    Anywhere        # HTTPS (Caddy)
(+ the same two for v6)
```

Opening another port: `sudo ufw allow PORT/tcp comment "what it is"`.

> ⚠️ **ufw does not protect Docker ports.** A port published by a container is reachable from the internet even without a ufw rule. See [§10](#10-docker--services).

**fail2ban** — enabled, `sshd` jail on, backend `systemd`, action `nftables`.

- `/etc/fail2ban/jail.d/defaults-debian.conf` — package default (enables `[sshd]`)
- `/etc/fail2ban/jail.d/ignore-dashboard.local` (new):
  ```
  [DEFAULT]
  ignoreip = 127.0.0.1/8 ::1 45.81.252.94
  ```

Useful commands:

```bash
sudo fail2ban-client status sshd          # bans / failures
sudo fail2ban-client set sshd unbanip IP  # unban an address
sudo ufw status verbose
```

---

## 7. Security audit (2026-10-14)

**Log coverage:** logs only cover **31 Oct – 3 Nov 2025** (hostname `ubuntu-2404`) and **14 Oct 2026 from 17:25** (hostname `vps3124`). There are **no journal entries or boots in between**. The root password was set and the hostname changed right after today's boot. This looks like a provider (re)deploy from a late-2025 image, not a year of continuous uptime. Deleted logs can't be ruled out, but nothing else points to that.

**Successful logins**

| IP | When | What | Assessment |
|---|---|---|---|
| *admin PC* (home IP omitted) | 2026-10-14 | root (password, then key), rmx (key) | Admin PC — expected |
| `213.159.55.52` | 2025-11-03 09:31 & 11:44 | root (password), ~1 min each; also 5 failed attempts | **Unverified** — probably the provider building the image. Confirm with the provider if you don't recognise it |

**Failed attempts** (all on 2026-10-14, about 2.5 hours of uptime): 37 PAM authentication failures, 35 `btmp` entries, ~10 source IPs. Top: `94.232.225.98` (9), `45.148.10.141` (9). Typical internet scanning. fail2ban banned `45.148.10.141` and `193.47.62.69` right after install.

**Persistence checks — nothing found:**
- UID 0 accounts: only `root`. Login shells: only `root`, `rmx`.
- `authorized_keys` on the whole disk: only the setup key (now `rmx` only).
- Crontabs: none for users; `/etc/cron.d` contains only `e2scrub_all`, `sysstat`.
- No custom systemd units; `/tmp`, `/var/tmp`, `/dev/shm` clean; no unusual processes.
- Public listeners: only sshd on 22.

---

## 8. Undo / maintenance

| Task | How |
|---|---|
| Stop / remove Caddy | See [§10 Undo](#undo) |
| Remove dashboard root access | Delete the `Match Address 45.81.252.94` block at the end of `/etc/ssh/sshd_config`, `sudo sshd -t && sudo systemctl reload ssh`; optionally remove `/etc/fail2ban/jail.d/ignore-dashboard.local` and `sudo systemctl restart fail2ban` |
| Change the root password | `sudo passwd root` (used only by the dashboard terminal) |
| Add another key / PC | Append its `.pub` line to `/home/rmx/.ssh/authorized_keys` |
| Always before restarting ssh | `sudo sshd -t`, and keep a working session open |
| Updates | `sudo apt update && sudo apt upgrade`; reboot if `/var/run/reboot-required` exists |

---

## 9. Updating this repo

After changing something on the server:

1. Add a dated entry to `CHANGELOG.md`: what changed, why, the backup file, how to undo it.
2. Update this README if the current state changed.
3. Refresh the config copies (PowerShell, from the repo folder):

   ```powershell
   ssh rmx-vps 'sudo cat /etc/ssh/sshd_config' | Set-Content config\ssh\sshd_config
   ssh rmx-vps 'sudo cat /etc/ssh/sshd_config.d/00-hardening.conf' | Set-Content config\ssh\sshd_config.d\00-hardening.conf
   ssh rmx-vps 'sudo cat /etc/fail2ban/jail.d/ignore-dashboard.local' | Set-Content config\fail2ban\jail.d\ignore-dashboard.local
   ssh rmx-vps 'sudo ufw status verbose' | Set-Content config\ufw\status.txt
   ssh rmx-vps 'cat /etc/docker/daemon.json' | Set-Content config\docker\daemon.json
   ssh rmx-vps 'cat /etc/apt/sources.list.d/docker.sources' | Set-Content config\docker\docker.sources
   ```

4. Commit and push:

   ```powershell
   git add -A
   git commit -m "Short description of the change"
   git push
   ```

5. Update the copy on the server (a read-only clone in `/opt/rmx-vps`, owned by `rmx`):

   ```powershell
   ssh rmx-vps 'git -C /opt/rmx-vps pull --ff-only'
   ```

   From the dashboard terminal (logged in as root), run it as `rmx` so file ownership stays correct:

   ```bash
   sudo -u rmx git -C /opt/rmx-vps pull --ff-only
   ```

On the server, `~/VPS-SETUP.md` (for both root and rmx) is a symlink to `/opt/rmx-vps/README.md`, so `less ~/VPS-SETUP.md` always shows the pulled version.

The server clone can also **push**, using a repo-only deploy key (see below). Pull before editing on either side, so the PC and server copies don't diverge.

### Pushing from the server

- Deploy key `/home/rmx/.ssh/github-rmx-vps` (ed25519, no passphrase), added to this repo with **write access**. It works for this repo only, not the rest of the GitHub account.
- `~rmx/.ssh/config` has `Host github-rmx-vps` → `github.com` with that key; the remote is `git@github-rmx-vps:jRmx0/rmx-vps.git`.
- Commit identity (repo-local): `jRmx0 <116594512+jRmx0@users.noreply.github.com>`.
- Always work as `rmx` (root has no access to the key):

  ```bash
  sudo -u rmx -i            # from the dashboard terminal
  cd /opt/rmx-vps && git pull --ff-only
  # edit, then:
  git add -A && git commit -m "…" && git push
  ```

- ⚠️ The repo is **public**: everything pushed from the server is published at once. Check `git diff --cached` before committing. Never commit secrets, home IPs or personal emails.
- To revoke: delete the key in GitHub → repo **Settings → Deploy keys**, then `rm ~/.ssh/github-rmx-vps*` on the server.

---

## 10. Docker & services

### Docker

- Docker Engine **29.9.1** + Compose plugin **v5.6.0**, from Docker's official apt repo (not Ubuntu's `docker.io` package).
  - Repo: `/etc/apt/sources.list.d/docker.sources` (copy in [`config/docker/`](config/docker/)), key `/etc/apt/keyrings/docker.asc`, fingerprint `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88` (matches Docker's docs).
  - Updates arrive with the normal `sudo apt update && sudo apt upgrade`.
- `/etc/docker/daemon.json`: container logs rotate at 10 MB × 3 files, so they can't fill the disk.
- `docker` and `containerd` start at boot. Containers with `restart: unless-stopped` come back after a reboot.
- `rmx` is in the `docker` group, so `docker …` works without `sudo`. (That group is effectively root, but `rmx` already has passwordless sudo.)

### ⚠️ Docker bypasses ufw — port policy

Docker writes its own iptables rules for published ports. That traffic goes through the `FORWARD` chain, and ufw's rules (on `INPUT`) never see it. **A published port is open to the whole internet, whatever ufw says.**

Tested on 2026-10-15 with a throwaway `nginx` container while ufw allowed only 22:

| Published as | ufw rule for 8080? | From the internet |
|---|---|---|
| `-p 8080:80` | none | **HTTP 200: reachable** |
| `-p 127.0.0.1:8080:80` | none | timeout: not reachable (only from the server itself) |

**Rules for this server:**

1. **Databases publish no ports.** They sit on the `backend` network, and only the app can reach them.
2. **Private tools** (admin UIs, dashboards, debug ports) bind to localhost: `"127.0.0.1:PORT:PORT"`. Reach them through an SSH tunnel from the PC: `ssh -L PORT:127.0.0.1:PORT rmx-vps`, then open `http://localhost:PORT`.
3. **Public ports are deliberate:** listed in the table below, documented in the CHANGELOG, and each gets a matching ufw rule, so `ufw status` stays an honest list of what's open.

Check what is really listening: `sudo ss -tlnp` and `docker ps --format '{{.Names}} {{.Ports}}'`.

### Layout

```
services/
├── compose.yaml          # project "rmx": includes each service, defines the networks
└── caddy/
    ├── compose.yaml      # Caddy container
    ├── Caddyfile         # sites, TLS, redirects
    ├── site/index.html   # placeholder page for rmx.lt
    └── data/             # (server only, gitignored) certificates + Caddy state
```

- Per-service secrets go in `services/<name>/.env` (gitignored). Commit a `.env.example` with placeholder values next to it.
- Runtime data goes in `services/<name>/data/` (gitignored, owned by root). It lives only on the server, and nothing backs it up.

**Networks** (defined in `services/compose.yaml`):

| Network | Docker name | Members | Notes |
|---|---|---|---|
| `edge` | `rmx_edge` | Caddy (later Mosquitto, app) | Normal bridge with internet access |
| `backend` | `rmx_backend` | (later app, database) | `internal: true`: no internet access. Created when the first service uses it |

### Public ports

| Port | Service | ufw | Purpose |
|---|---|---|---|
| 22/tcp | sshd (host) | ✅ | SSH |
| 80/tcp | Caddy | ✅ | Let's Encrypt HTTP-01 challenge, redirect to HTTPS |
| 443/tcp | Caddy | ✅ | HTTPS (HTTP/1.1 + HTTP/2). HTTP/3 is turned off, so 443/udp stays closed |

### Caddy

- Image `caddy:2.11` (2.11.7 when installed); container `rmx-caddy-1`.
- Sites:
  - `https://rmx.lt`: static placeholder page from `site/`
  - `https://api.rmx.lt`: placeholder JSON `{"service":"rmx-api","status":"placeholder"}`
  - `https://www.rmx.lt/…` → **301** to `https://rmx.lt/…`
  - every `http://…` → **308** to `https://…`
- Certificates: Let's Encrypt (issuer `YE2`), one per name, obtained automatically on first start (2026-10-15, valid until 2027-01-13). Caddy renews them about 30 days before they expire. No ACME email is set (Let's Encrypt no longer sends expiry emails, and an email would end up in this public repo).
- State: `services/caddy/data/data` → `/data` (certs, ACME account key) and `services/caddy/data/config` → `/config`. If these are deleted, Caddy just requests new certificates. Let's Encrypt allows 5 duplicate certificates per week, so don't delete them in a loop.

### Everyday commands (on the server)

```bash
cd /opt/rmx-vps/services
docker compose ps                         # what is running
docker compose logs -f caddy              # follow Caddy logs (Ctrl+C to stop)
docker compose up -d                      # start / apply compose changes
docker compose restart caddy              # apply Caddyfile / site changes
docker compose pull && docker compose up -d   # update images
```

Deploy a change made on the PC: commit + push, then `ssh rmx-vps 'git -C /opt/rmx-vps pull --ff-only'`, then run the matching command above. A changed `compose.yaml` needs `up -d`. A changed `Caddyfile` needs `restart caddy`: git replaces the file, and the container keeps seeing the old one until it restarts.

Check the certificates from the PC: `curl.exe -vI https://rmx.lt` (Windows curl verifies the chain and fails loudly if it's bad).

### Undo

| Undo | How |
|---|---|
| Stop Caddy (keep everything) | `cd /opt/rmx-vps/services && docker compose down` |
| Close 80/443 | `sudo ufw delete allow 80/tcp && sudo ufw delete allow 443/tcp`. Also stop Caddy, because Docker keeps the ports open without ufw |
| Delete Caddy's certificates and state | `sudo rm -rf /opt/rmx-vps/services/caddy/data` (after `down`) |
| Remove Docker completely | `docker compose down`, then `sudo apt purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras`, `sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc`, `sudo gpasswd -d rmx docker` |
