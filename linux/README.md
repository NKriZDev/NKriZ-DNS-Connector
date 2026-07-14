# NKriZ DNS Connector — Linux Mint (native)

Everything runs **on mint-dev only**. No Mac sync, no cross-compile, no Docker.

## One-time setup

```bash
cd ~/Dev/NKriZ-DNS-Connector/linux   # or wherever you cloned the repo
chmod +x native
./native all
```

That runs: install deps → build → install → launch.

When prompted for a password:
- **sudo** asks for your **user (`db`) password**
- if sudo fails, **su** asks for the **root password**

## Daily commands

| Command | What it does |
|---------|----------------|
| `./native build` | Rebuild after code changes |
| `./native install` | Copy new binary to `/usr/local/bin` |
| `./native run` | Start tray app (fixes DISPLAY/DBUS automatically) |
| `./native stop` | Kill running instance |
| `./native debug` | Print diagnostics — paste this if something breaks |

After editing code: `./native build && ./native install && ./native run`

## Tray icon not visible?

1. Run `./native debug` and check for `MISS` packages or `not found` libs.
2. Cinnamon: right-click panel → **Applets** → enable **Notification Area**.
3. Look for a small overflow arrow (^) on the panel — icons sometimes hide there.
4. Make sure you're not launching from plain SSH without a display. Use `./native run` (it sets `DISPLAY=:0` for you).

## DNS test

```bash
# Active connection name
nmcli -t -f NAME connection show --active

# DNS on first active connection
nmcli -f ipv4.dns connection show "$(nmcli -t -f NAME connection show --active | head -1)"
```

Expected NKriZ DNS: `178.22.122.101` and `185.51.200.1`

## Files installed

- `/usr/local/bin/nkriz-dns-connector` — binary
- `/usr/local/bin/nkriz-dns-connector-launch` — wrapper (sets DISPLAY/DBUS)
- `/usr/share/applications/nkriz-dns-connector.desktop` — app menu entry
- `/etc/xdg/autostart/nkriz-dns-connector-autostart.desktop` — login autostart

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `linker /Users/... not found` | Run `./native setup` (rewrites `.cargo/config.toml`) |
| `GTK has not been initialized` | Rebuild with latest code (`./native build`) |
| `DISPLAY is not set` | Use `./native run`, not raw `nkriz-dns-connector` from SSH |
| `sudo: incorrect password` | Use `su` when prompted, or run `./native install` from a desktop terminal |
| App exits immediately | `./native debug` then paste output |

## Old scripts (still work)

- `scripts/build-linux-native.sh` → calls `./native build`
- `scripts/install-linux-mint.sh` → standalone install from `dist/linux/`
