# Changelog — rmx-vps (45.81.252.43)

Newest entries at the top. Times in UTC. For each change, record **what**, **why**, the **backup** file, and how to **undo** it.

---

## 2026-10-18 — rmx-backend-probe deployed, with auto-deploy

*Why:* the probe (github.com/jRmx0/rmx-backend-probe) rehearses the whole production workflow: a Rust app plus a TimescaleDB container, routes behind Caddy, browser MQTT over WebSockets, and auto-deploy from GitHub Actions on merge to `main`. This setup will be copied for the production app.

### Probe containers (Compose profile `probe`)
- New `services/probe/compose.yaml`, included from `services/compose.yaml`. Its variables (passwords and `PROBE_TAG`, the deployed image) come from `probe/.env` (server only), which Compose reads automatically next to the included file. It's optional, and there are no `${VAR:?}` checks, so a missing file breaks only the probe, not Caddy or Mosquitto.
- `probe-db`: `timescale/timescaledb:2.30.2-pg17`, `rmx_backend` only, no ports, `mem_limit 256m`, tuned for 1 GB (`shared_buffers=32MB`, `work_mem=2MB`, `max_connections=20`, no parallel workers, 3 TimescaleDB background workers, telemetry off), health check `pg_isready`. Data in `probe/data/db/`.
- `probe-app`: `ghcr.io/jrmx0/rmx-backend-probe:sha-…`, `rmx_edge` + `rmx_backend`, no ports, `mem_limit 64m`, starts after the DB is healthy. Running: DB ~60 MB, app ~8 MB.
- Profile `probe`: a plain `docker compose up -d` doesn't start it. Stop it with `docker compose stop probe-app probe-db`. (Found the hard way: `docker compose --profile probe stop` without names stops Caddy and Mosquitto too; about a minute of downtime, restarted with `docker compose up -d`.)

### Mosquitto
- New logins `probe-app` (`probe/#`) and `probe-web` (write `probe/req/+`; read `probe/res/+`, `probe/events/#`, `probe/status/#`), random 32-character passwords in `data/credentials.txt`.
- New listener **9001** `protocol websockets`, not published, for browsers through Caddy. `use_username_as_clientid` stays on 8883 only (it is per listener), so several probe tabs can share the `probe-web` login. Known limit: client IDs are shared across listeners (README §10).
- `tests/mqtt-tests.ps1`: the client-ID test filtered the server log with `grep` inside a double-quoted remote command, which Windows PowerShell 5.1 mangles. It now filters locally. 12/12 pass in PowerShell 5.1 and 7.

### Caddy
- `api.rmx.lt`: `/probe` and `/probe/*` → `probe-app:8080` (prefix kept) behind `basic_auth` (user `probe`). The hash comes from `caddy/.env` (server only) via an optional `env_file`; template `caddy/.env.example`. Without it, the Caddyfile falls back to the hash of a random password that was thrown away, so `/probe` stays locked and Caddy still starts. Probe off → 502.
- `mqtt.rmx.lt`: `/mqtt` → `mosquitto:9001` (WebSockets); everything else still answers the one-line text, so the 8883 certificate keeps renewing.

### Auto-deploy
- New user `deploy` (no password, not in `sudo`/`docker`), one SSH key with `restrict,command="sudo -n /usr/local/sbin/rmx-deploy-probe \"$SSH_ORIGINAL_COMMAND\""`.
- `/etc/sudoers.d/deploy`: that script only, argument `^sha-[0-9a-f]{7}$` only. Checked with `visudo -cf` before installing, then `visudo -c`.
- `/usr/local/sbin/rmx-deploy-probe` (source `services/probe/deploy/rmx-deploy-probe.sh`): validate, lock, pull, write the tag, recreate `probe-app`, wait for healthy, roll back on failure, log to `/var/log/rmx-deploy-probe.log` and the journal.
- Tested from the PC with the deploy key: shell commands, `;` injection, no command and port forwarding refused; unknown tag → nothing changed; older tag → deployed; rollback with the DB stopped → previous tag restored, exit 1.
- GitHub secrets `DEPLOY_HOST`, `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS` set on rmx-backend-probe; no copy of the private key is kept anywhere else.

