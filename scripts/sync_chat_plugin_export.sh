#!/bin/bash

# Copies the APEX plug-in export of the UC AI Chat plug-in from the apex-chat repository
# into the root of this repository, next to the install scripts. Users import it in the
# APEX Builder (Shared Components > Plug-ins > Import).
#
# This repository is the source of the database side of the plug-in: the packages
# src/packages/uc_ai_chat*.pks/.pkb and the tables in src/tables/install.sql. Edit them
# here. Only the export file (and the JavaScript and CSS inside it) comes from apex-chat.
#
# Usage: bash scripts/sync_chat_plugin_export.sh [path/to/apex-chat]
# Default path: ../apex-chat

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CHAT_DIR="${1:-$ROOT_DIR/../apex-chat}"

PLUGIN_FILE="region_type_plugin_com_united_codes_uc_ai_chat.sql"

if [ ! -f "$CHAT_DIR/src/plugins/$PLUGIN_FILE" ]; then
    echo "Error: $PLUGIN_FILE not found in $CHAT_DIR/src/plugins"
    exit 1
fi

cp "$CHAT_DIR/src/plugins/$PLUGIN_FILE" "$ROOT_DIR/$PLUGIN_FILE"
echo "Copied $PLUGIN_FILE"
