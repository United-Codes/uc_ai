create or replace package test_uc_ai_passthrough as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Extra request-body and provider-tools passthrough)
  --%suitepath(uc_ai)

  -- LLM-free unit tests for uc_ai.g_extra_body / g_provider_tools, the
  -- uc_ai_settings transport (build_from_globals / build_from_config /
  -- apply_extra_body) and uc_ai_tools_api.get_tools_array raw tool injection.

  --%aftereach
  procedure reset_globals;

  -- apply_extra_body
  --%test(apply_extra_body merges new top-level keys onto the request body)
  procedure extra_body_merges_new_keys;

  --%test(apply_extra_body overrides a non-reserved framework key)
  procedure extra_body_overrides_key;

  --%test(apply_extra_body skips reserved core keys)
  procedure extra_body_protects_core;

  --%test(apply_extra_body is a no-op when extra_body is null)
  procedure extra_body_null_noop;

  -- settings transport
  --%test(build_from_globals snapshots g_extra_body and g_provider_tools)
  procedure globals_snapshot;

  --%test(build_from_config reads g_extra_body and g_provider_tools keys)
  procedure config_reads_keys;

  -- get_tools_array provider tools
  --%test(get_tools_array appends provider tools verbatim without wrapping)
  procedure provider_tools_verbatim;

  --%test(get_tools_array returns provider tools even when tools disabled)
  procedure provider_tools_when_disabled;

end test_uc_ai_passthrough;
/
