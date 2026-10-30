# RMX-SERVER as code (Ansible)

An empty Ubuntu 24.04 VPS becomes RMX-SERVER with one command. The playbook describes the **end state**, so it is safe to run again: it changes only what differs, and `--check --diff` shows what it would change without touching anything.

| Role | What it sets up |
|---|---|
| `base` | `apt` upgrade, unattended security updates (reboot at 04:30 when needed), 2 GB swapfile, kernel settings |
| `users` | admin user `rmx` (key only, sudo), `deploy` user for GitHub Actions (forced command) |
| `ssh` | sshd: keys only, no root except from the provider dashboard, host keys from the vault |
| `firewall` | ufw: only the ports in `group_vars/all/vars.yml` (`public_ports`); fail2ban |
| `docker` | Docker Engine + Compose from Docker's apt repo (key fingerprint checked) |
| `stack` | the clone in `/opt/rmx-vps`, the secrets of Caddy / Mosquitto / probe, cert-sync timer, deploy script, `docker compose up`, then a smoke test |

Everything the old README §3–§10 did by hand is in these roles. Settings that aren't secret are in [`group_vars/all/vars.yml`](group_vars/all/vars.yml); secrets are in `group_vars/all/vault.yml`, encrypted.

## The vault

`vault.yml` holds every secret a rebuild needs: SSH host keys, Mosquitto passwords, the `/fw/` logins, the probe's database and app passwords, the deploy key. It is committed **encrypted** (AES-256, Ansible Vault); the repo is public, so use a long random vault password and keep it in your password manager. Lose it and the vault can't be opened.

```bash
# keep the passwords of the CURRENT server (once, on the old server, before reinstalling)
cd /opt/rmx-vps/ansible && sudo ./export-vault.sh     # writes group_vars/all/vault.yml, prints nothing secret
ansible-vault encrypt group_vars/all/vault.yml        # asks for the new vault password
git add group_vars/all/vault.yml && git commit -m "Vault" && git push

ansible-vault edit group_vars/all/vault.yml           # change a value later
```

Template with every field: [`group_vars/all/vault.yml.example`](group_vars/all/vault.yml.example). Do not commit an unencrypted `vault.yml`: CI fails the pull request if the file doesn't start with `$ANSIBLE_VAULT`.

## Build a server from empty

1. Provider dashboard → reinstall Ubuntu 24.04 (this erases everything).
2. Open the dashboard terminal (root) and run:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/jRmx0/rmx-vps/main/ansible/bootstrap.sh | bash
   ```

   It installs git and Ansible, clones this repo to `/opt/rmx-vps`, asks for the vault password and runs the playbook on the server itself. About 10 minutes.
3. Check: the smoke test at the end of the run answers for the sites, `/fw/` login and MQTT's TLS port. Then `ssh rmx-vps` from the PC (the host key is the same as before, so no warning).

DNS must already point at the server's IP: Caddy gets its certificates from Let's Encrypt during the run. Without DNS the run continues, Mosquitto waits for its certificate, and the cert-sync timer retries twice a day.

## Day to day

Change the repo, push, then on the server:

```bash
cd /opt/rmx-vps/ansible
./bootstrap.sh --check --diff        # what would change (nothing is applied)
./bootstrap.sh                       # apply
./bootstrap.sh --tags ssh            # only one role: base users ssh firewall docker stack
./bootstrap.sh -e probe=on           # also start the probe and create its app logins
./bootstrap.sh -e reset_mqtt_passwords=true   # after editing Mosquitto passwords in the vault
```

Run it from the PC instead (WSL, or any Linux with Ansible): `ansible-playbook site.yml --ask-vault-pass -e target=remote`.

Run `--check --diff` now and then. A difference means somebody changed the server by hand: either put it in the repo or let the next run undo it.

## What it does not do

- Create or reinstall the VPS, DNS records, GitHub secrets, the device firmware: all outside the server.
- Restore **data**: the probe database and Mosquitto's retained messages start empty after a reinstall (by choice, see the CHANGELOG).
- Remove things you delete from the playbook. A deleted task leaves its result on the server; add an explicit `state: absent` first, or reinstall.
- Passwords of existing Mosquitto logins: it adds missing logins only (salted hashes can't be compared). To change one, edit the vault and run with `-e reset_mqtt_passwords=true`.
- Probe: the database password only takes effect when the database is first created; the app logins only when you run with `-e probe=on`.

## Test it without risk

The playbook was run against a fresh `ubuntu:24.04` container with systemd (swap is skipped in containers): second run `changed=0`, `--check` shows nothing, and a manual change to `sshd` is reported. Do the same before a big change; a throwaway VPS from any hourly provider works too.
