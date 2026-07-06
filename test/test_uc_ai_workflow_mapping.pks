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

end test_uc_ai_workflow_mapping;
/
