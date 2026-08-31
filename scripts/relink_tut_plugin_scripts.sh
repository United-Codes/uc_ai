#!/usr/bin/env bash
# Point the supporting-object scripts of the tutorial app back at the plug-in
# repository.
#
# The chat plug-in has its own repository, so this one keeps symlinks instead of
# copies. An APEXLANG export does not write through a symlink: it writes a fresh
# copy next to it and re-points install-scripts.apx at that copy. Running this
# after every export undoes that, so no copy of the plug-in is committed here.
set -euo pipefail

app_dir="${1:-examples/sample-apps/tutorials/uc-ai-tutorials}"
scripts_dir="$app_dir/supporting-objects/install-scripts"
# From install-scripts up to the directory that holds both repositories.
plugin_rel="../../../../../../../apex-chat/src"

# name in APEX | file the export writes | file in the plug-in repository
links=(
  "ai_tables.sql|ai-tables-sql.sql|$plugin_rel/ddl/ai_tables.sql"
  "uc_ai_chat.pks|uc-ai-chat-pks.sql|$plugin_rel/plsql/uc_ai_chat.pks"
  "uc_ai_chat.pkb|uc-ai-chat-pkb.sql|$plugin_rel/plsql/uc_ai_chat.pkb"
  "uc_ai_chat_hook.pks|uc-ai-chat-hook-pks.sql|$plugin_rel/plsql/uc_ai_chat_hook.pks"
  "uc_ai_chat_hook.pkb|uc-ai-chat-hook-pkb.sql|$plugin_rel/plsql/uc_ai_chat_hook.pkb"
)

for entry in "${links[@]}"; do
  IFS='|' read -r link exported target <<< "$entry"
  rm -f "$scripts_dir/$exported"
  ln -sfn "$target" "$scripts_dir/$link"
  # The export names the file after the script; point it back at the link.
  perl -0pi -e "s{contentFile: \Q$exported\E\n}{contentFile: $link\n}" \
    "$app_dir/supporting-objects/install-scripts.apx"
done

echo "Supporting-object scripts re-linked to $plugin_rel"
