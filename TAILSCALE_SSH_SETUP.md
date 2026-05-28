# Enabling Tailscale SSH (keyless access for Helm)

With [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh) enabled, Helm (and
any standard SSH/SFTP client) connects to your machines with **no key and no
password** — Tailscale authenticates the device and the SSH server accepts it. In
Helm, pick the **Tailscale** auth method and a host needs only a nickname, address,
and username.

This is a one-time change **on your machines + tailnet**, not in the app.

## 1. Enable Tailscale SSH on each host

**Linux** — over your existing SSH session:
```bash
sudo tailscale set --ssh
# older clients: sudo tailscale up --ssh
```
Note: enabling this can drop your current SSH session as traffic reroutes — that's
expected.

**macOS** — requires the **standalone** Tailscale build (the Mac App Store build is
sandboxed and cannot run the SSH server). With the standalone build:
```bash
tailscale set --ssh
```

**NAS / appliances** — enable SSH for the node if the platform's Tailscale package
supports it; otherwise use Helm's Key or Password auth for that host.

After enabling, the host shows a green **SSH** badge in the Tailscale admin console.

## 2. Authorize SSH in your tailnet ACL

Tailscale SSH still needs an ACL rule saying who may connect as which user. In the
admin console → **Access Controls**, add an `ssh` block (example for a single-user
tailnet where all devices are owned by you):

```jsonc
"ssh": [
  {
    "action": "accept",          // "check" instead requires periodic re-auth
    "src":    ["autogroup:member"],
    "dst":    ["autogroup:self"],
    "users":  ["autogroup:nonroot", "root"]
  }
]
```

- `src` — the devices that initiate the connection (e.g. your phone).
- `dst: autogroup:self` — your own (untagged) machines.
- `users` — which local accounts you may log in as; `autogroup:nonroot` covers
  normal user accounts.

## 3. Verify from a computer (forces no key)

```bash
ssh -o IdentitiesOnly=yes -i /dev/null <user>@<host>
```
If Tailscale SSH is working, this logs in **without** offering any key.

## 4. In Helm

Add the host with **Authentication → Tailscale**: nickname, hostname (a Tailscale
`100.x` address or MagicDNS name), username, and a start directory. No key, no paste.

## Notes

- Helm accepts host keys on first use; fine for a private tailnet.
- If a host doesn't have Tailscale SSH on, Helm's **Key** / **Password** methods still work.
