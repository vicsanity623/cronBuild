#!/bin/bash
# =============================================================================
# CRONBUILD — Uninstaller
# Removes cron job, lock file, logs, and installed script.
# =============================================================================

set -e

echo ""
echo "CRONBUILD — Uninstall"
echo "======================"
echo ""

# Remove cron job
echo "[1/4] Removing cron job..."
crontab -l 2>/dev/null | grep -v "cronbuild" | grep -v "autonomous.sh" | crontab - 2>/dev/null || true
echo "  Done."

# Remove installed script
echo "[2/4] Removing installed script..."
sudo rm -f /usr/local/bin/cronbuild 2>/dev/null || rm -f /usr/local/bin/cronbuild 2>/dev/null || true
echo "  Done."

# Remove logs and config
echo "[3/4] Removing logs and config..."
rm -rf "$HOME/.cronbuild" 2>/dev/null || true
echo "  Done."

# Remove lock file
echo "[4/4] Removing lock files..."
rm -f /tmp/cronbuild_*.lock 2>/dev/null || true
echo "  Done."

echo ""
echo "CRONBUILD has been removed from your system."
echo "Your project files and git history are untouched."
echo ""
