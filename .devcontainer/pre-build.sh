#!/usr/bin/env bash

SETTINGS_URL="https://raw.githubusercontent.com/ruzickap/ansible-my_workstation/refs/heads/main/ansible/files/home/myusername/.config/Code/User/settings.json"
DEST_FILE=".vscode/settings.json"

echo "🔄 Fetching VS Code settings from ${SETTINGS_URL}..."
mkdir -p .vscode
curl -fsSL "${SETTINGS_URL}" -o "${DEST_FILE}"

SETTINGS_JSON=$(sed 's/^ *\/\/.*//' "${DEST_FILE}" | jq -c '.')

echo "🔄 Injecting settings into devcontainer.json..."

sed 's/^ *\/\/.*//' .devcontainer/devcontainer.json | jq --argjson settings "${SETTINGS_JSON}" '.customizations.vscode.settings = $settings' > .devcontainer/devcontainer.temp.json &&
  mv .devcontainer/devcontainer.temp.json .devcontainer/devcontainer.json

echo "✅ Settings injected successfully."
