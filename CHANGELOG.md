# Changelog — rmx-vps (45.81.252.43)

Newest entries at the top. Times in UTC. For each change, record **what**, **why**, the **backup** file, and how to **undo** it.

---

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
