create or replace package test_uc_ai_workflow_mapping as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Workflow Mapping/Resolution Tests)
  --%suitepath(uc_ai.agents)

  -- LLM-free unit tests for uc_ai_agent_workflow_api state resolution

  --%test(map_inputs resolves nested input and step paths)
  procedure map_inputs_resolves_nested_paths;

  --%test(map_inputs round-trips a value larger than 32k)
  procedure map_inputs_clob_value_survives;

  --%test(map_inputs substitutes multiple tokens inside surrounding text)
  procedure map_inputs_template_multiple_tokens;

  --%test(map_inputs converts number and boolean leaf values)
  procedure map_inputs_number_and_boolean_conversion;

  --%test(Unresolved paths substitute an empty string without raising)
  procedure unresolved_path_substitutes_empty;

  --%test(evaluate_condition compares resolved numeric values)
  procedure evaluate_condition_numeric_compare;

  --%test(evaluate_condition raises when a referenced value exceeds 32k)
  procedure condition_with_oversized_value_raises;

  --%test(Array elements resolve with 1-based indexing)
  procedure array_index_resolution;

  --%test(Loop iteration snapshots are independent copies)
  procedure loop_iteration_snapshots_differ;

  --%test(add_result_to_workflow_state raises when step has no output_key)
  --%throws(-20450)
  procedure add_result_missing_output_key;

  --%test(add_result_to_workflow_state creates steps object and preserves existing keys)
  procedure add_result_creates_steps_object;

  --%test(add_result_to_workflow_state keeps a final_message larger than 32k)
  procedure add_result_clob_final_message;

  --%test(add_result_to_workflow_state stores a non-string final_message as-is)
  procedure add_result_non_string_final_message;

  --%test(evaluate_final_message resolves expression objects against state)
  procedure final_message_object_expression;

  --%test(String final_message resolves without its JSON quotes)
  procedure final_message_string_element_quotes;

  --%test(evaluate_final_message returns full CLOB for plain expressions over 32k)
  procedure final_message_clob_32k_plain;

  --%test(evaluate_final_message evaluates PL/SQL expressions)
  procedure final_message_plsql_expression;

  --%test(PL/SQL final_message raises when the resolved value exceeds 32k)
  procedure final_message_plsql_oversized;

  --%test(Invalid PL/SQL final_message raises the final message eval error)
  --%throws(-20453)
  procedure final_message_plsql_invalid;

  --%test(Unresolvable state expression raises the jsonpath resolve error)
  --%throws(-20455)
  procedure jsonpath_resolve_error;

  --%test(manage_history passes history through when config is null)
  procedure history_null_config_passthrough;

  --%test(manage_history full strategy passes history through)
  procedure history_full_passthrough;

  --%test(Sliding window below the limit returns history unchanged)
  procedure history_window_under_limit;

  --%test(Sliding window trims to the last N messages)
  procedure history_window_trims;

  --%test(Sliding window preserves a leading system message)
  procedure history_window_keeps_system;

  --%test(Sliding window defaults to 20 messages)
  procedure history_window_default_20;

  --%test(Summarize without a summarizer agent falls back to a window)
  procedure history_summarize_fallback_window;

  --%test(Summarize below the threshold returns history unchanged)
  procedure history_summarize_under_threshold;

  --%test(Unknown history strategy passes history through)
  procedure history_unknown_strategy_passthrough;

end test_uc_ai_workflow_mapping;
/
