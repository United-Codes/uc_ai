create or replace package body uc_ai_memory as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  -- Anthropic contract: text views longer than this are truncated (the model
  -- follows up with view_range)
  c_view_max_chars constant pls_integer := 16000;
  -- Files beyond this many lines refuse line-based edits (contract limit)
  c_max_edit_lines constant pls_integer := 999999;
  -- str_replace stops counting occurrences here (only "0, 1 or many" matters)
  c_max_occurrences constant pls_integer := 25;

  -- Session-level store override for standalone (non-agent) usage
  -- @dblinter ignore(g-7230): session override is deliberately session state
  g_store_override varchar2(255 char);

  -- Effective size caps of the resolved store
  type t_caps is record (
    max_file_chars  number,
    max_store_chars number,
    max_files       number
  );

  -- Line container (clob elements: a single line may exceed 32k)
  type t_lines is table of clob;

  subtype path_type is varchar2(1000 char);


  -- ==========================================================================
  -- Small helpers
  -- ==========================================================================

  function current_user_id return varchar2
  as
  begin
    return coalesce(sys_context('APEX$SESSION', 'app_user'), sys_context('userenv', 'session_user'));
  end current_user_id;


  /*
   * du-style human-readable size from a char count: plain below 1K, else one
   * decimal with K/M suffix (e.g. 812, 5.5K, 1.2M).
   */
  function format_size(p_chars in number) return varchar2
  as
    l_chars number := nvl(p_chars, 0);
  begin
    if l_chars < 1024 then
      return trim(to_char(l_chars, 'fm999999990'));
    elsif l_chars < 1048576 then
      return trim(to_char(round(l_chars / 1024, 1), 'fm999990.0')) || 'K';
    else
      return trim(to_char(round(l_chars / 1048576, 1), 'fm999990.0')) || 'M';
    end if;
  end format_size;


  /*
   * Normalizes and validates a virtual path. Returns the normalized path or
   * NULL when the path is invalid (callers emit the instructive error string).
   *
   * Rules: non-null; no '..' anywhere (covers ../ and ..\), no backslashes, no
   * URL-encoded traversal (%2e/%2f/%5c), no control characters; duplicate
   * slashes collapsed; trailing slash stripped (except the root itself); must
   * then be exactly /memories or start with /memories/; max 1000 chars.
   */
  function normalize_path(p_path in varchar2) return varchar2
  as
    l_path varchar2(4000 char);
  begin
    if p_path is null or length(p_path) > 1000 then
      return null;
    end if;

    if instr(p_path, '..') > 0
      or instr(p_path, '\') > 0
      or instr(lower(p_path), '%2e') > 0
      or instr(lower(p_path), '%2f') > 0
      or instr(lower(p_path), '%5c') > 0
      or regexp_like(p_path, '[[:cntrl:]]')
    then
      return null;
    end if;

    -- collapse duplicate slashes, strip a trailing slash (but keep the root)
    l_path := regexp_replace(p_path, '/{2,}', '/');
    if l_path != c_root and substr(l_path, -1) = '/' then
      l_path := rtrim(l_path, '/');
    end if;

    if l_path = c_root or l_path like c_root || '/%' then
      return l_path;
    end if;

    return null;
  end normalize_path;


  function invalid_path_msg(p_path in varchar2) return varchar2
  as
  begin
    return 'Error: Invalid path `' || p_path || '`. Paths must be absolute, start with '
      || c_root || ' and must not contain `..` or backslashes.';
  end invalid_path_msg;


  function not_found_msg(p_path in varchar2) return varchar2
  as
  begin
    return 'The path ' || p_path || ' does not exist. Please provide a valid path.';
  end not_found_msg;


  function param_required_msg(
    p_param   in varchar2,
    p_command in varchar2
  ) return varchar2
  as
  begin
    return 'Error: parameter `' || p_param || '` is required for command `' || p_command || '`.';
  end param_required_msg;


  /*
   * Splits content into lines on chr(10). A trailing newline does not produce
   * a trailing empty line (chomp semantics, matching the Anthropic reference
   * implementations). Empty/null content is one empty line.
   */
  function split_lines(p_content in clob) return t_lines
  as
    l_lines_arr t_lines := t_lines();
    l_start     pls_integer := 1;
    l_pos       pls_integer;
    l_len       pls_integer := nvl(length(p_content), 0);
  begin
    if l_len = 0 then
      l_lines_arr.extend;
      return l_lines_arr;
    end if;

    <<line_loop>>
    loop
      l_pos := instr(p_content, chr(10), l_start);
      l_lines_arr.extend;
      if l_pos = 0 then
        l_lines_arr(l_lines_arr.count) := substr(p_content, l_start);
        exit line_loop;
      end if;
      l_lines_arr(l_lines_arr.count) := substr(p_content, l_start, l_pos - l_start);
      l_start := l_pos + 1;
      -- content ends with a newline: no trailing empty line
      exit line_loop when l_start > l_len;
    end loop line_loop;

    return l_lines_arr;
  end split_lines;


  function join_lines(p_lines in t_lines) return clob
  as
    l_out clob;
  begin
    <<join_loop>>
    for i in 1 .. p_lines.count loop
      if i > 1 then
        l_out := l_out || chr(10);
      end if;
      l_out := l_out || p_lines(i);
    end loop join_loop;
    return l_out;
  end join_lines;


  /*
   * 1-based line number of a character position in content.
   */
  function line_of_position(
    p_content  in clob,
    p_position in pls_integer
  ) return pls_integer
  as
    l_line  pls_integer := 1;
    l_start pls_integer := 1;
    l_pos   pls_integer;
  begin
    <<count_loop>>
    loop
      l_pos := instr(p_content, chr(10), l_start);
      exit count_loop when l_pos = 0 or l_pos >= p_position;
      l_line  := l_line + 1;
      l_start := l_pos + 1;
    end loop count_loop;
    return l_line;
  end line_of_position;


  /*
   * Renders lines p_from..p_to with Anthropic line-number formatting (6-char
   * right-aligned, TAB separator, 1-indexed), truncating past c_view_max_chars.
   */
  function render_numbered(
    p_lines in t_lines,
    p_from  in pls_integer,
    p_to    in pls_integer
  ) return clob
  as
    l_out clob;
  begin
    <<render_loop>>
    for i in p_from .. p_to loop
      if i > p_from then
        l_out := l_out || chr(10);
      end if;
      l_out := l_out || lpad(to_char(i), 6) || chr(9) || p_lines(i);

      if length(l_out) > c_view_max_chars then
        l_out := l_out || chr(10) || '... (output truncated after line ' || i
          || ' of ' || p_lines.count || ' - use the view_range parameter to see more)';
        return l_out;
      end if;
    end loop render_loop;
    return l_out;
  end render_numbered;


  -- ==========================================================================
  -- Store resolution
  -- ==========================================================================

  /*
   * Escapes the LIKE wildcards in a literal so it matches only itself.
   * Used where an agent code becomes part of a LIKE pattern.
   */
  function like_literal(p_value in varchar2) return varchar2
  as
  begin
    return replace(replace(replace(p_value, '\', '\\'), '%', '\%'), '_', '\_');
  end like_literal;


  /*
   * The store key of a context-scoped store.
   *
   * The namespace segment defaults to the agent code, so a context store stays
   * private to its agent exactly like an 'agent' store. Naming a store_code
   * instead lets several agents share one memory per context value, e.g. a
   * DOC_CHAT and a DOC_SUMMARY agent both working on document 7.
   */
  function context_store_key(
    p_namespace     in varchar2,
    p_context_key   in varchar2,
    p_context_value in varchar2
  ) return varchar2
  as
  begin
    return 'context:' || p_namespace || ':' || p_context_key || ':' || p_context_value;
  end context_store_key;


  /*
   * Is a run-context value usable as a store-key segment?
   *
   * The key is built by concatenation, so a value carrying ':' could address a
   * store belonging to another namespace or another key. Only an unambiguous
   * identifier is accepted; anything else is rejected rather than escaped.
   */
  function valid_context_value(p_value in varchar2) return boolean
  as
  begin
    return p_value is not null
       and length(p_value) <= 200
       and regexp_like(p_value, '^[A-Za-z0-9_.-]+$');
  end valid_context_value;


  /*
   * Finds or auto-provisions the store row for a canonical store key.
   *
   * AUTONOMOUS by design: a store row is pure addressing metadata, and
   * committing it immediately keeps a second session from blocking on the
   * unique index for the whole duration of a long uncommitted agent run. A
   * lost provisioning race is absorbed by the dup_val handler.
   */
  function get_or_create_store(
    p_store_key     in varchar2,
    p_scope         in varchar2,
    p_agent_code    in varchar2 default null,
    p_username      in varchar2 default null,
    p_session_id    in varchar2 default null,
    p_store_code    in varchar2 default null,
    p_context_key   in varchar2 default null,
    p_context_value in varchar2 default null
  ) return number
  as
    -- @dblinter ignore(g-3330): deliberate, see above - the store row is addressing
    -- metadata that other sessions must see before the caller's run commits
    pragma autonomous_transaction;
    l_id number;
  begin
    begin
      select id
        into l_id
        from uc_ai_memory_stores
       where store_key = p_store_key;
      rollback;
      return l_id;
    exception
      when no_data_found then
        null;
    end;

    begin
      insert into uc_ai_memory_stores (store_key, scope, agent_code, username, session_id, store_code,
                                       context_key, context_value)
      values (p_store_key, p_scope, p_agent_code, p_username, p_session_id, p_store_code,
              p_context_key, p_context_value)
      returning id into l_id;
      commit;
    exception
      when dup_val_on_index then
        rollback;
        select id
          into l_id
          from uc_ai_memory_stores
         where store_key = p_store_key;
    end;

    return l_id;
  end get_or_create_store;


  /*
   * Resolves which store (virtual filesystem) the current caller sees:
   *   1. the set_store session override (standalone usage) -> shared store
   *   2. the ambient execution context -> the agent's uc_ai_memory_config
   *   3. neither -> instructive error string in po_error
   */
  procedure resolve_store(
    po_store_id out number,
    po_caps     out nocopy t_caps,
    po_error    out nocopy varchar2
  )
  as
    l_ctx     uc_ai.t_exec_context;
    l_cfg     uc_ai_memory_config%rowtype;
    l_key     uc_ai_memory_stores.store_key%type;
    l_ctx_val varchar2(4000 char);
  begin
    po_caps.max_file_chars := c_default_max_file_chars;
    po_caps.max_files      := c_default_max_files;

    if g_store_override is not null then
      po_store_id := get_or_create_store(
        p_store_key  => 'shared:' || g_store_override,
        p_scope      => c_scope_shared,
        p_store_code => g_store_override
      );
      return;
    end if;

    l_ctx := uc_ai.get_exec_context;
    if l_ctx.agent_code is null then
      po_error := 'Error: the memory tool is not available here - no agent context and no store'
        || ' override. Run inside a memory-enabled agent or call uc_ai_memory.set_store first.';
      return;
    end if;

    begin
      select *
        into l_cfg
        from uc_ai_memory_config
       where agent_code = l_ctx.agent_code;
    exception
      when no_data_found then
        po_error := 'Error: memory is not enabled for agent ' || l_ctx.agent_code
          || '. Enable it with uc_ai_memory.enable_for_agent.';
        return;
    end;

    if l_cfg.enabled != 'Y' then
      po_error := 'Error: memory is disabled for agent ' || l_ctx.agent_code || '.';
      return;
    end if;

    po_caps.max_file_chars  := l_cfg.max_file_chars;
    po_caps.max_store_chars := l_cfg.max_store_chars;
    po_caps.max_files       := l_cfg.max_files;

    case l_cfg.scope
      when c_scope_agent then
        l_key := 'agent:' || l_ctx.agent_code;
      when c_scope_user then
        l_key := 'user:' || l_ctx.agent_code || ':'
          || coalesce(l_ctx.created_by, sys_context('userenv', 'session_user'));
      when c_scope_session then
        if l_ctx.session_id is null then
          po_error := 'Error: session-scoped memory requires an execution session.';
          return;
        end if;
        l_key := 'session:' || l_ctx.session_id;
      when c_scope_shared then
        l_key := 'shared:' || l_cfg.store_code;
      when c_scope_global then
        l_key := 'global';
      when c_scope_context then
        l_ctx_val := uc_ai.run_context_value(l_ctx.run_context, l_cfg.context_key);
        if l_ctx_val is null then
          po_error := 'Error: the memory of agent ' || l_ctx.agent_code
            || ' is scoped to the run-context key "' || l_cfg.context_key
            || '", which this run did not supply. Start the run with that key in p_run_context.';
          return;
        end if;
        if not valid_context_value(l_ctx_val) then
          po_error := 'Error: the run-context value of "' || l_cfg.context_key
            || '" cannot identify a memory store. Use at most 200 characters from'
            || ' A-Z, a-z, 0-9, underscore, dot and hyphen.';
          return;
        end if;
        l_key := context_store_key(
                   p_namespace     => coalesce(l_cfg.store_code, l_ctx.agent_code)
                 , p_context_key   => l_cfg.context_key
                 , p_context_value => l_ctx_val
                 );
    end case;

    po_store_id := get_or_create_store(
      p_store_key     => l_key,
      p_scope         => l_cfg.scope,
      p_agent_code    => case when l_cfg.scope in (c_scope_agent, c_scope_user, c_scope_context) then l_ctx.agent_code end,
      p_username      => case when l_cfg.scope = c_scope_user then coalesce(l_ctx.created_by, sys_context('userenv', 'session_user')) end,
      p_session_id    => case when l_cfg.scope = c_scope_session then l_ctx.session_id end,
      p_store_code    => l_cfg.store_code,
      p_context_key   => case when l_cfg.scope = c_scope_context then l_cfg.context_key end,
      p_context_value => case when l_cfg.scope = c_scope_context then l_ctx_val end
    );
  end resolve_store;


  /*
   * Best-effort last_accessed_at touch on view.
   *
   * AUTONOMOUS + skip locked by design: a read must not acquire row locks
   * inside the caller's transaction (two parallel runs viewing the same file
   * would serialize until commit), and an autonomous update must never block
   * on a row the parent transaction itself has locked. A skipped touch only
   * delays expire_files, which also considers updated_at.
   */
  procedure touch_access(p_file_id in number)
  as
    -- @dblinter ignore(g-3330): deliberate, see above - a read must not take row
    -- locks in the caller's transaction, nor block on the parent's own locks
    pragma autonomous_transaction;
  begin
    <<touch_loop>>
    for r in (
      select id
        from uc_ai_memory_files
       where id = p_file_id
         for update skip locked
    ) loop
      -- @dblinter ignore(g-3210): the loop touches at most one row (the file just
      -- viewed); a set update could not skip a row another session holds locked
      update uc_ai_memory_files
         set last_accessed_at = systimestamp
       where id = r.id;
    end loop touch_loop;
    commit;
  exception
    -- @dblinter ignore(g-5040): best-effort touch must never disturb a view
    when others then
      rollback;
  end touch_access;


  -- ==========================================================================
  -- Commands
  -- ==========================================================================

  /*
   * Reads the `view_range` argument of a file view.
   *
   * Presence says nothing about intent: a provider in strict mode (OpenAI)
   * sends every property that the tool schema declares, so the argument arrives
   * on every call with a value the model invented. An absent argument, a JSON
   * null and an empty array therefore all mean "no range".
   *
   * po_range    the array when the argument holds one with entries, else null.
   *             The caller validates the contents and reports a bad range.
   * po_explicit true when the argument holds something that is not a usable
   *             array, so the caller reports the expected shape instead of
   *             silently showing the whole file.
   */
  procedure read_view_range(
    p_arguments in  json_object_t,
    po_range    out nocopy json_array_t,
    po_explicit out boolean
  )
  as
    l_el  json_element_t;
    l_arr json_array_t;
  begin
    po_range    := null;
    po_explicit := false;

    if p_arguments is null or not p_arguments.has('view_range') then
      return;
    end if;

    l_el := p_arguments.get('view_range');
    if l_el is null or l_el.is_null then
      return;
    end if;

    if l_el.is_array then
      l_arr := treat(l_el as json_array_t);
      if l_arr.get_size = 0 then
        return;
      end if;
      po_range := l_arr;
      return;
    end if;

    -- Present but not an array at all. Hand it to the caller, which reports the
    -- expected shape, and treat it as a real request.
    po_explicit := true;
  end read_view_range;


  function cmd_view(
    p_store_id  in number,
    p_arguments in json_object_t
  ) return clob
  as
    l_path       path_type;
    l_norm       path_type;
    l_file_id    number;
    l_content    clob;
    l_lines_arr  t_lines;
    l_from       pls_integer;
    l_to         pls_integer;
    l_range      json_array_t;
    l_has_range  boolean;
    l_out        clob;
    l_total      number := 0;
    l_rem        varchar2(1000 char);
    l_seg        varchar2(1000 char);
    l_rem2       varchar2(1000 char);
    l_entry      path_type;
    l_found_rows boolean := false;
    type t_size_map is table of number index by path_type;
    l_sizes_map  t_size_map;

    -- @dblinter ignore(g-7130): add_size aggregates into the l_sizes_map of its
    -- enclosing command; passing the map in and out would copy the collection
    -- twice for every row
    procedure add_size(p_entry in path_type, p_chars in number)
    as
    begin
      if l_sizes_map.exists(p_entry) then
        l_sizes_map(p_entry) := l_sizes_map(p_entry) + p_chars;
      else
        l_sizes_map(p_entry) := p_chars;
      end if;
    end add_size;
  begin
    l_path := p_arguments.get_string('path');
    if l_path is null then
      return param_required_msg('path', 'view');
    end if;

    l_norm := normalize_path(l_path);
    if l_norm is null then
      return invalid_path_msg(l_path);
    end if;

    -- exact file?
    begin
      select id, content
        into l_file_id, l_content
        from uc_ai_memory_files
       where store_id = p_store_id
         and path = l_norm;
    exception
      when no_data_found then
        l_file_id := null;
    end;

    if l_file_id is not null then
      l_lines_arr := split_lines(l_content);
      l_from  := 1;
      l_to    := l_lines_arr.count;

      read_view_range(p_arguments, l_range, l_has_range);
      if l_range is not null or l_has_range then
        if l_range is null or l_range.get_size != 2 then
          return 'Error: Invalid `view_range` parameter: it must be an array of two integers [start_line, end_line].';
        end if;
        l_from := l_range.get_number(0);
        l_to   := l_range.get_number(1);
        if l_to = -1 then
          l_to := l_lines_arr.count;
        end if;
        if l_from is null or l_to is null
          or l_from < 1 or l_from > l_lines_arr.count
          or l_to < l_from or l_to > l_lines_arr.count
        then
          return 'Error: Invalid `view_range` parameter: [' || l_range.get_number(0) || ', '
            || l_range.get_number(1) || ']. Lines must be within [1, ' || l_lines_arr.count || '].';
        end if;
      end if;

      touch_access(l_file_id);

      return 'Here''s the content of ' || l_norm || ' with line numbers:' || chr(10)
        || render_numbered(l_lines_arr, l_from, l_to);
    end if;

    -- directory? (implicit from path prefixes; the root is always a directory)
    <<entry_loop>>
    for r in (
      select path, sys.dbms_lob.getlength(content) as char_count
        from uc_ai_memory_files
       where store_id = p_store_id
         and path like l_norm || '/%'
       order by path
    ) loop
      l_found_rows := true;
      l_total := l_total + r.char_count;

      l_rem := substr(r.path, length(l_norm) + 2);
      if instr(l_rem, '/') = 0 then
        -- direct file child
        add_size(l_norm || '/' || l_rem, r.char_count);
      else
        -- first-level directory (aggregate)
        l_seg := substr(l_rem, 1, instr(l_rem, '/') - 1);
        add_size(l_norm || '/' || l_seg, r.char_count);

        -- second-level entry (file or aggregated sub-directory)
        l_rem2 := substr(l_rem, instr(l_rem, '/') + 1);
        if instr(l_rem2, '/') > 0 then
          l_rem2 := substr(l_rem2, 1, instr(l_rem2, '/') - 1);
        end if;
        add_size(l_norm || '/' || l_seg || '/' || l_rem2, r.char_count);
      end if;
    end loop entry_loop;

    if not l_found_rows and l_norm != c_root then
      return not_found_msg(l_norm);
    end if;

    -- view_range is ignored for a directory, whatever it holds.
    --
    -- A listing has no lines, so no range can be a meaningful request against
    -- one, and there is nothing a caller could pass that we should honour or
    -- refuse. A provider in strict mode sends the argument on every call and
    -- invents a value for it - [1,200], [0,0], [-1,-1] and [-1,0] have all been
    -- observed from one model in one run - so refusing "a range that looks
    -- deliberate" only makes the listing succeed or fail by luck. Ignoring it
    -- removes the whole class.

    l_out := 'Here''re the files and directories up to 2 levels deep in ' || l_norm || ':'
      || chr(10) || format_size(l_total) || chr(9) || l_norm;

    l_entry := l_sizes_map.first;
    <<listing_loop>>
    while l_entry is not null loop
      l_out   := l_out || chr(10) || format_size(l_sizes_map(l_entry)) || chr(9) || l_entry;
      l_entry := l_sizes_map.next(l_entry);
    end loop listing_loop;

    return l_out;
  end cmd_view;


  /*
   * Enforces the resolved store's size caps for a pending write. Returns null
   * when the write is allowed, else the instructive error string.
   * p_old_chars = current length of the file being replaced (0 for a new file),
   * p_is_new = whether the write adds a file.
   */
  function check_caps(
    p_store_id  in number,
    p_caps      in t_caps,
    p_new_chars in number,
    p_old_chars in number,
    p_is_new    in boolean
  ) return varchar2
  as
    l_files number;
    l_chars number;
  begin
    if p_caps.max_file_chars is not null and p_new_chars > p_caps.max_file_chars then
      return 'Error: file too large (' || p_new_chars || ' chars, cap is '
        || p_caps.max_file_chars || '). Split the content into smaller files or delete stale content.';
    end if;

    if p_is_new and p_caps.max_files is not null then
      select count(*) into l_files from uc_ai_memory_files where store_id = p_store_id;
      if l_files >= p_caps.max_files then
        return 'Error: the memory store already holds ' || l_files
          || ' files (cap is ' || p_caps.max_files || '). Delete or consolidate files first.';
      end if;
    end if;

    if p_caps.max_store_chars is not null then
      select nvl(sum(sys.dbms_lob.getlength(content)), 0)
        into l_chars
        from uc_ai_memory_files
       where store_id = p_store_id;
      if l_chars - nvl(p_old_chars, 0) + p_new_chars > p_caps.max_store_chars then
        return 'Error: the memory store would exceed its total size cap of '
          || p_caps.max_store_chars || ' chars. Delete or consolidate files first.';
      end if;
    end if;

    return null;
  end check_caps;


  /*
   * Locks the file row for a mutation and returns id + content.
   * Returns false when the file does not exist.
   */
  -- @dblinter ignore(g-7440): the return value answers "does the file exist"; the
  -- row it locked comes back in po_id/po_content, which keeps a mutation to one
  -- round trip
  function lock_file(
    p_store_id in number,
    p_path     in varchar2,
    po_id      out number,
    po_content out nocopy clob
  ) return boolean
  as
  begin
    select id, content
      into po_id, po_content
      from uc_ai_memory_files
     where store_id = p_store_id
       and path = p_path
       for update;
    return true;
  exception
    when no_data_found then
      return false;
  end lock_file;


  procedure update_file_content(
    p_file_id in number,
    p_content in clob
  )
  as
    l_user varchar2(255 char) := current_user_id();
  begin
    update uc_ai_memory_files
       set content          = coalesce(p_content, empty_clob()),
           last_accessed_at = systimestamp,
           updated_by       = l_user,
           updated_at       = systimestamp
     where id = p_file_id;
  end update_file_content;


  function cmd_create(
    p_store_id  in number,
    p_caps      in t_caps,
    p_arguments in json_object_t
  ) return clob
  as
    l_path    path_type;
    l_norm    path_type;
    l_text    clob;
    l_file_id number;
    l_old     clob;
    l_err     varchar2(4000 char);
  begin
    l_path := p_arguments.get_string('path');
    if l_path is null then
      return param_required_msg('path', 'create');
    end if;
    if not p_arguments.has('file_text') then
      return param_required_msg('file_text', 'create');
    end if;

    l_norm := normalize_path(l_path);
    if l_norm is null then
      return invalid_path_msg(l_path);
    end if;
    if l_norm = c_root then
      return 'Error: ' || c_root || ' is a directory, not a file.';
    end if;

    -- empty JSON strings arrive as null; an empty file is still a valid file
    l_text := coalesce(p_arguments.get_clob('file_text'), empty_clob());

    -- create overwrites per the tool contract
    if lock_file(p_store_id, l_norm, l_file_id, l_old) then
      l_err := check_caps(p_store_id, p_caps, nvl(length(l_text), 0), nvl(length(l_old), 0), p_is_new => false);
      if l_err is not null then
        return l_err;
      end if;
      update_file_content(l_file_id, l_text);
    else
      l_err := check_caps(p_store_id, p_caps, nvl(length(l_text), 0), 0, p_is_new => true);
      if l_err is not null then
        return l_err;
      end if;
      begin
        insert into uc_ai_memory_files (store_id, path, content)
        values (p_store_id, l_norm, l_text);
      exception
        when dup_val_on_index then
          -- lost a create race: overwrite the winner (create-overwrites contract)
          if lock_file(p_store_id, l_norm, l_file_id, l_old) then
            update_file_content(l_file_id, l_text);
          end if;
      end;
    end if;

    return 'File created successfully at: ' || l_norm;
  end cmd_create;


  function cmd_str_replace(
    p_store_id  in number,
    p_caps      in t_caps,
    p_arguments in json_object_t
  ) return clob
  as
    l_path      path_type;
    l_norm      path_type;
    l_old_str   clob;
    l_new_str   clob;
    l_file_id   number;
    l_content   clob;
    l_result    clob;
    l_pos       pls_integer;
    l_count     pls_integer := 0;
    l_lines_txt varchar2(4000 char);
    l_lines_arr t_lines;
    l_line      pls_integer;
    l_from      pls_integer;
    l_to        pls_integer;
    l_err       varchar2(4000 char);
  begin
    l_path := p_arguments.get_string('path');
    if l_path is null then
      return param_required_msg('path', 'str_replace');
    end if;
    l_old_str := p_arguments.get_clob('old_str');
    if l_old_str is null or length(l_old_str) = 0 then
      return param_required_msg('old_str', 'str_replace');
    end if;
    -- omitted new_str deletes old_str
    l_new_str := coalesce(p_arguments.get_clob('new_str'), empty_clob());

    l_norm := normalize_path(l_path);
    if l_norm is null then
      return invalid_path_msg(l_path);
    end if;

    if not lock_file(p_store_id, l_norm, l_file_id, l_content) then
      return 'Error: The path ' || l_norm || ' does not exist. Please provide a valid path.';
    end if;

    if split_lines(l_content).count > c_max_edit_lines then
      return 'Error: File ' || l_norm || ' exceeds maximum line limit of 999,999 lines.';
    end if;

    -- count occurrences (0, 1 or many is all that matters)
    l_pos := instr(l_content, l_old_str, 1);
    <<count_loop>>
    while l_pos > 0 and l_count <= c_max_occurrences loop
      l_count := l_count + 1;
      if l_count > 1 then
        l_lines_txt := l_lines_txt || ', ';
      end if;
      l_lines_txt := l_lines_txt || line_of_position(l_content, l_pos);
      l_pos := instr(l_content, l_old_str, l_pos + 1);
    end loop count_loop;

    if l_count = 0 then
      return 'No replacement was performed, old_str `' || sys.dbms_lob.substr(l_old_str, 2000, 1)
        || '` did not appear verbatim in ' || l_norm || '.';
    elsif l_count > 1 then
      return 'No replacement was performed. Multiple occurrences of old_str `'
        || sys.dbms_lob.substr(l_old_str, 2000, 1) || '` in lines: ' || l_lines_txt
        || '. Please ensure it is unique';
    end if;

    l_pos    := instr(l_content, l_old_str, 1);
    l_result := substr(l_content, 1, l_pos - 1) || l_new_str
      || substr(l_content, l_pos + length(l_old_str));

    l_err := check_caps(p_store_id, p_caps, nvl(length(l_result), 0), nvl(length(l_content), 0), p_is_new => false);
    if l_err is not null then
      return l_err;
    end if;

    update_file_content(l_file_id, l_result);

    -- Anthropic-style snippet around the edit
    l_lines_arr := split_lines(l_result);
    l_line  := line_of_position(l_result, l_pos);
    l_from  := greatest(1, l_line - 2);
    l_to    := least(l_lines_arr.count, l_line + 2 + nvl(regexp_count(sys.dbms_lob.substr(l_new_str, 4000, 1), chr(10)), 0));

    return 'The memory file has been edited.' || chr(10)
      || render_numbered(l_lines_arr, l_from, l_to);
  end cmd_str_replace;


  function cmd_insert(
    p_store_id  in number,
    p_caps      in t_caps,
    p_arguments in json_object_t
  ) return clob
  as
    l_path          path_type;
    l_norm          path_type;
    l_insert_line   pls_integer;
    l_insert_text   clob;
    l_file_id       number;
    l_content       clob;
    l_lines_arr     t_lines;
    l_new_lines_arr t_lines := t_lines();
    l_result        clob;
    l_err           varchar2(4000 char);
  begin
    l_path := p_arguments.get_string('path');
    if l_path is null then
      return param_required_msg('path', 'insert');
    end if;
    if not p_arguments.has('insert_line') then
      return param_required_msg('insert_line', 'insert');
    end if;
    if not p_arguments.has('insert_text') then
      return param_required_msg('insert_text', 'insert');
    end if;
    l_insert_line := p_arguments.get_number('insert_line');
    l_insert_text := coalesce(p_arguments.get_clob('insert_text'), empty_clob());

    l_norm := normalize_path(l_path);
    if l_norm is null then
      return invalid_path_msg(l_path);
    end if;

    if not lock_file(p_store_id, l_norm, l_file_id, l_content) then
      return 'Error: The path ' || l_norm || ' does not exist';
    end if;

    l_lines_arr := split_lines(l_content);

    if l_lines_arr.count > c_max_edit_lines then
      return 'Error: File ' || l_norm || ' exceeds maximum line limit of 999,999 lines.';
    end if;

    if l_insert_line is null or l_insert_line < 0 or l_insert_line > l_lines_arr.count then
      return 'Error: Invalid `insert_line` parameter: ' || l_insert_line
        || '. It should be within the range of lines of the file: [0, ' || l_lines_arr.count || ']';
    end if;

    -- chomp one trailing newline of the inserted text (reference behavior)
    if length(l_insert_text) > 0 and substr(l_insert_text, -1) = chr(10) then
      l_insert_text := substr(l_insert_text, 1, length(l_insert_text) - 1);
    end if;

    <<head_loop>>
    for i in 1 .. l_insert_line loop
      l_new_lines_arr.extend;
      l_new_lines_arr(l_new_lines_arr.count) := l_lines_arr(i);
    end loop head_loop;
    l_new_lines_arr.extend;
    l_new_lines_arr(l_new_lines_arr.count) := l_insert_text;
    <<tail_loop>>
    for i in l_insert_line + 1 .. l_lines_arr.count loop
      l_new_lines_arr.extend;
      l_new_lines_arr(l_new_lines_arr.count) := l_lines_arr(i);
    end loop tail_loop;

    l_result := join_lines(l_new_lines_arr);

    l_err := check_caps(p_store_id, p_caps, nvl(length(l_result), 0), nvl(length(l_content), 0), p_is_new => false);
    if l_err is not null then
      return l_err;
    end if;

    update_file_content(l_file_id, l_result);

    return 'The file ' || l_norm || ' has been edited.';
  end cmd_insert;


  function cmd_delete(
    p_store_id  in number,
    p_arguments in json_object_t
  ) return clob
  as
    l_path path_type;
    l_norm path_type;
  begin
    l_path := p_arguments.get_string('path');
    if l_path is null then
      return param_required_msg('path', 'delete');
    end if;

    l_norm := normalize_path(l_path);
    if l_norm is null then
      return invalid_path_msg(l_path);
    end if;
    if l_norm = c_root then
      return 'Error: cannot delete the ' || c_root || ' root directory.';
    end if;

    -- a path may be a file, an (implicit) directory, or both — remove all of it
    delete from uc_ai_memory_files
     where store_id = p_store_id
       and (path = l_norm or path like l_norm || '/%');

    if sql%rowcount = 0 then
      return 'Error: The path ' || l_norm || ' does not exist';
    end if;

    return 'Successfully deleted ' || l_norm;
  end cmd_delete;


  function cmd_rename(
    p_store_id  in number,
    p_arguments in json_object_t
  ) return clob
  as
    l_old_path path_type;
    l_new_path path_type;
    l_old      path_type;
    l_new      path_type;
    l_cnt      pls_integer;
    l_moved    pls_integer := 0;
    l_user     varchar2(255 char) := current_user_id();
  begin
    l_old_path := p_arguments.get_string('old_path');
    if l_old_path is null then
      return param_required_msg('old_path', 'rename');
    end if;
    l_new_path := p_arguments.get_string('new_path');
    if l_new_path is null then
      return param_required_msg('new_path', 'rename');
    end if;

    l_old := normalize_path(l_old_path);
    if l_old is null then
      return invalid_path_msg(l_old_path);
    end if;
    l_new := normalize_path(l_new_path);
    if l_new is null then
      return invalid_path_msg(l_new_path);
    end if;

    if l_old = c_root or l_new = c_root then
      return 'Error: cannot rename the ' || c_root || ' root directory.';
    end if;
    if l_new like l_old || '/%' then
      return 'Error: cannot move ' || l_old || ' inside itself.';
    end if;
    if l_old = l_new then
      return 'Error: The destination ' || l_new || ' already exists';
    end if;

    select count(*)
      into l_cnt
      from uc_ai_memory_files
     where store_id = p_store_id
       and (path = l_new or path like l_new || '/%')
       and rownum = 1;
    if l_cnt > 0 then
      return 'Error: The destination ' || l_new || ' already exists';
    end if;

    -- exact file (locked by the update itself)
    update uc_ai_memory_files
       set path       = l_new,
           updated_by = l_user,
           updated_at = systimestamp
     where store_id = p_store_id
       and path = l_old;
    l_moved := sql%rowcount;

    -- (implicit) directory: move the whole prefix
    update uc_ai_memory_files
       set path       = l_new || substr(path, length(l_old) + 1),
           updated_by = l_user,
           updated_at = systimestamp
     where store_id = p_store_id
       and path like l_old || '/%';
    l_moved := l_moved + sql%rowcount;

    if l_moved = 0 then
      return 'Error: The path ' || l_old || ' does not exist';
    end if;

    return 'Successfully renamed ' || l_old || ' to ' || l_new;
  end cmd_rename;


  -- ==========================================================================
  -- Tool entry point
  -- ==========================================================================

  function execute_command(p_arguments in json_object_t) return clob
  as
    l_scope    uc_ai_logger.scope := gc_scope_prefix || 'execute_command';
    l_args     json_object_t := p_arguments;
    l_keys     json_key_list;
    l_command  varchar2(50 char);
    l_store_id number;
    l_caps     t_caps;
    l_error    varchar2(4000 char);
    l_wrap_key varchar2(4000 char);
    l_wrap_cnt pls_integer := 0;
  begin
    if l_args is null then
      return param_required_msg('command', 'memory');
    end if;

    -- some providers/schemas wrap the arguments in a single parent object. The
    -- tool layer always adds the run context under uc_ai.c_run_context_key, so
    -- that key never counts as the wrapper.
    if not l_args.has('command') then
      l_keys := l_args.get_keys;
      if l_keys is not null then
        <<key_loop>>
        for i in 1 .. l_keys.count loop
          if l_keys(i) != uc_ai.c_run_context_key then
            l_wrap_cnt := l_wrap_cnt + 1;
            l_wrap_key := l_keys(i);
          end if;
        end loop key_loop;
      end if;

      if l_wrap_cnt = 1
        and l_args.get(l_wrap_key) is not null
        and l_args.get(l_wrap_key).is_object
      then
        l_args := treat(l_args.get(l_wrap_key) as json_object_t);
      end if;
    end if;

    l_command := lower(l_args.get_string('command'));
    if l_command is null then
      return param_required_msg('command', 'memory');
    end if;

    resolve_store(l_store_id, l_caps, l_error);
    if l_error is not null then
      return l_error;
    end if;

    case l_command
      when 'view'        then return cmd_view(l_store_id, l_args);
      when 'create'      then return cmd_create(l_store_id, l_caps, l_args);
      when 'str_replace' then return cmd_str_replace(l_store_id, l_caps, l_args);
      when 'insert'      then return cmd_insert(l_store_id, l_caps, l_args);
      when 'delete'      then return cmd_delete(l_store_id, l_args);
      when 'rename'      then return cmd_rename(l_store_id, l_args);
      else
        return 'Error: unknown command `' || l_command
          || '`. Valid commands: view, create, str_replace, insert, delete, rename.';
    end case;
  exception
    -- @dblinter ignore(g-5040): tool contract - errors go back to the model as
    -- result strings, never as raised exceptions (provider error handling differs)
    when others then
      uc_ai_logger.log_error(
        p_text  => 'memory tool command failed'
      , p_scope => l_scope
      , p_extra => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
      return 'Error: memory command failed unexpectedly: ' || sqlerrm;
  end execute_command;


  function execute_command(p_arguments in clob) return clob
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'execute_command(clob)';
    l_args  json_object_t;
  begin
    -- The tool layer (uc_ai_tools_api.exec_function_call) binds the arguments of
    -- a tool call as one CLOB, so the registered function_call comes in here.
    if p_arguments is not null then
      begin
        l_args := json_object_t.parse(p_arguments);
      exception
        -- @dblinter ignore(g-5040): tool contract - a model can send anything, and
        -- text that does not parse must reach the model as a result string
        when others then
          uc_ai_logger.log_error(
            p_text  => 'memory tool arguments are no JSON object'
          , p_scope => l_scope
          , p_extra => sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
          );
          return 'Error: the memory arguments are not a JSON object. Send an object like'
            || ' {"command": "view", "path": "/memories"}.';
      end;
    end if;

    return execute_command(p_arguments => l_args);
  end execute_command;


  -- ==========================================================================
  -- Low-code enablement
  -- ==========================================================================

  /*
   * Adds the memory tool tag (+ g_enable_tools) to the model_config_json of
   * the prompt profile the agent currently resolves to.
   */
  procedure add_tag_to_profile(p_agent_code in uc_ai_agents.code%type)
  as
    l_scope   uc_ai_logger.scope := gc_scope_prefix || 'add_tag_to_profile';
    l_agent   uc_ai_agents%rowtype;
    l_profile uc_ai_prompt_profiles%rowtype;
    l_config  json_object_t;
    l_tags    json_array_t;
    l_has_tag boolean := false;
    l_others  varchar2(4000 char);
  begin
    select *
      into l_agent
      from (
        select *
          from uc_ai_agents
         where code = p_agent_code
         order by case when status = uc_ai_agents_api.c_status_active then 0 else 1 end, version desc
      )
     where rownum = 1;

    if l_agent.agent_type != uc_ai_agents_api.c_type_profile
      or l_agent.prompt_profile_code is null
    then
      uc_ai_logger.log_warn(
        p_text  => 'Memory enabled for agent ' || p_agent_code || ' (type ' || l_agent.agent_type
          || '), but the tool tag can only be wired into profile agents automatically.'
          || ' Add the tag ''' || c_tool_tag || ''' to the relevant prompt profiles'' g_tool_tags manually.'
      , p_scope => l_scope
      );
      return;
    end if;

    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(
      p_code    => l_agent.prompt_profile_code,
      p_version => l_agent.prompt_profile_version
    );

    l_config := json_object_t.parse(coalesce(l_profile.model_config_json, '{}'));
    if l_config.has('g_tool_tags') then
      l_tags := l_config.get_array('g_tool_tags');
    else
      l_tags := json_array_t();
    end if;

    <<tag_check>>
    for i in 0 .. l_tags.get_size - 1 loop
      if l_tags.get_string(i) = c_tool_tag then
        l_has_tag := true;
        exit tag_check;
      end if;
    end loop tag_check;

    if not l_has_tag then
      l_tags.append(c_tool_tag);
    end if;

    l_config.put('g_tool_tags', l_tags);
    l_config.put('g_enable_tools', true);

    uc_ai_prompt_profiles_api.update_prompt_profile(
      p_code                   => l_profile.code,
      p_version                => l_profile.version,
      p_description            => l_profile.description,
      p_system_prompt_template => l_profile.system_prompt_template,
      p_user_prompt_template   => l_profile.user_prompt_template,
      p_provider               => l_profile.provider,
      p_model                  => l_profile.model,
      p_model_config_json      => l_config.to_clob,
      p_response_schema        => l_profile.response_schema,
      p_parameters_schema      => l_profile.parameters_schema
    );

    -- warn when other agents reference the same profile: they gain tool
    -- VISIBILITY (they still resolve their own stores, so no data leaks)
    select listagg(distinct code, ', ' on overflow truncate) within group (order by code)
      into l_others
      from uc_ai_agents
     where prompt_profile_code = l_profile.code
       and code != p_agent_code;

    if l_others is not null then
      uc_ai_logger.log_warn(
        p_text  => 'Prompt profile ' || l_profile.code || ' (v' || l_profile.version
          || ') is also referenced by agent(s) ' || l_others
          || ' - they will see the memory tool too (each resolves its own store).'
      , p_scope => l_scope
      );
    end if;
  end add_tag_to_profile;


  /*
   * Removes the memory tool tag from the agent's profile, unless another
   * memory-enabled agent shares that profile.
   */
  procedure remove_tag_from_profile(p_agent_code in uc_ai_agents.code%type)
  as
    l_scope   uc_ai_logger.scope := gc_scope_prefix || 'remove_tag_from_profile';
    l_agent   uc_ai_agents%rowtype;
    l_profile uc_ai_prompt_profiles%rowtype;
    l_config  json_object_t;
    l_tags    json_array_t;
    l_new     json_array_t := json_array_t();
    l_cnt     pls_integer;
  begin
    select *
      into l_agent
      from (
        select *
          from uc_ai_agents
         where code = p_agent_code
         order by case when status = uc_ai_agents_api.c_status_active then 0 else 1 end, version desc
      )
     where rownum = 1;

    if l_agent.agent_type != uc_ai_agents_api.c_type_profile
      or l_agent.prompt_profile_code is null
    then
      return;
    end if;

    -- keep the tag when another memory-enabled agent uses the same profile
    -- @dblinter ignore(g-8110): an existence check; the count itself is not used
    select count(*)
      into l_cnt
      from uc_ai_memory_config c
     where c.enabled = 'Y'
       and c.agent_code != p_agent_code
       and exists (
         select 1
           from uc_ai_agents a
          where a.code = c.agent_code
            and a.prompt_profile_code = l_agent.prompt_profile_code
       );

    if l_cnt > 0 then
      uc_ai_logger.log_warn(
        p_text  => 'Memory tool tag kept on profile ' || l_agent.prompt_profile_code
          || ': another memory-enabled agent still uses it.'
      , p_scope => l_scope
      );
      return;
    end if;

    l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(
      p_code    => l_agent.prompt_profile_code,
      p_version => l_agent.prompt_profile_version
    );

    l_config := json_object_t.parse(coalesce(l_profile.model_config_json, '{}'));
    if not l_config.has('g_tool_tags') then
      return;
    end if;

    l_tags := l_config.get_array('g_tool_tags');
    <<tag_loop>>
    for i in 0 .. l_tags.get_size - 1 loop
      if l_tags.get_string(i) != c_tool_tag then
        l_new.append(l_tags.get_string(i));
      end if;
    end loop tag_loop;
    l_config.put('g_tool_tags', l_new);

    uc_ai_prompt_profiles_api.update_prompt_profile(
      p_code                   => l_profile.code,
      p_version                => l_profile.version,
      p_description            => l_profile.description,
      p_system_prompt_template => l_profile.system_prompt_template,
      p_user_prompt_template   => l_profile.user_prompt_template,
      p_provider               => l_profile.provider,
      p_model                  => l_profile.model,
      p_model_config_json      => l_config.to_clob,
      p_response_schema        => l_profile.response_schema,
      p_parameters_schema      => l_profile.parameters_schema
    );
  end remove_tag_from_profile;


  procedure enable_for_agent(
    p_agent_code      in uc_ai_agents.code%type,
    p_scope           in varchar2 default c_scope_agent,
    p_store_code      in varchar2 default null,
    p_context_key     in varchar2 default null,
    p_update_profile  in boolean  default true,
    p_max_file_chars  in number   default null,
    p_max_store_chars in number   default null,
    p_max_files       in number   default null
  )
  as
    l_scope_lc varchar2(50 char) := lower(trim(p_scope));
    l_cnt      pls_integer;
    l_user     varchar2(255 char) := current_user_id();
  begin
    if l_scope_lc not in (c_scope_agent, c_scope_user, c_scope_session, c_scope_shared, c_scope_global,
                          c_scope_context) then
      raise_application_error(c_err_invalid_scope,
        'Invalid memory scope "' || p_scope || '". Valid: agent, user, session, shared, global, context.');
    end if;

    if l_scope_lc = c_scope_shared and p_store_code is null then
      raise_application_error(c_err_config_invalid,
        'Memory scope "shared" requires p_store_code (the named store to share).');
    end if;

    if l_scope_lc = c_scope_context and p_context_key is null then
      raise_application_error(c_err_config_invalid,
        'Memory scope "context" requires p_context_key (the run-context key that identifies the store).');
    end if;

    -- @dblinter ignore(g-8110): an existence check; the count itself is not used
    select count(*) into l_cnt from uc_ai_agents where code = p_agent_code;
    if l_cnt = 0 then
      raise_application_error(c_err_agent_not_found,
        'Agent "' || p_agent_code || '" does not exist.');
    end if;

    merge into uc_ai_memory_config t
    using (select p_agent_code as agent_code from dual) s
       on (t.agent_code = s.agent_code)
    when matched then update set
      t.scope           = l_scope_lc,
      t.store_code      = p_store_code,
      t.context_key     = p_context_key,
      t.enabled         = 'Y',
      t.max_file_chars  = coalesce(p_max_file_chars, t.max_file_chars),
      t.max_store_chars = coalesce(p_max_store_chars, t.max_store_chars),
      t.max_files       = coalesce(p_max_files, t.max_files),
      t.updated_by      = l_user,
      t.updated_at      = systimestamp
    when not matched then insert
      (agent_code, scope, store_code, context_key, enabled, max_file_chars, max_store_chars, max_files)
    values
      (p_agent_code, l_scope_lc, p_store_code, p_context_key, 'Y',
       coalesce(p_max_file_chars, c_default_max_file_chars),
       p_max_store_chars,
       coalesce(p_max_files, c_default_max_files));

    if p_update_profile then
      add_tag_to_profile(p_agent_code);
    end if;
  end enable_for_agent;


  procedure disable_for_agent(
    p_agent_code      in uc_ai_agents.code%type,
    p_remove_tool_tag in boolean default true,
    p_drop_store      in boolean default false
  )
  as
    l_user varchar2(255 char) := current_user_id();
    -- The agent code goes into a LIKE pattern below, so its wildcards are escaped.
    l_like_code varchar2(1000 char) := like_literal(p_agent_code);
  begin
    update uc_ai_memory_config
       set enabled    = 'N',
           updated_by = l_user,
           updated_at = systimestamp
     where agent_code = p_agent_code;

    if sql%rowcount = 0 then
      raise_application_error(c_err_config_invalid,
        'Memory was never enabled for agent "' || p_agent_code || '".');
    end if;

    if p_remove_tool_tag then
      remove_tag_from_profile(p_agent_code);
    end if;

    if p_drop_store then
      -- Only the agent's OWN stores; shared/global/session stores are kept. A
      -- context store counts as the agent's own exactly when it was not put in a
      -- shared namespace, which is when its namespace segment is the agent code.
      delete from uc_ai_memory_stores
       where store_key = 'agent:' || p_agent_code
          or store_key like 'user:'    || l_like_code || ':%' escape '\'
          or store_key like 'context:' || l_like_code || ':%' escape '\';
    end if;
  end disable_for_agent;


  -- ==========================================================================
  -- Standalone (non-agent) usage
  -- ==========================================================================

  procedure set_store(p_store_code in varchar2)
  as
  begin
    if p_store_code is null then
      raise_application_error(c_err_config_invalid, 'p_store_code must not be null (use clear_store).');
    end if;
    g_store_override := p_store_code;
  end set_store;


  procedure clear_store
  as
  begin
    g_store_override := null;
  end clear_store;


  -- ==========================================================================
  -- Prompt protocol
  -- ==========================================================================

  function get_memory_protocol return clob
  as
  begin
    return '# MEMORY PROTOCOL' || chr(10)
      || 'You have a persistent memory directory at /memories, accessed through the "memory" tool. It survives across conversations.' || chr(10)
      || '1. ALWAYS check your memory first: view /memories before doing anything else, and read the files relevant to the task.' || chr(10)
      || '2. Record important context as you work - decisions, user preferences, learnings, task progress. Update memory continuously, not only at the end.' || chr(10)
      || '3. ASSUME INTERRUPTION: your context window may be reset at any moment; anything not recorded in memory is lost.' || chr(10)
      || '4. Keep memory organized: small focused files; update or delete stale content instead of piling up new files.' || chr(10)
      || '5. A memory command can report that it could not determine your memory store, rather than that a file is missing. That is a failure to reach your memory, NOT an empty memory. After such a result, do not state what you do or do not remember: tell the user that the memory could not be read.';
  end get_memory_protocol;


  procedure check_run_ready(
    p_agent_code  in uc_ai_agents.code%type,
    p_run_context in clob
  )
  as
    l_cfg     uc_ai_memory_config%rowtype;
    l_ctx_val varchar2(4000 char);
  begin
    begin
      select *
        into l_cfg
        from uc_ai_memory_config
       where agent_code = p_agent_code
         and enabled = 'Y';
    exception
      when no_data_found then
        -- no memory for this agent: nothing to be ready for
        return;
    end;

    if l_cfg.scope != c_scope_context then
      return;
    end if;

    l_ctx_val := uc_ai.run_context_value(p_run_context, l_cfg.context_key);

    if l_ctx_val is null then
      raise_application_error(c_err_context_missing,
        'The memory of agent "' || p_agent_code || '" is scoped to the run-context key "'
        || l_cfg.context_key || '", which this run does not supply. Pass it in p_run_context,'
        || ' for example json_object_t(''{"' || l_cfg.context_key || '":"123"}'').');
    end if;

    if not valid_context_value(l_ctx_val) then
      raise_application_error(c_err_context_missing,
        'The run-context value of "' || l_cfg.context_key || '" cannot identify a memory store'
        || ' for agent "' || p_agent_code || '". Use at most 200 characters from A-Z, a-z, 0-9,'
        || ' underscore, dot and hyphen.');
    end if;
  end check_run_ready;


  procedure augment_system_prompt(
    pio_system_prompt in out nocopy clob
  )
  as
    l_ctx uc_ai.t_exec_context;
    l_cnt pls_integer;
  begin
    l_ctx := uc_ai.get_exec_context;
    if l_ctx.agent_code is null then
      return;
    end if;

    -- @dblinter ignore(g-8110): an existence check; the count itself is not used
    select count(*)
      into l_cnt
      from uc_ai_memory_config
     where agent_code = l_ctx.agent_code
       and enabled = 'Y';

    if l_cnt = 0 then
      return;
    end if;

    pio_system_prompt :=
      case
        when pio_system_prompt is not null then pio_system_prompt || chr(10) || chr(10)
      end
      || get_memory_protocol;
  end augment_system_prompt;


  -- ==========================================================================
  -- Admin helpers
  -- ==========================================================================

  function resolve_store_id(
    p_scope         in varchar2,
    p_agent_code    in varchar2 default null,
    p_username      in varchar2 default null,
    p_session_id    in varchar2 default null,
    p_store_code    in varchar2 default null,
    p_context_key   in varchar2 default null,
    p_context_value in varchar2 default null
  ) return number
  as
    l_scope_lc varchar2(50 char) := lower(trim(p_scope));
    l_key      uc_ai_memory_stores.store_key%type;
    l_id       number;
  begin
    case l_scope_lc
      when c_scope_agent   then l_key := 'agent:' || p_agent_code;
      when c_scope_user    then l_key := 'user:' || p_agent_code || ':' || p_username;
      when c_scope_session then l_key := 'session:' || p_session_id;
      when c_scope_shared  then l_key := 'shared:' || p_store_code;
      when c_scope_global  then l_key := 'global';
      when c_scope_context then
        l_key := context_store_key(
                   p_namespace     => coalesce(p_store_code, p_agent_code)
                 , p_context_key   => p_context_key
                 , p_context_value => p_context_value
                 );
      else
        raise_application_error(c_err_invalid_scope,
          'Invalid memory scope "' || p_scope || '". Valid: agent, user, session, shared, global, context.');
    end case;

    select id
      into l_id
      from uc_ai_memory_stores
     where store_key = l_key;

    return l_id;
  exception
    when no_data_found then
      raise_application_error(c_err_store_not_found,
        'No memory store exists for key "' || l_key || '".');
  end resolve_store_id;


  function list_files(p_store_id in number) return sys_refcursor
  as
    l_files_cur sys_refcursor;
  begin
    open l_files_cur for
      select path,
             sys.dbms_lob.getlength(content) as char_count,
             created_at,
             updated_at,
             last_accessed_at
        from uc_ai_memory_files
       where store_id = p_store_id
       order by path;
    return l_files_cur;
  end list_files;


  function get_file(
    p_store_id in number,
    p_path     in varchar2
  ) return clob
  as
    l_content clob;
    l_norm    path_type := normalize_path(p_path);
  begin
    select content
      into l_content
      from uc_ai_memory_files
     where store_id = p_store_id
       and path = coalesce(l_norm, p_path);
    return l_content;
  exception
    when no_data_found then
      raise_application_error(c_err_file_not_found,
        'Memory file "' || p_path || '" does not exist in store ' || p_store_id || '.');
  end get_file;


  procedure put_file(
    p_store_id in number,
    p_path     in varchar2,
    p_content  in clob
  )
  as
    l_norm    path_type := normalize_path(p_path);
    l_file_id number;
    l_old     clob;
  begin
    if l_norm is null or l_norm = c_root then
      raise_application_error(c_err_config_invalid,
        'Invalid memory path "' || p_path || '": must be a file path under ' || c_root || '.');
    end if;

    if lock_file(p_store_id, l_norm, l_file_id, l_old) then
      update_file_content(l_file_id, coalesce(p_content, empty_clob()));
    else
      insert into uc_ai_memory_files (store_id, path, content)
      values (p_store_id, l_norm, coalesce(p_content, empty_clob()));
    end if;
  end put_file;


  procedure delete_file(
    p_store_id in number,
    p_path     in varchar2
  )
  as
    l_norm path_type := normalize_path(p_path);
  begin
    delete from uc_ai_memory_files
     where store_id = p_store_id
       and path = coalesce(l_norm, p_path);

    if sql%rowcount = 0 then
      raise_application_error(c_err_file_not_found,
        'Memory file "' || p_path || '" does not exist in store ' || p_store_id || '.');
    end if;
  end delete_file;


  procedure clear_store_files(p_store_id in number)
  as
  begin
    delete from uc_ai_memory_files
     where store_id = p_store_id;
  end clear_store_files;


  procedure expire_files(
    p_days     in number,
    p_store_id in number default null
  )
  as
  begin
    if p_days is null or p_days <= 0 then
      raise_application_error(c_err_config_invalid, 'p_days must be a positive number.');
    end if;

    delete from uc_ai_memory_files
     where (p_store_id is null or store_id = p_store_id)
       and greatest(last_accessed_at, updated_at) < systimestamp - numtodsinterval(p_days, 'DAY');
  end expire_files;

end uc_ai_memory;
/
