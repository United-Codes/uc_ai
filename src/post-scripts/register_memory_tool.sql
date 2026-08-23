-- ============================================================================
-- Register the MEMORY function tool
-- ============================================================================
-- Idempotent (merge), so it runs on a fresh install and on every package
-- upgrade. One command-based tool matching the Anthropic memory tool contract,
-- usable as a plain function tool on every provider. The description carries
-- condensed protocol guidance, so a setup that does not use a prompt profile
-- (and therefore never gets the MEMORY PROTOCOL block) still nudges the model
-- to check memory first.

declare
  -- @dblinter ignore(g-2135): merge_tool_from_schema is a function; the tool id it
  -- returns is of no use to an installer
  l_id number;
begin
  l_id := uc_ai_tools_api.merge_tool_from_schema(
    p_tool_code     => 'MEMORY',
    p_description   => 'Persistent memory across conversations: a private virtual filesystem rooted at /memories'
      || ' where you store notes, learnings, progress and user context as plain-text files.'
      || ' Commands (pass in `command`):'
      || ' view = list a directory (2 levels deep) or show a file with line numbers, optional view_range [start_line, end_line] (end -1 = end of file);'
      || ' create = create or overwrite the file at `path` with `file_text`;'
      || ' str_replace = replace one unique occurrence of `old_str` with `new_str` (omit new_str to delete the text);'
      || ' insert = insert `insert_text` after line `insert_line` (0 = top of file);'
      || ' delete = delete a file or directory (recursive);'
      || ' rename = move `old_path` to `new_path` (destination must not exist).'
      || ' All paths are absolute and must start with /memories.'
      || ' IMPORTANT: at the start of a conversation ALWAYS view /memories before doing anything else'
      || ' and read the files relevant to the task. Record important decisions, user preferences and'
      || ' task progress as you work - assume the conversation can be interrupted at any time.'
      || ' Keep memory organized: small focused files; update or delete stale content.',
    p_function_call => 'return uc_ai_memory.execute_command(:ARGUMENTS);',
    p_json_schema   => json_object_t.parse(q'[{
      "type": "object",
      "properties": {
        "command": {
          "type": "string",
          "enum": ["view", "create", "str_replace", "insert", "delete", "rename"],
          "description": "The memory operation to run."
        },
        "path": {
          "type": "string",
          "description": "Absolute path starting with /memories. Used by view, create, str_replace, insert and delete."
        },
        "view_range": {
          "type": "array",
          "items": { "type": "integer" },
          "minItems": 2,
          "maxItems": 2,
          "description": "Optional for view on a file: [start_line, end_line], 1-indexed; end_line -1 means end of file."
        },
        "file_text": {
          "type": "string",
          "description": "For create: the full content of the file (overwrites an existing file)."
        },
        "old_str": {
          "type": "string",
          "description": "For str_replace: the exact text to replace (must appear exactly once in the file)."
        },
        "new_str": {
          "type": "string",
          "description": "For str_replace: the replacement text (omit to delete old_str)."
        },
        "insert_line": {
          "type": "integer",
          "description": "For insert: the line number to insert after (0 = beginning of the file)."
        },
        "insert_text": {
          "type": "string",
          "description": "For insert: the text to insert."
        },
        "old_path": {
          "type": "string",
          "description": "For rename: the current path."
        },
        "new_path": {
          "type": "string",
          "description": "For rename: the new path (must not exist yet)."
        }
      },
      "required": ["command"]
    }]'),
    p_tags          => apex_t_varchar2('memory')
  );
end;
/

commit;
