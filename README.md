# screen-monitor

Screen monitoring system for Ubuntu 24.04+ X11 desktops. Captures screenshots at regular intervals when the screen content has changed, for workflow analysis.

```bash
git clone https://github.com/OkusiAssociates/screen-monitor.git && cd screen-monitor && sudo make deps && sudo make install && sudo make enable
```

## How It Works

- Runs as a root-level systemd service
- Discovers the active X11 session dynamically via `loginctl`
- Captures the full virtual screen (all monitors) using ImageMagick `import`
- Compares MD5 hashes to skip duplicate frames — only stores when pixels change
- Records mouse position and active window name with each capture
- Stores metadata in SQLite (WAL mode)
- Daily cleanup timer removes old screenshots and manages disk usage

## Requirements

All tools are standard on Ubuntu 24.04+ desktop installations:

- ImageMagick (`import`, `convert`)
- xdotool
- SQLite3
- systemd

## Installation

```bash
sudo make deps      # Verify dependencies
sudo make install   # Install scripts, config, systemd units
sudo make enable    # Enable and start service and cleanup timer
```

## Configuration

Edit `/etc/screen-monitor.conf`:

| Setting | Default | Description |
|---------|---------|-------------|
| `CAPTURE_INTERVAL` | `10` | Seconds between capture attempts |
| `SCREENSHOT_DIR` | `/var/lib/screen-monitor/screenshots` | Screenshot storage path |
| `DB_PATH` | `/var/lib/screen-monitor/screen-monitor.db` | SQLite database path |
| `CAPTURE_FORMAT` | `webp` | Storage format: `png`, `jpg`, `webp` |
| `CAPTURE_QUALITY` | `80` | Compression quality 1-100 (ignored for png) |
| `HASH_EXCLUDE_TOP` | `30` | Pixels to exclude from top for change detection (0=disabled) |
| `MAX_AGE_DAYS` | `30` | Delete screenshots older than this |
| `MAX_DISK_MB` | `5000` | Soft disk usage limit |

Restart the service after changing configuration:

```bash
sudo systemctl restart screen-monitor
```

## Storage

```
/var/lib/screen-monitor/
  screenshots/
    2026/03/16/
      20260316_073625.webp
      20260316_073635.webp
  screen-monitor.db
```

Screenshots are organized by date (`YYYY/MM/DD/`) to prevent directory bloat.

## Usage

```bash
sudo make status    # Show service status and recent captures
sudo make check     # Verify installed commands
make test           # Run syntax checks (no root needed)
sudo make disable   # Stop and disable the service
sudo make enable    # Enable and start the service
```

### Query the database

```bash
# Recent captures
sqlite3 /var/lib/screen-monitor/screen-monitor.db \
  "SELECT timestamp, filename, mouse_x, mouse_y, window_name FROM captures ORDER BY id DESC LIMIT 10;"

# Captures per day
sqlite3 /var/lib/screen-monitor/screen-monitor.db \
  "SELECT date(timestamp) as day, count(*) FROM captures GROUP BY day ORDER BY day DESC LIMIT 7;"

# Storage per day
sqlite3 /var/lib/screen-monitor/screen-monitor.db \
  "SELECT date(timestamp) as day, count(*), sum(filesize)/1024/1024 || 'MB' FROM captures GROUP BY day ORDER BY day DESC LIMIT 7;"
```

### Logs

```bash
journalctl -u screen-monitor -f          # Follow live
journalctl -u screen-monitor --since today  # Today's logs
journalctl -u screen-monitor-cleanup     # Cleanup logs
```

## Uninstall

```bash
sudo make uninstall
```

This removes scripts and systemd units. Configuration (`/etc/screen-monitor.conf`) and data (`/var/lib/screen-monitor/`) are preserved.

To remove everything:

```bash
sudo rm -f /etc/screen-monitor.conf
sudo rm -rf /var/lib/screen-monitor
```

#fin
