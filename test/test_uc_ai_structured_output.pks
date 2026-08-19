create or replace package test_uc_ai_structured_output as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Structured Output schema conversion tests)
  --%suitepath(uc_ai)

  -- LLM-free unit tests for uc_ai_structured_output provider format conversion

  --%test(OpenAI strict format wraps schema in json_schema envelope)
  procedure openai_strict_envelope;

  --%test(OpenAI strict mode removes $schema, title and description recursively)
  procedure openai_strict_removes_metadata;

  --%test(OpenAI strict mode adds additionalProperties false to object nodes only)
  procedure openai_strict_additional_props;

  --%test(OpenAI strict mode forces all properties into required)
  procedure openai_strict_forces_all_required;

  --%test(OpenAI strict mode recurses into array items schemas)
  procedure openai_strict_recurses_items;

  --%test(OpenAI schema name is sanitized from the title)
  procedure openai_name_sanitized;

  --%test(OpenAI schema name falls back when title yields no valid characters)
  procedure openai_name_fallback;

  --%test(OpenAI non-strict mode passes the schema through unchanged)
  procedure openai_non_strict_passthrough;

  --%test(OpenAI conversion does not mutate the input schema)
  procedure openai_does_not_mutate_input;

  --%test(Google format uppercases schema types)
  procedure google_type_conversion;

  --%test(Google format converts nested properties recursively)
  procedure google_nested_conversion;

  --%test(Google format adds propertyOrdering only when required is present)
  procedure google_property_ordering;

  --%test(Google format converts array items recursively)
  procedure google_array_items;

  --%test(Google format drops keys it does not map)
  procedure google_drops_unknown_keys;

  --%test(Ollama format only removes $schema and title)
  procedure ollama_removes_metadata_only;

  --%test(Anthropic format wraps schema in output_config.format envelope)
  procedure anthropic_envelope;

  --%test(Anthropic format strips unsupported constraints recursively)
  procedure anthropic_strips_constraints;

  --%test(Responses API format has name, strict and schema at the top level)
  procedure responses_api_flat_shape;

  --%test(format_schema dispatches to the provider-specific functions)
  procedure format_schema_dispatch;

  --%test(format_schema raises for providers without structured output support)
  --%throws(-20307)
  procedure format_schema_unknown_provider;

  --%test(Empty schema object converts without errors)
  procedure empty_schema_handled;

end test_uc_ai_structured_output;
/
