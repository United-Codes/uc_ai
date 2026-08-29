create or replace package test_uc_ai_tools_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Wire-level tool schema and tool argument tests (LLM-free))
  --%suitepath(uc_ai)

  -- uc_ai_tools_api is the shared spine: every provider builds its tools array and
  -- runs every tool through it. This suite pins the two things that were wrong
  -- there and that no per-provider suite could see, because each of them only ever
  -- looked at one provider:
  --
  --   1. the key a tool schema is offered under. ONE flat two-parameter tool is
  --      registered once and offered to every provider in turn; each request has to
  --      carry the whole schema under the key that provider reads. Plain OpenAI
  --      Chat Completions used to get the Anthropic key, so gpt-4o-mini was handed
  --      a function with no parameters and called it with `arguments: {}`.
  --   2. the shape a handler is given. A tool that declares a single object
  --      parameter was unwrapped by Anthropic and Google and not by the others, so
  --      the same handler read NULLs on half the providers.
  --
  -- Plus the COHERE parameterDefinitions conversion, the 32 KB argument ceiling and
  -- the TOO_MANY_ROWS in get_tools_object_param_name.
  --
  -- Same rules as test_uc_ai_wire: uc_ai_test_http_mock stands in for the network,
  -- every call names an APEX web credential (so no test reads uc_ai_get_key), and
  -- every test ends by asserting that every queued response was consumed.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- Tool handlers. Public because the tools registered below call them by name;
  -- they are not tests.
  function capture_args(p_args in clob) return clob;
  function args_length(p_args in clob) return clob;

  -- tool schemas on the wire -----------------------------------------------------
  --%test(Every provider is offered the same flat two-parameter schema under the key it reads)
  procedure flat_schema_reaches_every_provider;

  --%test(OCI COHERE converts a flat schema into populated parameterDefinitions)
  procedure cohere_flat_parameter_definitions;

  --%test(The legacy single-object-parameter schema still converts for COHERE and OCI GENERIC)
  procedure legacy_wrapper_schema_still_works;

  --%test(A tool without parameters keeps an empty parameterDefinitions)
  procedure cohere_no_parameter_tool;

  --%test(Google and OCI get no $schema, because both reject unknown schema keys)
  procedure schema_keywords_left_out_where_rejected;

  -- tool arguments ---------------------------------------------------------------
  --%test(A wrapped argument object is unwrapped once, whichever provider sent it)
  procedure wrapped_arguments_arrive_flat;

  --%test(An already unwrapped payload is not unwrapped a second time)
  procedure unwrap_is_idempotent;

  --%test(A tool argument over 32 KB reaches the handler unchanged)
  procedure large_arguments_reach_the_handler;

  --%test(execute_tool carries a 32 KB argument without apex_plugin_util)
  procedure large_arguments_through_execute_tool;

  --%test(A 32 KB argument also survives the apex_plugin_util branch)
  procedure large_arguments_on_the_apex_branch;

  -- parameter lookup ---------------------------------------------------------------
  --%test(Two top-level parameters, one of them an object, do not raise TOO_MANY_ROWS)
  procedure two_top_level_params_no_error;

end test_uc_ai_tools_wire;
/