### Tested end to end (from the PC)
- `/probe/health` ok (db and mqtt true), basic auth required (401 without), `/probe` → 308 `/probe/`, `/probe/config.json` gives `wss://mqtt.rmx.lt/mqtt`.
- Scripted: REST create, WSS create + live event, MQTT over WSS as `probe-web` with two client IDs at once, responses only to the asking client, events to both, forged events and `mower/#` blocked by the ACL.
- TimescaleDB: `record_events` is a hypertable with compression and retention policies; events from https, wss and mqtt are logged.

### Undo
- README §10 → Probe → Remove. Backups: none (by choice).

## 2026-10-15 — Mosquitto: MQTT over TLS on mqtt.rmx.lt:8883

*Why:* Phase 3. The mowers need a broker for telemetry, status and commands. It needs TLS and a login, and each mower may use only its own topics.

### Caddy
- New `mqtt.rmx.lt` site block in `services/caddy/Caddyfile` (responds with a one-line text). It's there so Caddy obtains and renews the certificate that Mosquitto uses. Let's Encrypt issued it on 2026-10-15 (issuer `YE1`, valid until 2027-01-13).

### Mosquitto
- New service `services/mosquitto/` (included from `services/compose.yaml`): `eclipse-mosquitto:2.1-alpine` (2.1.2), container `rmx-mosquitto-1`, on `rmx_edge`, `mem_limit: 64m`, `restart: unless-stopped`.
- `config/mosquitto.conf`: listener **8883** with TLS (minimum 1.2) and `use_username_as_clientid`, plus listener **1883** (plain MQTT, *not published*, for the app container). `allow_anonymous false`, password file, ACL file, persistence on, logs to stdout.
- `config/acl`: `app` → `mower/#`; every other login → `mower/<username>/#` (`pattern … %u`). An installed copy (`data/auth/acl`, owner 1883, `0600`) is used because Mosquitto warns about world-readable ACL files, and future versions will refuse them.
- Logins `app` and `mower-01` with random 32-character passwords. Hashes are in `data/auth/passwd`; the plain-text passwords are in `data/credentials.txt` (root, `0600`). Both are server only and gitignored.
- `tests/mqtt-tests.ps1`: test suite run from the Windows PC over the internet. 12/12 passed: valid chain for `mqtt.rmx.lt`, TLS 1.1 refused, mower-01 publish and subscribe on its own topics, retained status, mower-01 gets nothing from mower-02's topics and can't publish there, anonymous and wrong password refused, client-ID takeover, 1883 not reachable.
- Found while testing: on Windows, the Mosquitto clients' `--tls-use-os-certs` and `-W` don't work. The test script works around both (README §10).

### Certificate sync (new on the host)
- `/usr/local/sbin/rmx-mqtt-cert-sync`, `/etc/systemd/system/rmx-mqtt-cert-sync.service` and `.timer` (sources in `services/mosquitto/cert-sync/`). Twice a day, the script copies Caddy's cert and key for `mqtt.rmx.lt` to `services/mosquitto/data/certs/` (owner 1883, key `0600`) if they changed, then sends SIGHUP to Mosquitto.
- *Why:* Caddy's certificate files are root-only, and Mosquitto runs as uid 1883. Copying avoids a second ACME client and keeps Caddy's data private. Tested: after SIGHUP, Mosquitto serves the new certificate without a restart.

### Firewall
- `ufw allow 8883/tcp comment "MQTT over TLS (Mosquitto)"` (IPv4 + IPv6). ufw now allows 22, 80, 443 and 8883.

### Undo
- See README §10 → Undo ("Close 8883", "Remove Mosquitto completely"). No backup of the logins or retained messages (by choice).

## 2026-10-15 — 2 GB swapfile

