# Makefile for screen-monitor
# BCS1212-compliant install/uninstall

SHELL   := /bin/bash
PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
MANDIR  ?= $(PREFIX)/share/man
COMPDIR ?= $(PREFIX)/share/bash-completion/completions
DESTDIR ?=
CONFDIR := /etc
UNITDIR := /etc/systemd/system
DATADIR := /var/lib/screen-monitor

SCRIPTS := screen-monitor screen-monitor-cleanup screen-monitor-sync
CONF    := screen-monitor.conf
UNITS   := screen-monitor.service screen-monitor-cleanup.service screen-monitor-cleanup.timer \
           screen-monitor-sync.service screen-monitor-sync.timer

.PHONY: all install uninstall check test enable disable deps status clean help sync

all: help

help:
	@echo "screen-monitor — Screen Monitoring System"
	@echo ""
	@echo "Targets:"
	@echo "  make deps       Verify build dependencies"
	@echo "  make install    Install scripts, config, and systemd units"
	@echo "  make uninstall  Remove scripts and systemd units (preserves config and data)"
	@echo "  make check      Verify installed commands"
	@echo "  make test       Run syntax checks"
	@echo "  make enable     Enable and start the service and cleanup timer"
	@echo "                  (also enables sync timer if SYNC_ENABLED=1)"
	@echo "  make disable    Stop and disable the service and cleanup timer"
	@echo "  make status     Show service status"
	@echo "  make sync       Run sync manually (if configured)"
	@echo ""
	@echo "Typical workflow:"
	@echo "  sudo make deps && sudo make install && sudo make enable"

deps:
	@pkgs=''; \
	command -v import   >/dev/null 2>&1 || pkgs="$$pkgs imagemagick"; \
	command -v xdotool  >/dev/null 2>&1 || pkgs="$$pkgs xdotool"; \
	command -v sqlite3  >/dev/null 2>&1 || pkgs="$$pkgs sqlite3"; \
	command -v md5sum   >/dev/null 2>&1 || pkgs="$$pkgs coreutils"; \
	command -v loginctl >/dev/null 2>&1 || pkgs="$$pkgs systemd"; \
	command -v logger   >/dev/null 2>&1 || pkgs="$$pkgs bsdutils"; \
	if [[ -n "$$pkgs" ]]; then \
	  echo "Installing:$$pkgs"; \
	  apt-get install -y $$pkgs; \
	fi
	@command -v rclone >/dev/null 2>&1 || echo "NOTE: rclone not installed (optional, for sync: apt install rclone)"

install: deps
	install -m 0755 screen-monitor         $(DESTDIR)$(BINDIR)/screen-monitor
	install -m 0755 screen-monitor-cleanup $(DESTDIR)$(BINDIR)/screen-monitor-cleanup
	install -m 0755 screen-monitor-sync    $(DESTDIR)$(BINDIR)/screen-monitor-sync
	@if [[ ! -f $(DESTDIR)$(CONFDIR)/$(CONF) ]]; then \
	  install -m 0644 $(CONF) $(DESTDIR)$(CONFDIR)/$(CONF); \
	else \
	  install -m 0644 $(CONF) $(DESTDIR)$(CONFDIR)/$(CONF).new; \
	fi
	install -m 0644 screen-monitor.service         $(DESTDIR)$(UNITDIR)/screen-monitor.service
	install -m 0644 screen-monitor-cleanup.service  $(DESTDIR)$(UNITDIR)/screen-monitor-cleanup.service
	install -m 0644 screen-monitor-cleanup.timer    $(DESTDIR)$(UNITDIR)/screen-monitor-cleanup.timer
	install -m 0644 screen-monitor-sync.service     $(DESTDIR)$(UNITDIR)/screen-monitor-sync.service
	install -m 0644 screen-monitor-sync.timer       $(DESTDIR)$(UNITDIR)/screen-monitor-sync.timer
	install -d $(DESTDIR)$(DATADIR)/screenshots
	@[[ -n "$(DESTDIR)" ]] || systemctl daemon-reload

uninstall:
	@if [[ -z "$(DESTDIR)" ]]; then \
	  systemctl stop screen-monitor.service 2>/dev/null; \
	  systemctl stop screen-monitor-cleanup.timer 2>/dev/null; \
	  systemctl stop screen-monitor-sync.timer 2>/dev/null; \
	  systemctl disable screen-monitor.service 2>/dev/null; \
	  systemctl disable screen-monitor-cleanup.timer 2>/dev/null; \
	  systemctl disable screen-monitor-sync.timer 2>/dev/null; \
	fi; true
	rm -f $(DESTDIR)$(BINDIR)/screen-monitor
	rm -f $(DESTDIR)$(BINDIR)/screen-monitor-cleanup
	rm -f $(DESTDIR)$(BINDIR)/screen-monitor-sync
	rm -f $(DESTDIR)$(UNITDIR)/screen-monitor.service
	rm -f $(DESTDIR)$(UNITDIR)/screen-monitor-cleanup.service
	rm -f $(DESTDIR)$(UNITDIR)/screen-monitor-cleanup.timer
	rm -f $(DESTDIR)$(UNITDIR)/screen-monitor-sync.service
	rm -f $(DESTDIR)$(UNITDIR)/screen-monitor-sync.timer
	@[[ -n "$(DESTDIR)" ]] || systemctl daemon-reload

check:
	@[[ -n "$(DESTDIR)" ]] && exit 0 || true
	@command -v screen-monitor         >/dev/null 2>&1 || { echo "NOT INSTALLED: screen-monitor";         exit 1; }
	@command -v screen-monitor-cleanup >/dev/null 2>&1 || { echo "NOT INSTALLED: screen-monitor-cleanup"; exit 1; }
	@[[ -f $(CONFDIR)/$(CONF) ]]                       || { echo "NOT INSTALLED: $(CONFDIR)/$(CONF)";     exit 1; }
	@[[ -f $(UNITDIR)/screen-monitor.service ]]         || { echo "NOT INSTALLED: screen-monitor.service"; exit 1; }

test:
	bash -n screen-monitor
	bash -n screen-monitor-cleanup
	bash -n screen-monitor-sync

enable:
	systemctl enable --now screen-monitor.service
	systemctl enable --now screen-monitor-cleanup.timer
	@if grep -q '^SYNC_ENABLED=1' $(CONFDIR)/$(CONF) 2>/dev/null; then \
	  systemctl enable --now screen-monitor-sync.timer; \
	  echo "Sync timer enabled (every 6 hours)"; \
	fi

disable:
	systemctl stop screen-monitor.service
	systemctl stop screen-monitor-cleanup.timer
	systemctl disable screen-monitor.service
	systemctl disable screen-monitor-cleanup.timer
	@systemctl stop screen-monitor-sync.timer 2>/dev/null || true
	@systemctl disable screen-monitor-sync.timer 2>/dev/null || true

status:
	@systemctl status screen-monitor.service --no-pager 2>/dev/null || true
	@echo ""
	@systemctl status screen-monitor-cleanup.timer --no-pager 2>/dev/null || true
	@echo ""
	@systemctl status screen-monitor-sync.timer --no-pager 2>/dev/null || echo "Sync: not enabled"
	@echo ""
	@du -sh $(DATADIR) 2>/dev/null || echo "No data directory yet"
	@echo ""
	@sqlite3 $(DATADIR)/screen-monitor.db \
	  "SELECT timestamp, filename, filesize, mouse_x, mouse_y FROM captures ORDER BY id DESC LIMIT 5;" \
	  2>/dev/null || echo "No database yet"

sync:
	/usr/local/bin/screen-monitor-sync

clean:
	@true

#fin
