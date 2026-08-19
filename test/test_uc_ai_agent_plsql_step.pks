create or replace package test_uc_ai_agent_plsql_step as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Workflow PL/SQL Step Tests)
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  -- Observable side effects for PL/SQL steps (set from inline snippets)
  g_side_effect  number := 0;
  g_loop_counter number := 0;

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(PL/SQL steps transform data between steps using the full workflow state)
  procedure transforms_between_steps;

  --%test(PL/SQL step output is stored as its real JSON type - number, object, string)
  procedure output_types;

  --%test(PL/SQL step without output_key runs for its side effect and stores nothing)
  procedure optional_output_key;

  --%test(A false condition skips a PL/SQL step)
  procedure condition_skips_step;

  --%test(A PL/SQL step output can gate whether a downstream step runs)
  procedure gates_downstream_step;

  --%test(A stop directive halts all remaining workflow steps)
  procedure stop_halts_workflow;

  --%test(A stop directive breaks out of a loop workflow)
  procedure stop_breaks_loop;

  --%test(Creating a workflow with a PL/SQL step missing plsql_function_call is rejected)
  procedure validation_rejects_missing_fc;

  --%test(Creating a workflow with an unknown step_type is rejected)
  procedure validation_rejects_unknown_type;

  --%test(A PL/SQL-only step - no agent_code, no output_key - is accepted)
  procedure validation_accepts_plsql_only;

  --%test(An error inside a PL/SQL step surfaces as the PL/SQL step error code)
  procedure error_surfaces;

end test_uc_ai_agent_plsql_step;
/
