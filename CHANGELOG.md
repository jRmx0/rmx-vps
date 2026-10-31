# Changelog — rmx-vps (45.81.252.43)

Newest entries at the top. Times in UTC. For each change, record **what**, **why**, the **backup** file, and how to **undo** it.

---

## 2026-10-31 — Repos moved to the `rmx-lt` organization: probe image from `ghcr.io/rmx-lt` (not applied yet)

- *Why:* the project repos moved from `jRmx0` to the `rmx-lt` organization. GitHub redirects repo URLs, but GHCR packages don't move, so rmx-backend-probe now publishes `ghcr.io/rmx-lt/rmx-backend-probe` (rmx-backend-probe#16). Issue #11, parent rmx-lt/blade-of-grass#1.
- *Changed:* `services/probe/compose.yaml` image; `rmx-deploy-probe.sh` `IMAGE` and the prune filter (label `org.opencontainers.image.source=https://github.com/rmx-lt/rmx-backend-probe`); repo URLs in the README, `ansible/bootstrap.sh`, `group_vars` `repo_url` and the server remote in `roles/stack/tasks/repo.yml`. Older entries below keep the old URLs as history.
- *Apply (before rmx-backend-probe#17 merges):* `sudo -u rmx git -C /opt/rmx-vps remote set-url origin git@github-rmx-vps:rmx-lt/rmx-vps.git`, `sudo -u rmx git -C /opt/rmx-vps pull --ff-only`, `sudo install -m 0755 /opt/rmx-vps/services/probe/deploy/rmx-deploy-probe.sh /usr/local/sbin/rmx-deploy-probe`. After the first good `rmx-lt` deploy: `docker image prune -af --filter "label=org.opencontainers.image.source=https://github.com/jRmx0/rmx-backend-probe"`.
- *Undo:* revert this commit, reinstall the script, deploy an old `jrmx0` tag by hand (`sudo rmx-deploy-probe sha-…`).

---

## 2026-10-30 — CI/CD: development → production, automatic deploy with encrypted backup (not applied yet)

- *Why:* Justas wants merges to deploy the server by themselves, with a backup first, and CI to prove the playbook builds a server from empty. Issue #9.
- *Added:* `.github/workflows/deploy.yml` (push to `production`: backup → `--check --diff` → apply → smoke test); `ansible.yml` gains `container` (server from empty twice, drift visible) and `db-roundtrip` (backup/restore of TimescaleDB and the Mosquitto store); `ansible/ci/rmx-ci.sh` (`backup`, `check:<sha>`, `apply:<sha>`, `restore`) and `sudoers-ci`; user `ci` with a forced-command key (only when `vault_ci_ssh_key` is set); `repo_branch: production` (bootstrap.sh and the clone follow it).
- *Backup:* config + `pg_dump` + Mosquitto store, encrypted on the runner with `age` (the private key stays on the PC), artifact kept 7 days. Data restore: `sudo rmx-ci restore`.
- *Tested:* `db-roundtrip.sh` and `container-test.sh` run here; the workflows, branch protection and the real deploy are untested until the secrets and branches exist.
- *Applied:* nothing on the live server. Setup steps: `ansible/README.md` → CI/CD.
- *Undo:* revert the PR; on the server `sudo userdel -r ci; sudo rm /etc/sudoers.d/ci /usr/local/sbin/rmx-ci`.

---

## 2026-10-30 — Setup as code: Ansible playbook + vault (not applied to the live server yet)

- *Why:* the server was built by hand, so what it is lived in this log and in memory. The goal is a lean server that can be rebuilt from empty and where nothing done by hand lingers. Justas chose Ansible + Ansible Vault, and a rebuild by reinstalling the VPS (nothing real runs on it, so downtime is fine; database data is not kept).
- *Added:* `ansible/` (roles `base`, `users`, `ssh`, `firewall`, `docker`, `stack`; `bootstrap.sh` for a fresh VPS; `export-vault.sh` to collect the current server's secrets; runbook in `ansible/README.md`), a CI check (`.github/workflows/ansible.yml`: syntax, lint, vault must be encrypted), README §11.
- *Also in the code, new compared with the hand-built server (from the 2026-10-23 security review):* `X11Forwarding no`, `AllowUsers rmx deploy root@<dashboard IP>`, `Match User deploy` with `DisableForwarding yes`, unattended security updates with a 04:30 reboot, kernel network settings (no redirects/source routing, `rp_filter`, martian logging), `snapd` removed, old `sshd_config.bak-*` removed, ufw rules not in the list are deleted.
- *Tested:* a fresh `ubuntu:24.04` container with systemd, Docker inside: the whole playbook ran from empty (Docker's key fingerprint verified, Mosquitto 2.1.2 up with all logins and the synced certificate, Caddy up, sshd/ufw/sudoers results checked), a second run changed nothing, `--check --diff` showed a manual sshd change. **Not tested:** Let's Encrypt issuance and the HTTPS smoke test (no DNS in the container), `-e probe=on` (needs the real image), the swapfile (container), a real reboot.
- *Applied:* nothing on the live server. Next: `export-vault.sh` there, encrypt and commit the vault, `--check --diff`, then reinstall from the provider dashboard and run `bootstrap.sh`.
- *Undo:* nothing to undo on the server; revert the PR.

## 2026-10-22 — Caddy: `/fw/*` for OTA firmware images (basic auth)

- *Why:* the LTE modem board (rmx-mower-modem-probe PR #9) updates its firmware over the air from `https://api.rmx.lt/fw/probe/<version>.bin`. The images are signed (the key exists only on the PC), and the login only keeps casual downloads away. Justas approved the route on 2026-10-22.
- *Caddy:* PR #5. `handle /fw/*` in `api.rmx.lt` → `file_server` from `caddy/firmware/` (read-only mount at `/srv/fw`), `basic_auth` users imported from `caddy/private/fw-users.caddy` (server only, gitignored, template `fw-users.caddy.example`). Two new read-only mounts in `caddy/compose.yaml`.
- *Applied:* `git pull --ff-only` (ca22540), created `caddy/firmware/probe/`, `caddy/private/fw-users.caddy` (login `probe-device`, bcrypt hash from `docker exec rmx-caddy-1 caddy hash-password`) and `caddy/private/credentials.txt` (root, `0600`, plain-text copy), then `docker compose up -d caddy`. The password was copied into the device's gitignored `sdkconfig` over ssh without being printed.
- *Tested:* `/fw/probe/x.bin` without a login → 401; `rmx.lt` → 200; `/probe/health` → 200; no errors in the Caddy log. From the device over LTE: first OTA 0.2.0 → 0.2.1 (856 KB) downloaded in ~2 min, rebooted into `ota_1`, confirmed itself after MQTT connected; ~3 min from command to confirmed.
- *Undo:* revert PR #5, `docker compose up -d caddy`, then `sudo rm -r caddy/firmware caddy/private`.

## 2026-10-20 — MQTT for devices only (no browser MQTT), like production

- *Why:* production browsers will talk only to the backend (HTTPS + its WebSocket, with a session); only devices and the backend talk to the broker. The probe's browser MQTT (`wss://mqtt.rmx.lt/mqtt` → Mosquitto 9001, login `probe-web`) is no longer needed: the LTE modem probe tests MQTT on 8883 (`probe-device`). Removing it also closes the client-ID takeover over WebSockets, and Mosquitto now sees the real IP of every MQTT client.
- *App:* rmx-backend-probe PR #12 (deployed as `sha-f2c3941`): no MQTT in the page, `MQTT_WS_URL` and `/probe/config.json` removed.
- *Mosquitto:* listener 9001 (websockets) removed from `mosquitto.conf`; `probe-web` removed from `config/acl` (reinstalled 0600), from the password file (`mosquitto_passwd -D`) and from `data/credentials.txt`. `docker compose restart mosquitto` (listeners only change on restart; all clients reconnect).
- *Caddy:* `mqtt.rmx.lt` answers only the one-line text (the block still gets the certificate for 8883); the `/mqtt` route is gone.
- *Probe compose:* `MQTT_WS_URL` removed.
- *Applied:* `git merge --ff-only` on the server, the new Caddyfile validated in a throwaway container, `probe-web` removed (`mosquitto_passwd -D`, ACL reinstalled 0600, its line deleted from `credentials.txt`), `docker compose restart mosquitto`, then Caddy and probe-app recreated.
- *Tested:* Mosquitto listens only on 1883 (internal) and 8883, no errors in its log; probe-app (`sha-f2c3941`, no `MQTT_WS_URL`) and the **modem probe** (`probe-device`, 8883) reconnected by themselves within seconds; an upgrade request to `wss://mqtt.rmx.lt/mqtt` now gets the plain text (200), not 101; `/probe/health` 200; `tests/mqtt-tests.ps1` 12/12.
- *Undo:* revert this commit; re-add `probe-web` with `mosquitto_passwd` (new password into `credentials.txt`), reinstall the ACL, `docker compose restart mosquitto`, recreate Caddy; deploy an app image from before the change.

## 2026-10-19 — Mosquitto + probe: `probe-device` login for the ESP32 LTE probe

- *Why:* the LilyGo T-SIM7600 firmware (github.com/jRmx0/rmx-mower-modem-probe) talks to the probe over MQTT on 8883 and HTTPS. The user chose a dedicated login instead of sharing `probe-web`: on 8883 the client id is forced to the username, so the device gets its own `probe/req|res/probe-device` pair, and it can't read other clients' responses.
- *Mosquitto:* new login `probe-device` (random 32-character password, `data/credentials.txt`). `config/acl`: `user probe-device` → write `probe/req/probe-device`; read `probe/res/probe-device`, `probe/events/#`, `probe/status/#` (plus `mower/probe-device/#` from the pattern; the device uses `mower/probe-device/status` as its retained status and last will). Installed with `install -o 1883 -g 1883 -m 0600` + HUP (no disconnects).
- *Probe app:* web user `probe-device` (`probe-server create-user`, 24-character password from stdin), plain-text copy as `app-login probe-device …` in `probe/data/credentials.txt`.
- The passwords were copied into the device's gitignored `sdkconfig` over ssh without being printed.
- *Applied:* `git merge --ff-only` of this branch on the server, then a one-off script (scp to `/tmp`, `sudo bash`, deleted).
- *Tested from the device over LTE:* MQTT CONNACK as `probe-device`, `create`/`list` on `probe/req/probe-device` answered on `probe/res/probe-device`, `probe/events/records` and the retained `probe/status/server` received; HTTPS login → 200 + cookie, create → 201, list → 200. 4 test records (ids 30–33) were left in the probe DB.
- *Undo:* `docker compose exec -u mosquitto mosquitto mosquitto_passwd -D /mosquitto/auth/passwd probe-device`, remove the `probe-device` block from `config/acl`, reinstall the ACL + HUP, delete its line in `mosquitto/data/credentials.txt`; `docker compose exec -T probe-app /app/probe-server delete-user probe-device` and delete its line in `probe/data/credentials.txt`.

## 2026-10-19 — Probe: the app's own login replaces Caddy basic auth

- *Why:* basic auth can't do a real logout, sends the password with every request, and iOS WebKit doesn't send it on WebSocket handshakes (yesterday's `probe_ws` cookie was a stopgap). Production will need a real login with server-side sessions, so the probe rehearses it first: rmx-backend-probe PR #9 (deployed as `sha-4537af9`).
- *App (rmx-backend-probe):* login page, `users` table (Argon2id), `sessions` table (only a SHA-256 of the 256-bit cookie token is stored; 7-day idle, 30-day absolute timeout), cookie `__Secure-probe_session` (`HttpOnly; Secure; SameSite=Strict; Path=/probe`), checked on the API, `/probe/ws` and `/probe/config.json`; `/probe/health` stays public. Origin check against `ALLOWED_ORIGINS`, login backoff per username and IP. Details: its README, "Login and sessions".
- *Caddy:* removed `basic_auth`, the `probe_ws` cookie (`@probe_ws_cookie` and the `Set-Cookie` header) and the `env_file`. `caddy/.env` (`PROBE_AUTH_USER`, `PROBE_AUTH_HASH`, `PROBE_WS_TOKEN`) deleted on the server, `caddy/.env.example` deleted from the repo. Closed by default still holds: the app requires its login for everything but health, login and the static page; probe off → 502.
- *Probe compose:* `ALLOWED_ORIGINS: https://api.rmx.lt` (required by the new image; the server doesn't start without it).
- *First user:* `probe`, created with `probe-server create-user` (password piped from stdin, 24 random characters). `probe/data/credentials.txt`: the basic-auth line was replaced by the app login.
- *Applied:* `git merge --ff-only` on the server, the new Caddyfile validated in a throwaway `caddy:2.11` container, then `docker compose up -d --force-recreate caddy` (a few seconds of downtime for all sites), `caddy/.env` deleted, `docker compose --profile probe up -d probe-db probe-app` → healthy on `sha-4537af9`.
- *Tested from the PC* (curl, 22/22): health and the page public; REST, `config.json` and the WebSocket → 401 without a cookie, with a forged cookie, after logout and after the session was expired in the DB; wrong password → 401; login from a foreign Origin → 403; login → 200 with `Path=/probe; HttpOnly; Secure; SameSite=Strict`; with the cookie: REST and `config.json` 200, POST without Origin or with a foreign one → 403, with `https://api.rmx.lt` → 201; WebSocket with cookie + Origin → 101, foreign Origin → 403. The user tested **PC and iPhone** in the browser: login, HTTPS, WSS, MQTT and logout all work (WSS on the iPhone included).
- The probe was left **running** afterwards, at the user's request.
- *Undo:* deploy an image from before the login (`sudo rmx-deploy-probe sha-7fd8f6c`) and revert this commit (Caddy basic auth, `caddy/.env` with a new hash: `docker compose exec caddy caddy hash-password`). The `users`/`sessions` tables stay in the DB and are ignored by the old image.

## 2026-10-18 — Caddy: WebSocket cookie for iPhones

- *Problem:* on an iPhone (Chrome, i.e. WebKit) the probe page kept asking for the login, and WSS never connected. A temporary access log (reload only, gone after the next restart) showed every normal request with `Authorization` (200) and every `/probe/ws` upgrade **without** it (401). WebKit doesn't send basic-auth credentials on WebSocket handshakes. PC and phone didn't share anything.
- *Fix (Caddy only):* after a basic-auth login, Caddy sets the cookie `probe_ws=<PROBE_WS_TOKEN>` (`Path=/probe/ws`, 24 h, `Secure; HttpOnly; SameSite=Strict`); a new `@probe_ws_cookie` handle lets `/probe/ws` through with exactly that value (CEL `expression`, exact match, and the token must be ≥ 32 characters, otherwise the path is off). New `PROBE_WS_TOKEN` (48 hex chars) in `caddy/.env`; template in `caddy/.env.example` with a placeholder that is too short on purpose.
- Tested with curl: right cookie → 101 without a password; wrong, empty or no cookie → 401; the cookie alone doesn't open the page or REST (401).
- Undo: remove the `@probe_ws_cookie` block and the `header Set-Cookie` line from the Caddyfile, delete `PROBE_WS_TOKEN` from `caddy/.env`, `docker compose up -d --force-recreate caddy`.

## 2026-10-18 — Probe off by default

- After the end-to-end test (auto-deploy verified: merging rmx-backend-probe PR #5 deployed `sha-3402713` by itself), the probe was stopped with `docker compose stop probe-app probe-db`, and **off** is now the default.
- *Why:* it's a learning tool, and the 1 GB VPS keeps ~50–70 MB more free when it's off. Deploys still run while it's off: the script records and pulls the tag but doesn't start anything.
- Undo / use it: `docker compose --profile probe up -d` (README §10 → Probe).

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
