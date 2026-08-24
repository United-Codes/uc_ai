create or replace package test_uc_ai_memory as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Agent-memory tests (LLM-free))
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  -- LLM-free unit tests for uc_ai_memory: virtual-filesystem commands, store
  -- resolution, the config API and the system-prompt augmentation.
  -- execute_command is called directly with hand-built JSON arguments; the
  -- execution context is stubbed via uc_ai.set_exec_context. No agent execution
  -- / provider call happens.

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%beforeeach
  procedure before_each;

  --%aftereach
  procedure after_each;

  -- ---- path security -------------------------------------------------------

  --%test(paths outside /memories are rejected)
  procedure rejects_path_outside_memories;

  --%test(dot-dot traversal is rejected)
  procedure rejects_dotdot_traversal;

  --%test(backslash paths are rejected)
  procedure rejects_backslash_traversal;

  --%test(URL-encoded traversal is rejected)
  procedure rejects_urlencoded_traversal;

  --%test(duplicate slashes are normalized to one path)
  procedure normalizes_duplicate_slashes;

  -- ---- store resolution -----------------------------------------------------

  --%test(agent scope resolves to one store per agent code)
  procedure resolves_agent_scope;

  --%test(user scope gives each user of the agent an own store)
  procedure resolves_user_scope_per_user;

  --%test(session scope gives each session an own store)
  procedure resolves_session_scope;

  --%test(shared scope lets several agents use the same named store)
  procedure resolves_shared_store_across_agents;

  --%test(global scope resolves to the single global store)
  procedure resolves_global_scope;

  --%test(no agent context and no override returns an instructive error)
  procedure standalone_without_context_returns_error;

  --%test(set_store override resolves to the named shared store)
  procedure set_store_override_resolves_shared;

  --%test(a disabled config returns an instructive error)
  procedure disabled_config_returns_error;

  --%test(store auto-provisioning is idempotent (one row per key))
  procedure store_autoprovision_is_idempotent;

  -- ---- view -----------------------------------------------------------------

  --%test(viewing the empty root is a listing, not an error)
  procedure view_empty_root_not_error;

  --%test(directory listing shows two levels with aggregated sizes)
  procedure view_directory_two_levels_sizes;

  --%test(file view uses 6-char right-aligned line numbers with a tab)
  procedure view_file_line_numbers_format;

  --%test(view_range returns the requested slice)
  procedure view_range_slice;

  --%test(view_range end -1 reads to end of file)
  procedure view_range_minus_one_to_eof;

  --%test(a view_range that is not an array of two integers is reported on a file)
  procedure view_range_bad_shape_on_file;

  --%test(a view_range outside the file is reported with the real line count)
  procedure view_range_out_of_bounds_on_file;

  --%test(an absent, null or empty view_range shows the whole file)
  procedure view_range_empty_shows_whole_file;

  --%test(a directory listing ignores view_range, whatever a strict-mode provider invented)
  procedure view_directory_ignores_any_range;

  --%test(the whole-file view_range a strict-mode provider always sends still lists a directory)
  procedure view_directory_with_default_range;

  --%test(a null or empty view_range does not stop a directory listing)
  procedure view_directory_with_empty_range;

  --%test(the full strict-mode argument set still lists the root)
  procedure view_root_with_strict_mode_arguments;

  --%test(views longer than 16k chars are truncated with a hint)
  procedure view_truncates_over_16k;

  --%test(viewing a missing path returns the contract error string)
  procedure view_missing_path_error_string;

  --%test(viewing a file refreshes last_accessed_at)
  procedure view_touches_last_accessed;

  -- ---- create ---------------------------------------------------------------

  --%test(create returns the contract success message)
  procedure create_new_file_message;

  --%test(create overwrites an existing file)
  procedure create_overwrites_existing;

  --%test(create enforces the per-file size cap)
  procedure create_enforces_file_cap;

  --%test(create enforces the max-files cap)
  procedure create_enforces_max_files;

  -- ---- str_replace ----------------------------------------------------------

  --%test(str_replace replaces a unique occurrence and returns a snippet)
  procedure str_replace_unique_success_snippet;

  --%test(str_replace not-found returns the exact contract message)
  procedure str_replace_not_found_exact_message;

  --%test(str_replace with multiple occurrences reports their line numbers)
  procedure str_replace_multiple_reports_line_numbers;

  --%test(str_replace without new_str deletes old_str)
  procedure str_replace_omitted_new_str_deletes;

  -- ---- insert ---------------------------------------------------------------

  --%test(insert at line 0 prepends)
  procedure insert_line_zero_prepends;

  --%test(insert after a middle line)
  procedure insert_middle;

  --%test(insert with an out-of-range line returns the exact contract message)
  procedure insert_out_of_range_exact_message;

  --%test(insert into a missing file errors)
  procedure insert_missing_file_error;

  -- ---- delete ---------------------------------------------------------------

  --%test(deleting a file returns the contract message)
  procedure delete_file_message;

  --%test(deleting a directory is recursive)
  procedure delete_directory_recursive;

  --%test(deleting the /memories root is refused)
  procedure delete_root_rejected;

  --%test(deleting a missing path errors)
  procedure delete_missing_path_error;

  -- ---- rename ---------------------------------------------------------------

  --%test(renaming a file returns the contract message)
  procedure rename_file_message;

  --%test(renaming a directory moves the whole prefix)
  procedure rename_directory_moves_prefix;

  --%test(renaming onto an existing destination is refused)
  procedure rename_destination_exists_error;

  --%test(renaming the /memories root is refused)
  procedure rename_root_rejected;

  --%test(moving a directory inside itself is refused)
  procedure rename_into_itself_rejected;

  -- ---- config API -----------------------------------------------------------

  --%test(enable_for_agent creates the config row)
  procedure enable_for_agent_creates_config;

  --%test(enable_for_agent wires the memory tag into the profile config)
  procedure enable_adds_memory_tag_to_profile;

  --%test(enable_for_agent with scope shared but no store_code raises -20424)
  procedure enable_shared_requires_store_code;

  --%test(enable_for_agent with an invalid scope raises -20421)
  procedure enable_invalid_scope_raises;

  --%test(enable_for_agent for an unknown agent raises -20422)
  procedure enable_unknown_agent_raises;

  --%test(disable_for_agent disables and removes the profile tag)
  procedure disable_for_agent_disables;

  --%test(disable keeps the profile tag while another enabled agent shares it)
  procedure disable_keeps_tag_when_shared;

  -- ---- admin helpers --------------------------------------------------------

  --%test(expire_files deletes only stale files)
  procedure expire_files_deletes_stale_only;

  --%test(clear_store_files empties the store)
  procedure clear_store_files_empties;

  --%test(put_file / get_file round-trip)
  procedure put_get_file_roundtrip;

  --%test(resolve_store_id finds a store and raises -20423 when missing)
  procedure resolve_store_id_behavior;

  -- ---- context scope --------------------------------------------------------

  --%test(Two run-context values give two separate stores)
  procedure context_scope_separates_values;

  --%test(A run without the context key gets an instructive error and no store)
  procedure context_scope_requires_key;

  --%test(A named store_code lets two agents share one store per context value)
  procedure context_scope_shared_namespace;

  --%test(Without a store_code a context store stays private to its agent)
  procedure context_scope_private_by_default;

  --%test(enable_for_agent with scope context requires p_context_key)
  procedure context_scope_needs_context_key;

  --%test(A context value that could forge a store key is rejected)
  procedure context_scope_rejects_bad_value;

  --%test(resolve_store_id resolves a context store)
  procedure context_scope_resolve_store_id;

  --%test(disable_for_agent drops the agent's own context stores and keeps shared ones)
  procedure context_scope_drop_store;

  --%test(A context value of exactly 200 characters works and one more is refused)
  procedure context_scope_value_length_limit;

  --%test(A context store another session provisioned first is reused, not duplicated)
  procedure context_scope_reuses_existing_store;

  --%test(expire_files and clear_store_files work on one context store only)
  procedure context_scope_housekeeping;

  -- ---- run readiness ---------------------------------------------------------

  --%test(check_run_ready raises when a context-scoped agent has no run-context key)
  procedure run_ready_raises_without_key;

  --%test(check_run_ready raises for a value that cannot identify a store)
  procedure run_ready_raises_on_bad_value;

  --%test(check_run_ready is silent for a supplied key, another scope and no memory)
  procedure run_ready_silent_when_fine;

  --%test(executing a context-scoped agent without its key fails instead of reporting an empty memory)
  procedure run_without_key_fails_the_run;

  --%test(the MEMORY PROTOCOL tells the model not to read a store failure as an empty memory)
  procedure protocol_separates_failure_from_empty;

  -- ---- prompt hook ----------------------------------------------------------

  --%test(augment_system_prompt appends the protocol for a memory-enabled agent)
  procedure augment_appends_protocol;

  --%test(augment_system_prompt is a no-op for other agents)
  procedure augment_noop_when_not_enabled;

  -- ---- tool layer -----------------------------------------------------------

  --%test(the registered MEMORY tool runs a view through uc_ai_tools_api)
  procedure tool_layer_view_works;

  --%test(the registered MEMORY tool writes and reads a file through uc_ai_tools_api)
  procedure tool_layer_create_and_view_file;

  --%test(arguments that are no JSON object give the model an error string)
  procedure tool_layer_malformed_json_error;

  --%test(empty arguments give the model an error string)
  procedure tool_layer_empty_arguments_error;

  --%test(the tool layer keeps the wrapped-arguments fallback usable)
  procedure tool_layer_wrapped_arguments;

end test_uc_ai_memory;
/
