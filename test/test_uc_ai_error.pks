create or replace package test_uc_ai_error as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(uc_ai_error: raise_error templates and parse_json_response)
  --%suitepath(uc_ai)

  -- LLM-free unit tests for the centralized error handling package

  --%test(Default template substitutes a single placeholder)
  procedure default_template_single_sub;

  --%test(Default template substitutes multiple placeholders)
  procedure default_template_multi_sub;

  --%test(p_message overrides the default template)
  procedure message_override;

  --%test(All ten placeholders %0-%9 are substituted)
  procedure all_ten_placeholders;

  --%test(Unmapped error code falls back to generic message)
  procedure unknown_code_fallback;

  --%test(Null placeholder value renders as empty string)
  procedure null_placeholder_renders_empty;

  --%test(parse_json_response parses valid JSON with HTTP 200)
  procedure parse_ok_status_200;

  --%test(parse_json_response parses valid JSON when status code is null)
  procedure parse_ok_status_null;

  --%test(parse_json_response raises on HTTP error status despite valid JSON body)
  procedure parse_http_error_status;

  --%test(parse_json_response wraps JSON parse failures with provider context)
  procedure parse_invalid_json;

  --%aftereach
  procedure reset_status_code;

end test_uc_ai_error;
/
