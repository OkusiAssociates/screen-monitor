# screen-monitor

Screen monitoring system for Ubuntu 24.04+ X11 desktops. Captures screenshots at regular intervals when the screen content has changed, for workflow analysis. Optionally syncs captures to a remote server over HTTPS.

```bash
git clone https://github.com/OkusiAssociates/screen-monitor.git && cd screen-monitor && sudo make deps && sudo make install && sudo make enable
```

## How It Works

- Runs as a root-level systemd service
- Discovers the active X11 session dynamically via `loginctl`
- Captures the full virtual screen (all monitors) using ImageMagick `import`
- Compares MD5 hashes to skip duplicate frames -- only stores when pixels change
- Records mouse position and active window name with each capture
- Stores metadata in SQLite (WAL mode)
- Daily cleanup timer removes old screenshots and manages disk usage
- Optional sync timer pushes captures to a remote server via rclone (WebDAV)

## Requirements

All tools are standard on Ubuntu 24.04+ desktop installations:

- ImageMagick (`import`, `convert`)
- xdotool
- SQLite3
- systemd
- rclone (optional, for sync feature: `apt install rclone`)

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
| `SYNC_ENABLED` | `0` | Enable sync to remote server (0=disabled, 1=enabled) |
| `SYNC_REMOTE` | `''` | rclone remote name (e.g., `okusi-sync`) |
| `SYNC_PATH` | `''` | Remote path, typically the hostname (e.g., `myhost`) |

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

## Remote Sync (Optional)

Sync pushes screenshots and a database snapshot to a remote server over HTTPS using rclone with a WebDAV backend. Designed for machines that cannot use SSH/rsync (e.g., behind NAT with only outbound HTTPS).

```
Client machine                         Remote server
+------------------+    HTTPS/WebDAV   +---------------------------+
| screen-monitor-  | ----------------> | Apache + mod_dav_fs       |
| sync (timer)     |   rclone copy     | /var/lib/screen-monitor-  |
| rclone (WebDAV)  |   --update        | archive/<hostname>/       |
+------------------+                   +---------------------------+
```

The sync timer runs every 6 hours with up to 5 minutes of random jitter to prevent multiple machines hitting the server simultaneously. Only new or changed files are transferred.

### Server Setup (One-Time)

These steps configure an Apache WebDAV endpoint on the receiving server. The server must already have Apache 2.4 with SSL enabled.

**1. Enable Apache DAV modules:**

```bash
a2enmod dav dav_fs
```

**2. Create storage and lock directories:**

```bash
mkdir -p /var/lib/screen-monitor-archive
chown www-data:www-data /var/lib/screen-monitor-archive
mkdir -p /var/lib/apache2/dav
chown www-data:www-data /var/lib/apache2/dav
```

**3. Create authentication credentials:**

```bash
htpasswd -c /etc/apache2/.screen-monitor-htpasswd sync-user
```

**4. Add WebDAV block to the HTTPS vhost.** Add the following inside the existing `<VirtualHost *:443>` block:

```apache
# Screen Monitor Sync (WebDAV)
Alias /screen-monitor-sync /var/lib/screen-monitor-archive
<Directory /var/lib/screen-monitor-archive>
    Dav On
    AuthType Basic
    AuthName "Screen Monitor Sync"
    AuthUserFile /etc/apache2/.screen-monitor-htpasswd
    Require valid-user
    Options -Indexes
</Directory>
DavLockDB /var/lib/apache2/dav/screen-monitor-DavLock
```

**5. Test and reload:**

```bash
apache2ctl configtest && systemctl reload apache2
```

**6. Verify:** The endpoint should return 401 (auth required) on GET and 207 on authenticated PROPFIND:

```bash
curl -sk -o /dev/null -w '%{http_code}' https://yourserver/screen-monitor-sync/
# Expected: 401
```

### Client Setup

**1. Install rclone:**

```bash
sudo apt install rclone
```

**2. Create the rclone remote** (as root, since the systemd service runs as root):

```bash
sudo rclone config
```

When prompted:

| Prompt | Value |
|--------|-------|
| n/s/q | `n` (new remote) |
| name | `okusi-sync` (or any name) |
| Storage type | `webdav` |
| url | `https://yourserver/screen-monitor-sync` |
| vendor | `other` |
| user | `sync-user` (from htpasswd) |
| pass | The htpasswd password |
| bearer_token | (leave blank) |

**3. Verify connectivity:**

```bash
sudo rclone lsd okusi-sync:
```

**4. Enable sync in the configuration:**

```bash
sudo vi /etc/screen-monitor.conf
```

```
SYNC_ENABLED=1
SYNC_REMOTE='okusi-sync'
SYNC_PATH='myhost'
```

Use a unique `SYNC_PATH` per machine (typically the hostname). This becomes the top-level directory on the server.

**5. Enable the sync timer and test:**

```bash
sudo make enable                         # Enables sync timer if SYNC_ENABLED=1
sudo /usr/local/bin/screen-monitor-sync  # Manual test run
```

**6. Verify on the server:**

```bash
ls /var/lib/screen-monitor-archive/myhost/screenshots/ | head
```

Remote layout per machine:

```
/var/lib/screen-monitor-archive/
  myhost/
    screenshots/2026/03/16/20260316_125453.webp
    screen-monitor-db-backup.db
```

## Usage

```bash
sudo make status    # Show service status and recent captures
sudo make check     # Verify installed commands
make test           # Run syntax checks (no root needed)
sudo make disable   # Stop and disable the service
sudo make enable    # Enable and start the service
sudo make sync      # Run sync manually (if configured)
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
journalctl -u screen-monitor -f              # Follow live
journalctl -u screen-monitor --since today   # Today's logs
journalctl -u screen-monitor-cleanup         # Cleanup logs
journalctl -t screen-monitor-sync            # Sync logs
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
