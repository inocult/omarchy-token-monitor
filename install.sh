#!/bin/bash
# Install omarchy-token-monitor into the current user's Omarchy.
#
# Copies rather than symlinks: the plugin scanner rejects symlinks anywhere
# inside a plugin directory, so a linked checkout would simply never load.
set -euo pipefail

PLUGIN_ID="inocult.token-monitor"
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

command -v omarchy >/dev/null || { echo "install.sh: this needs Omarchy" >&2; exit 1; }

install -d "$HOME/.config/omarchy/plugins/$PLUGIN_ID" "$HOME/.local/bin" "$HOME/.config/systemd/user"
cp -r "$here/plugin/." "$HOME/.config/omarchy/plugins/$PLUGIN_ID/"
install -m 755 "$here"/bin/* "$HOME/.local/bin/"
cp "$here"/systemd/* "$HOME/.config/systemd/user/"

omarchy plugin validate "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy plugin enable "$PLUGIN_ID" right || true

# Priced immediately, so the panel has something to show on first open.
"$HOME/.local/bin/token-cost" || true

echo
echo "Installed. The bar icon is on the right."
echo "Fleet view: add your machines to the EDIT HERE block in ~/.local/bin/agents-pull, then"
echo "  systemctl --user enable --now agents-pull.timer"
