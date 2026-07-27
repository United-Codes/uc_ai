create or replace package test_uc_ai_ptc as

  -- %suite(Programmatic tool calling (PTC / code mode))

  -- %beforeall
  procedure setup_tools;

  -- %afterall
  procedure cleanup_tools;

  -- %aftereach
  -- run_program sets uc_ai globals; leaving them set would break other suites
  -- that run in the same session
  procedure reset_state;

  --%test(code mode orchestrates multiple tools in the sandbox and returns only the aggregate)
  procedure test_code_mode_orchestration;

  --%test(a program that sets no result comes back as an explicit message, not null)
  procedure test_code_mode_no_result;

  --%test(get_tools_array offers the code-mode meta-tool only when enabled, with a tool catalog)
  procedure test_meta_tool_exposure;

  --%test(the meta-tool declares `code` under the schema key each provider expects)
  procedure test_meta_tool_schema_key;

  --%test(the meta-tool omits schema keys Google rejects)
  procedure test_meta_tool_google_schema;

  --%test(the code catalog lists parameter names for every provider)
  procedure test_catalog_param_names;

  --%test(a program larger than 32 KB is passed through uncut)
  procedure test_large_program;

  --%test(the program cannot reach SQL, so it cannot end the caller's transaction)
  procedure test_no_sql_access;

  --%test(allow-list rejects a tool that is not part of the run)
  procedure test_allowlist_rejection;

  --%test(a tool result larger than 32 KB is returned to the program uncapped)
  procedure test_large_tool_result;

  --%test(code_mode_access splits tools between direct list and code catalog)
  procedure test_code_mode_access;

  --%test(merge_tool_from_schema keeps a narrowed code_mode_access when not passed)
  procedure test_merge_keeps_access;

  --%test(a nested code-mode run restores the outer run so it can keep calling tools)
  procedure test_nested_run;

  --%test(a forgotten await before callTool is repaired)
  procedure test_missing_await_repaired;

  --%test(the await rewrite leaves strings, comments and member calls alone and falls back when it would not parse)
  procedure test_await_rewrite_is_safe;

  --%test(console output is returned when the program logs instead of assigning result)
  procedure test_console_output_returned;

  --%test(console output logged before a failure is attached to the error)
  procedure test_console_output_on_error;

  --%test(the before_tool_call hook fires for every callTool inside a program)
  procedure test_hook_fires_for_inner_calls;

  --%test(a before_tool_call veto for an inner call aborts the whole request)
  procedure test_hook_veto_aborts_run;

  -- Sample tool implementations. Registered tools' function_call snippets call
  -- these; they stand in for real data-access tools (cf. the PTC expenses demo).
  function f_get_employees(p_args in clob) return clob;
  function f_get_expenses(p_args in clob) return clob;
  function f_big_payload(p_args in clob) return clob;
  -- Stands in for an agent-as-tool: runs its own code-mode program (nested run).
  function f_nested_program(p_args in clob) return clob;

end test_uc_ai_ptc;
/