- `/swapfile` (2 GB, root-only `0600`) created with `fallocate`, `mkswap`, `swapon`; `/swapfile none swap sw 0 0` appended to `/etc/fstab` so it turns on at boot (checked with `findmnt --verify` and systemd's `swapfile.swap` unit, no reboot needed).
- `/etc/sysctl.d/60-swappiness.conf`: `vm.swappiness=10` (default 60), so the kernel swaps only under real memory pressure.
- *Why:* the VPS has ~1 GB RAM and had no swap, so a memory spike (DB query, image pull, apt upgrade) would make the OOM killer kill a process, often the database. Swap turns that into a short slowdown. Done before adding TimescaleDB.
- Backup: `/etc/fstab.bak-pre-swap`.
- Undo: `sudo swapoff /swapfile`, remove the line from `/etc/fstab`, `sudo rm /swapfile /etc/sysctl.d/60-swappiness.conf`, `sudo systemctl daemon-reload`.

## 2026-10-15 — Docker + Caddy (HTTPS for rmx.lt)

### Docker
- Installed Docker Engine 29.9.1 + Compose v5.6.0 (`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`) from Docker's official apt repo. Key fingerprint checked: `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`.
- `/etc/docker/daemon.json`: json-file logs rotated at 10 MB × 3.
- `rmx` added to the `docker` group.
- *Why:* every part of the IoT backend (Caddy, Mosquitto, app, DB) runs as a Compose service.
- **Docker bypasses ufw.** Tested: a throwaway nginx on `-p 8080:80` was reachable from the internet with no ufw rule, and on `-p 127.0.0.1:8080:80` it wasn't. The container and image were removed afterwards. Port policy written in README §10.
- Undo: README §10 → Undo ("Remove Docker completely").

### Repo
- New `services/` layout: `services/compose.yaml` (project `rmx`, `include`s each service; networks `edge` = `rmx_edge` and `backend` = `rmx_backend`, internal) and `services/caddy/`.
- `.gitignore`: `services/*/data/` (runtime data) and `!.env.example` (`.env` stays ignored).
- `config/docker/`: copies of `daemon.json` and `docker.sources`.

### Firewall
- `ufw allow 80/tcp` (HTTP, ACME) and `ufw allow 443/tcp` (HTTPS), with comments. ufw now allows 22, 80, 443 only.
- *Why:* needed for Let's Encrypt and HTTPS. Docker would open them anyway, but the rule keeps `ufw status` honest.
- Undo: `sudo ufw delete allow 80/tcp && sudo ufw delete allow 443/tcp` (and stop Caddy).

### Caddy
- `caddy:2.11` (2.11.7) running as `rmx-caddy-1` from `/opt/rmx-vps/services`, on the `edge` network, publishing 80 and 443/tcp only (HTTP/3 off).
- `rmx.lt` → placeholder page; `api.rmx.lt` → placeholder JSON; `www.rmx.lt` → 301 to `rmx.lt`; HTTP → 308 to HTTPS.
- Let's Encrypt certificates for `rmx.lt`, `api.rmx.lt`, `www.rmx.lt` obtained automatically (issuer `YE2`, valid until 2027-01-13). Verified from the PC with `curl.exe -v`; chain valid.
- State persisted on the server in `services/caddy/data/` (gitignored). No backup (by choice).
- Undo: `cd /opt/rmx-vps/services && docker compose down`; optionally `sudo rm -rf caddy/data`.

## 2026-10-14 — push access from the server (deploy key)

- New key `/home/rmx/.ssh/github-rmx-vps` (ed25519, no passphrase, comment `rmx-vps-server-deploy`), added on GitHub as a **deploy key with write access** to this repo only.
- `~rmx/.ssh/config`: `Host github-rmx-vps` (github.com, that key, `IdentitiesOnly yes`). GitHub's ED25519 host key was verified (`SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`) and added to `~rmx/.ssh/known_hosts`.
- `/opt/rmx-vps` remote changed to `git@github-rmx-vps:jRmx0/rmx-vps.git`; repo-local identity set to `jRmx0` with the GitHub no-reply email.
- *Why:* allows editing the docs from the server (e.g. in the dashboard terminal). A deploy key rather than an account key, so a compromised server can only touch this repo.
- Undo: delete the deploy key on GitHub, `rm ~/.ssh/github-rmx-vps*`, remove the `Host github-rmx-vps` block, then `git remote set-url origin https://github.com/jRmx0/rmx-vps.git`.
- This entry was committed and pushed **from the server** as the first test of the key.

## 2026-10-14 — docs repo cloned to the server

- `git` 2.43.0 used to clone `https://github.com/jRmx0/rmx-vps.git` to `/opt/rmx-vps` (owner `rmx`, read-only: no push credentials on the server).
- `/root/VPS-SETUP.md` and `/home/rmx/VPS-SETUP.md` replaced with symlinks to `/opt/rmx-vps/README.md`.
- Root's git config: `safe.directory /opt/rmx-vps`, so root can run read-only git commands in the rmx-owned repo.
- *Why:* one source of truth. The server copy updates with `git pull` instead of manual `scp`.
- Undo: `sudo rm -rf /opt/rmx-vps /root/VPS-SETUP.md /home/rmx/VPS-SETUP.md`.

## 2026-10-14 — initial access & hardening

**Why:** the only way in was `root` + password, open to the internet. Goal: key-based login as a non-root admin user, then lock everything else down.

### Local PC
- Created `%USERPROFILE%\.ssh\`, key `rmx-vps_ed25519` (ed25519, passphrase), fingerprint `SHA256:buE5PPY/pKGsMMYHrQLaRnG598ltv5jkqxvSpYVDZn4`.
- Windows `ssh-agent` service: Disabled → Automatic, started; key added with `ssh-add`.
- New `~/.ssh/config` with the `Host rmx-vps` alias.

### Server
- **~19:24** Public key added to `/root/.ssh/authorized_keys` (temporary, removed at 20:06).
- **~19:26** `sshd_config` line 47 `PubkeyAuthentication no` → `yes`. The server was refusing keys entirely.
  Backup: `/etc/ssh/sshd_config.bak-pubkey-off`.
- **~19:28** `apt update && apt upgrade`: nothing to upgrade.
- **~19:29** User `rmx` created, in the `sudo` group; `/etc/sudoers.d/rmx` = `NOPASSWD:ALL` (0440); key installed in `/home/rmx/.ssh/authorized_keys`.
- **~19:49** SSH hardening: new `/etc/ssh/sshd_config.d/00-hardening.conf` (keys only, no root, no password or keyboard-interactive); main file edited to match.
  Backup: `/etc/ssh/sshd_config.bak-pre-hardening`. Tested with a 5-min auto-rollback timer, cancelled after a fresh login worked.
- **~19:51** `ufw` enabled, only OpenSSH (22/tcp) allowed in.
- **~19:51** `fail2ban` installed, default `sshd` jail.
- **~19:56** Reboot: kernel `6.8.0-87` → `6.8.0-147`.
- **~20:04** `Match Address 45.81.252.94` block at the end of `sshd_config` allows root + password **from that IP only**.
  *Why:* the provider dashboard's "VPS Terminal" is an SSH bridge from that IP that logs in as root with a password.
  The IP was also added to fail2ban `ignoreip` (`/etc/fail2ban/jail.d/ignore-dashboard.local`).
  Backup: `/etc/ssh/sshd_config.bak-pre-dashboard`.
  Undo: delete the `Match` block, `sshd -t && systemctl reload ssh`.
- **~20:06** `/root/.ssh/authorized_keys` emptied, so no key can log in as root.
- **~20:09** This log copied to `/root/VPS-SETUP.md`.

### Audit findings
- Logs cover only 2025-10-31 → 2025-11-03 and 2026-10-14 from 17:25, with nothing in between. This looks like a provider redeploy, not a year of uptime.
- Unknown successful root logins: `213.159.55.52` on 2025-11-03 (probably the provider's image build). **To confirm with the provider.**
- Failed attempts today: ~37 from ~10 IPs (scanners). No persistence found.
