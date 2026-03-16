# Makefile for screen-monitor
# BCS1212-compliant install/uninstall

SHELL   := /bin/bash
PREFIX  := /usr/local
BINDIR  := $(PREFIX)/bin
CONFDIR := /etc
UNITDIR := /etc/systemd/system
DATADIR := /var/lib/screen-monitor

SCRIPTS := screen-monitor screen-monitor-cleanup
CONF    := screen-monitor.conf
UNITS   := screen-monitor.service screen-monitor-cleanup.service screen-monitor-cleanup.timer

.PHONY: all install uninstall enable disable deps status clean help

all: help

help:
	@echo "screen-monitor — Screen Monitoring System"
	@echo ""
	@echo "Targets:"
	@echo "  make deps       Verify required tools are installed"
	@echo "  make install    Install scripts, config, and systemd units"
	@echo "  make uninstall  Remove scripts and systemd units (preserves config and data)"
	@echo "  make enable     Enable and start the service and cleanup timer"
	@echo "  make disable    Stop and disable the service and cleanup timer"
	@echo "  make status     Show service status"
	@echo "  make clean      Remove build artifacts"
	@echo ""
	@echo "Typical workflow:"
	@echo "  sudo make deps && sudo make install && sudo make enable"

deps:
	@echo "Checking dependencies..."
	@command -v import   >/dev/null 2>&1 || { echo "MISSING: import (imagemagick)";  exit 1; }
	@command -v convert  >/dev/null 2>&1 || { echo "MISSING: convert (imagemagick)"; exit 1; }
	@command -v xdotool  >/dev/null 2>&1 || { echo "MISSING: xdotool";               exit 1; }
	@command -v sqlite3  >/dev/null 2>&1 || { echo "MISSING: sqlite3";               exit 1; }
	@command -v md5sum   >/dev/null 2>&1 || { echo "MISSING: md5sum (coreutils)";    exit 1; }
	@command -v loginctl >/dev/null 2>&1 || { echo "MISSING: loginctl (systemd)";    exit 1; }
	@command -v logger   >/dev/null 2>&1 || { echo "MISSING: logger (bsdutils)";     exit 1; }
	@echo "All dependencies present."

install: deps
	@echo "Installing screen-monitor..."
	install -m 0755 screen-monitor         $(BINDIR)/screen-monitor
	install -m 0755 screen-monitor-cleanup $(BINDIR)/screen-monitor-cleanup
	@# Install config only if not already present (preserve user edits)
	@if [[ ! -f $(CONFDIR)/$(CONF) ]]; then \
	  install -m 0644 $(CONF) $(CONFDIR)/$(CONF); \
	  echo "Installed config: $(CONFDIR)/$(CONF)"; \
	else \
	  install -m 0644 $(CONF) $(CONFDIR)/$(CONF).new; \
	  echo "Config exists, new version at: $(CONFDIR)/$(CONF).new"; \
	fi
	install -m 0644 screen-monitor.service         $(UNITDIR)/screen-monitor.service
	install -m 0644 screen-monitor-cleanup.service  $(UNITDIR)/screen-monitor-cleanup.service
	install -m 0644 screen-monitor-cleanup.timer    $(UNITDIR)/screen-monitor-cleanup.timer
	mkdir -p $(DATADIR)/screenshots
	systemctl daemon-reload
	@echo "Installation complete."

uninstall:
	@echo "Uninstalling screen-monitor..."
	@# Stop services first if running
	-systemctl stop screen-monitor.service 2>/dev/null
	-systemctl stop screen-monitor-cleanup.timer 2>/dev/null
	-systemctl disable screen-monitor.service 2>/dev/null
	-systemctl disable screen-monitor-cleanup.timer 2>/dev/null
	rm -f $(BINDIR)/screen-monitor
	rm -f $(BINDIR)/screen-monitor-cleanup
	rm -f $(UNITDIR)/screen-monitor.service
	rm -f $(UNITDIR)/screen-monitor-cleanup.service
	rm -f $(UNITDIR)/screen-monitor-cleanup.timer
	systemctl daemon-reload
	@echo "Uninstalled. Config ($(CONFDIR)/$(CONF)) and data ($(DATADIR)/) preserved."

enable:
	systemctl enable --now screen-monitor.service
	systemctl enable --now screen-monitor-cleanup.timer
	@echo "Service and cleanup timer enabled and started."

disable:
	systemctl stop screen-monitor.service
	systemctl stop screen-monitor-cleanup.timer
	systemctl disable screen-monitor.service
	systemctl disable screen-monitor-cleanup.timer
	@echo "Service and cleanup timer stopped and disabled."

status:
	@echo "=== screen-monitor.service ==="
	@systemctl status screen-monitor.service --no-pager 2>/dev/null || true
	@echo ""
	@echo "=== screen-monitor-cleanup.timer ==="
	@systemctl status screen-monitor-cleanup.timer --no-pager 2>/dev/null || true
	@echo ""
	@echo "=== Data directory ==="
	@du -sh $(DATADIR) 2>/dev/null || echo "No data directory yet"
	@echo ""
	@echo "=== Recent captures ==="
	@sqlite3 $(DATADIR)/screen-monitor.db \
	  "SELECT timestamp, filename, filesize, mouse_x, mouse_y FROM captures ORDER BY id DESC LIMIT 5;" \
	  2>/dev/null || echo "No database yet"

clean:
	@echo "Nothing to clean."

#fin
