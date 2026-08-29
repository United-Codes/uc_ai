create or replace package test_uc_ai_structured_output as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Structured Output schema conversion tests)
  --%suitepath(uc_ai)

  -- LLM-free unit tests for uc_ai_structured_output provider format conversion.
  --
  -- The keyword survival tests below are the contract. Each one sends a schema that
  -- carries every JSON schema keyword through one provider path and states exactly
  -- which keywords reach the wire. Provider behaviour was measured with live API
  -- calls; /tmp/uc-ai-docs-audit/PROBE-RESULTS.md records the HTTP 400 texts.

  --%test(OpenAI strict format wraps schema in json_schema envelope)
  procedure openai_strict_envelope;

  --%test(OpenAI strict mode keeps $schema, title and description)
  procedure openai_strict_keeps_metadata;

  --%test(OpenAI strict mode keeps every keyword the provider accepts)
  procedure openai_keyword_survival;

  --%test(OpenAI strict mode removes only the keywords the provider rejects)
  procedure openai_strips_rejected_keywords;

  --%test(OpenAI strict mode adds additionalProperties false to object nodes only)
  procedure openai_strict_additional_props;

  --%test(OpenAI strict mode forces all properties into required)
  procedure openai_strict_forces_all_required;

  --%test(OpenAI strict mode recurses into array items schemas)
  procedure openai_strict_recurses_items;

  --%test(OpenAI strict mode recurses into $defs and definitions)
  procedure openai_strict_recurses_defs;

  --%test(OpenAI strict mode recurses into anyOf, oneOf and allOf branches)
  procedure openai_strict_recurses_branches;

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

  --%test(Google format keeps every field the Gemini Schema proto has)
  procedure google_keyword_survival;

  --%test(Google format drops only the fields the proto does not have)
  procedure google_drops_non_proto_keys;

  --%test(Google format orders every property, not only the required ones)
  procedure google_property_ordering;

  --%test(Google format keeps an author-supplied propertyOrdering)
  procedure google_keeps_author_ordering;

  --%test(Google format converts array items recursively)
  procedure google_array_items;

  --%test(Google format writes enum values as strings)
  procedure google_enum_as_strings;

  --%test(Google format writes a local $ref out in place)
  procedure google_inlines_local_ref;

  --%test(Google format turns a union with null into nullable)
  procedure google_union_becomes_nullable;

  --%test(Google conversion does not mutate the input schema)
  procedure google_does_not_mutate_input;

  --%test(Ollama format only removes $schema and title)
  procedure ollama_removes_metadata_only;

  --%test(Anthropic format wraps schema in output_config.format envelope)
  procedure anthropic_envelope;

  --%test(Anthropic format keeps the author's partial required list)
  procedure anthropic_keeps_author_required;

  --%test(Anthropic format keeps every keyword the provider accepts)
  procedure anthropic_keyword_survival;

  --%test(Anthropic format removes only the keywords the provider rejects)
  procedure anthropic_strips_constraints;

  --%test(Anthropic format keeps minItems of 0 or 1 and removes anything larger)
  procedure anthropic_min_items_boundary;

  --%test(Anthropic format recurses into $defs and anyOf branches)
  procedure anthropic_recurses_defs_and_anyof;

  --%test(A removed constraint is written into the node description)
  procedure constraint_folded_into_desc;

  --%test(A folded note starts a new sentence and keeps the decimal zero)
  procedure constraint_note_formatting;

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
