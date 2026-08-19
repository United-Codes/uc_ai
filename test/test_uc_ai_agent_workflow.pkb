create or replace package body test_uc_ai_agent_workflow as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  gc_seq_workflow_code  constant varchar2(50 char) := 'TEST_SEQ_WORKFLOW';
  gc_loop_workflow_code constant varchar2(50 char) := 'TEST_LOOP_WORKFLOW';
  gc_cond_workflow_code constant varchar2(50 char) := 'TEST_COND_WORKFLOW';
  gc_cond_geo_agent_code constant varchar2(50 char) := 'TEST_WF_COND_GEO';
  gc_cond_sum_agent_code constant varchar2(50 char) := 'TEST_WF_COND_SUM';
  gc_step1_agent_code   constant varchar2(50 char) := 'TEST_WF_STEP1';
  gc_step2_agent_code   constant varchar2(50 char) := 'TEST_WF_STEP2';
  gc_haiku_creator_agent_code constant varchar2(50 char) := 'TEST_WF_HAIKU_CREATOR';
  gc_haiku_rater_agent_code constant varchar2(50 char) := 'TEST_WF_HAIKU_RATER';
  gc_haiku_improver_agent_code constant varchar2(50 char) := 'TEST_WF_HAIKU_IMPROVER';
  gc_haiku_translator_agent_code constant varchar2(50 char) := 'TEST_WF_HAIKU_TRANSLATOR';

  /*
   * Deterministic telemetry checks for a finished workflow run. A workflow
   * agent is a wrapper that delegates every LLM call to its step sub-agents
   * (each run with parent_execution_id set to the wrapper), so:
   *   - exactly one session header + one top-level turn (the wrapper)
   *   - the wrapper itself spends no tokens (no direct generate_text call)
   *   - step agents run as nested children, sharing the session, no turn_index
   *   - session token totals equal the SUM of every execution's own tokens
   * The wrapper result carries only a final_message (no structured messages
   * array), so the message log holds the final step's output as an assistant
   * row - attributed (via agent_code) to the workflow agent - or nothing at
   * all when every step was skipped.
   *   p_expect_children  false for the all-steps-skipped case (no child runs,
   *                      no LLM spend, empty message log)
   */
  procedure validate_workflow_telemetry(
    p_session_id      in varchar2,
    p_test_name       in varchar2,
    p_expect_children in boolean default true
  )
  as
    l_count         number;
    l_turn_count    number;
    l_status_hdr    varchar2(50 char);
    l_top_index     number;
    l_top_status    varchar2(50 char);
    l_top_output    clob;
    l_wrapper_in    number;
    l_wrapper_out   number;
    l_child_count   number;
    l_bad_child_idx number;
    l_bad_child_sid number;
    l_child_in      number;
    l_sess_in       number;
    l_sess_out      number;
    l_exec_in       number;
    l_exec_out      number;
    l_msg_rows      number;
    l_hdr_msg       number;
    l_bad_attr      number;
    l_min_seq       number;
    l_max_seq       number;
    l_uniq_seq      number;
  begin
    -- One session header, completed, exactly one workflow turn.
    select count(*) into l_count
      from uc_ai_agent_sessions where session_id = p_session_id;
    ut.expect(l_count, p_test_name || ': one session header').to_equal(1);

    select turn_count, status, total_input_tokens, total_output_tokens
      into l_turn_count, l_status_hdr, l_sess_in, l_sess_out
      from uc_ai_agent_sessions where session_id = p_session_id;
    ut.expect(l_turn_count, p_test_name || ': single workflow turn').to_equal(1);
    ut.expect(l_status_hdr, p_test_name || ': session completed').to_equal(uc_ai_agents_api.c_exec_completed);

    -- Top-level workflow wrapper: turn 1, completed, stored state, no own spend.
    select turn_index, status, output_result, total_input_tokens, total_output_tokens
      into l_top_index, l_top_status, l_top_output, l_wrapper_in, l_wrapper_out
      from uc_ai_agent_executions
     where session_id = p_session_id and parent_execution_id is null;
    ut.expect(l_top_index, p_test_name || ': wrapper is turn 1').to_equal(1);
    ut.expect(l_top_status, p_test_name || ': wrapper completed').to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_top_output is not null, p_test_name || ': wrapper stored an output_result').to_be_true();
    ut.expect(l_wrapper_in, p_test_name || ': wrapper spent no input tokens itself').to_equal(0);
    ut.expect(l_wrapper_out, p_test_name || ': wrapper spent no output tokens itself').to_equal(0);

    -- Step sub-agents: nested children, same session, no turn_index.
    select count(*),
           count(case when turn_index is not null then 1 end),
           count(case when session_id <> p_session_id then 1 end),
           nvl(sum(total_input_tokens), 0)
      into l_child_count, l_bad_child_idx, l_bad_child_sid, l_child_in
      from uc_ai_agent_executions
     where parent_execution_id is not null and session_id = p_session_id;
    ut.expect(l_bad_child_idx, p_test_name || ': nested executions carry no turn_index').to_equal(0);
    ut.expect(l_bad_child_sid, p_test_name || ': nested executions share the session_id').to_equal(0);

    -- Every step child parents the top-level workflow wrapper.
    select count(*) into l_count
      from uc_ai_agent_executions c
     where c.session_id = p_session_id
       and c.parent_execution_id is not null
       and not exists (
             select 1 from uc_ai_agent_executions p
              where p.id = c.parent_execution_id
                and p.session_id = c.session_id
                and p.parent_execution_id is null);
    ut.expect(l_count, p_test_name || ': every step child parents the workflow wrapper').to_equal(0);

    -- Every execution finished cleanly with consistent timestamps.
    select count(*) into l_count
      from uc_ai_agent_executions
     where session_id = p_session_id
       and (status <> uc_ai_agents_api.c_exec_completed or completed_at is null
            or started_at is null or completed_at < started_at);
    ut.expect(l_count, p_test_name || ': all executions completed with valid timestamps').to_equal(0);

    -- Session token totals reconcile with the SUM over executions.
    select nvl(sum(total_input_tokens), 0), nvl(sum(total_output_tokens), 0)
      into l_exec_in, l_exec_out
      from uc_ai_agent_executions where session_id = p_session_id;
    ut.expect(l_sess_in, p_test_name || ': session input = SUM of execution own tokens').to_equal(l_exec_in);
    ut.expect(l_sess_out, p_test_name || ': session output = SUM of execution own tokens').to_equal(l_exec_out);

    -- Message log: header count matches actual rows.
    select count(*), min(seq), max(seq), count(distinct seq)
      into l_msg_rows, l_min_seq, l_max_seq, l_uniq_seq
      from uc_ai_agent_messages where session_id = p_session_id;
    select message_count into l_hdr_msg
      from uc_ai_agent_sessions where session_id = p_session_id;
    ut.expect(l_hdr_msg, p_test_name || ': header message_count matches persisted rows').to_equal(l_msg_rows);

    if p_expect_children then
      ut.expect(l_child_count, p_test_name || ': workflow spawned step sub-agents').to_be_greater_than(0);
      ut.expect(l_child_in, p_test_name || ': step agents recorded their own input tokens').to_be_greater_than(0);
      ut.expect(l_sess_in, p_test_name || ': workflow spent input tokens').to_be_greater_than(0);
      ut.expect(l_msg_rows, p_test_name || ': final workflow message persisted').to_be_greater_than(0);
      ut.expect(l_uniq_seq, p_test_name || ': seq values are unique').to_equal(l_msg_rows);
      ut.expect(l_min_seq, p_test_name || ': seq starts at 1').to_equal(1);
      ut.expect(l_max_seq, p_test_name || ': seq ends at message count').to_equal(l_msg_rows);

      -- The persisted assistant row is attributed to a session agent.
      select count(*) into l_bad_attr
        from uc_ai_agent_messages m
       where m.session_id = p_session_id
         and (m.agent_code is null
              or not exists (
                    select 1
                      from uc_ai_agent_executions e
                      join uc_ai_agents a on a.id = e.agent_id
                     where e.session_id = p_session_id
                       and a.code = m.agent_code));
      ut.expect(l_bad_attr, p_test_name || ': workflow message attributed to a session agent').to_equal(0);
    else
      -- Every step was skipped: no child runs, no LLM spend, empty message log.
      ut.expect(l_child_count, p_test_name || ': no step ran, so no child executions').to_equal(0);
      ut.expect(l_sess_in, p_test_name || ': no LLM calls, zero input tokens').to_equal(0);
      ut.expect(l_sess_out, p_test_name || ': no LLM calls, zero output tokens').to_equal(0);
      ut.expect(l_msg_rows, p_test_name || ': no final message, empty message log').to_equal(0);
    end if;
  end validate_workflow_telemetry;

  procedure setup
  as
    l_id number;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Create required prompt profiles
    uc_ai_test_agent_utils.create_profiles;
    -- workflow agents first: their executions are parents of the step agents' executions
    uc_ai_test_agent_utils.delete_agents_cascade(gc_seq_workflow_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_loop_workflow_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_cond_workflow_code);
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_COND_WF_INVALID');
    uc_ai_test_agent_utils.delete_agents_cascade(gc_step1_agent_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_step2_agent_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_haiku_creator_agent_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_haiku_rater_agent_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_haiku_improver_agent_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_haiku_translator_agent_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_cond_geo_agent_code);
    uc_ai_test_agent_utils.delete_agents_cascade(gc_cond_sum_agent_code);

    -- Create step 1 profile agent (math)
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_step1_agent_code,
      p_description         => 'Workflow step 1 - math calculation',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_MATH',
      p_status              => uc_ai_agents_api.c_status_active
    );

    -- Create step 2 profile agent (summarizer)
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_step2_agent_code,
      p_description         => 'Workflow step 2 - summarize',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_SUM',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_haiku_creator_agent_code,
      p_description         => 'Haiku creator agent',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_HAIKU_CREATOR',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_haiku_rater_agent_code,
      p_description         => 'Haiku rater agent',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_HAIKU_RATER',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_haiku_improver_agent_code,
      p_description         => 'Haiku improver agent',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_HAIKU_IMPROVER',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_haiku_translator_agent_code,
      p_description         => 'Haiku translator agent',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_HAIKU_TRANSLATOR',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_cond_geo_agent_code,
      p_description         => 'Conditional workflow step - geography',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_GEO',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_cond_sum_agent_code,
      p_description         => 'Conditional workflow step - summarizer',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_SUM',
      p_status              => uc_ai_agents_api.c_status_active
    );

    commit; -- agents must be committed before execution (autonomous telemetry)
  end setup;

  procedure teardown
  as
  begin
    null;
    --uc_ai_test_agent_utils.cleanup_test_data;
  end teardown;

  procedure execute_sequential_workflow
  as
    l_workflow_id number;
    l_session_id  varchar2(100 char);
    l_result      json_object_t;
    l_final_msg   clob;
    l_status      varchar2(50 char);
    l_exec_count  number;
    l_workflow_def clob;
    l_agent_data json;
  begin
    -- Create sequential workflow definition
    l_workflow_def := '{
      "workflow_type": "sequential",
      "steps": [
        {
          "agent_code": "' || gc_haiku_creator_agent_code || '",
          "input_mapping": {
            "topic": "{$.input.topic}"
          },
          "output_key": "step1_result"
        },
        {
          "agent_code": "' || gc_haiku_translator_agent_code || '",
          "input_mapping": {
            "haiku": "{$.steps.step1_result}",
            "language": "{$.input.language}"
          },
          "output_key": "step2_result"
        }
      ]
    }';

    -- Create the workflow agent
    l_workflow_id := uc_ai_agents_api.create_agent(
      p_code                => gc_seq_workflow_code,
      p_description         => 'Test sequential workflow',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => l_workflow_def,
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;

    ut.expect(l_workflow_id).to_be_not_null();

    -- Execute the workflow
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_seq_workflow_code,
      p_input_parameters => json_object_t('{"topic": "Nature", "language": "french"}'),
      p_session_id       => l_session_id
    );

    sys.dbms_output.put_line('Workflow result JSON: ' || l_result.to_clob);

    -- Validate result
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Sequential Workflow');

    l_status := l_result.get_string('status');
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Sequential workflow result: ' || l_final_msg);
    ut.expect(l_final_msg).to_be_not_null();

    -- Check multiple executions were recorded (workflow + steps)
    select count(*) into l_exec_count
      from uc_ai_agent_executions
     where session_id = l_session_id;

    ut.expect(l_exec_count, 'Should have recorded multiple executions').to_be_greater_than(1);

    -- Child executions must share the caller context captured at the top level
    declare
      l_distinct_created_by number;
      l_child_count         number;
    begin
      select count(distinct e.created_by), count(c.id)
        into l_distinct_created_by, l_child_count
        from uc_ai_agent_executions e
        left join uc_ai_agent_executions c
          on c.parent_execution_id = e.id
       where e.session_id = l_session_id;

      ut.expect(l_child_count, 'Should have child executions').to_be_greater_than(0);
      ut.expect(l_distinct_created_by, 'All executions should share the caller''s created_by').to_equal(1);
    end;

    validate_workflow_telemetry(l_session_id, 'Sequential workflow');
  end execute_sequential_workflow;

  procedure execute_loop_workflow
  as
    l_workflow_id  number;
    l_session_id   varchar2(100 char);
    l_result       json_object_t;
    l_final_msg    clob;
    l_status       varchar2(50 char);
    l_workflow_def clob;
  begin
    -- Create loop workflow definition (runs max 3 iterations)
    l_workflow_def := q'#{
      "workflow_type": "loop",
      "steps": [
        {
          "agent_code": "#' || gc_haiku_creator_agent_code || q'#",
          "input_mapping": {
            "topic": {
              "expression": "case when '{$.steps.haiku_rating.feedback}' is not null then 'Improve this haiku about {$.input.topic}. Use this feedback: {$.steps.haiku_rating.feedback}. Haiku: {$.steps.haiku_result}' else '{$.input.topic}' end",
              "is_plsql_expression": true
            }
          },
          "output_key": "haiku_result"
        },
        {
          "agent_code": "#' || gc_haiku_rater_agent_code || q'#",
          "input_mapping": {
            "haiku": "{$.steps.haiku_result}",
            "topic": "{$.input.topic}"
          },
          "output_key": "haiku_rating"
        }
      ],
      "loop_config": {
        "max_iterations": 3,
        "exit_condition": "{$.steps.haiku_rating.quality} >= 8"
      },
      "final_message": "{$.steps.haiku_result}"
    }#';

    -- Create the loop workflow agent
    uc_ai_test_agent_utils.delete_agents_cascade(gc_loop_workflow_code);
    l_workflow_id := uc_ai_agents_api.create_agent(
      p_code                => gc_loop_workflow_code,
      p_description         => 'Test loop workflow',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => l_workflow_def,
      p_max_iterations      => 3,
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;

    ut.expect(l_workflow_id).to_be_not_null();

    -- Execute the loop workflow
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_loop_workflow_code,
      p_input_parameters => json_object_t('{"topic": "Star Wars"}'),
      p_session_id       => l_session_id
    );

    -- Dumping the whole result (with every per-iteration state snapshot) can
    -- overwhelm the utPLSQL reporter, so only log a bounded slice.
    sys.dbms_output.put_line('Loop Workflow result JSON (truncated): ' || substr(l_result.to_clob, 1, 2000));

    -- Validate result
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Loop Workflow');

    l_status := l_result.get_string('status');
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Loop workflow result: ' || l_final_msg);
    ut.expect(l_final_msg).to_be_not_null();

    -- _loop_iterations counts FULLY completed iterations; the loop checks its
    -- exit condition after each step, so an early exit (the first haiku already
    -- rates >= 8) legitimately leaves the counter at 0 while still having done
    -- real work. Only bound it by the cap here - that the step agents actually
    -- ran is asserted via the child executions in validate_workflow_telemetry.
    ut.expect(l_result.get_number('_loop_iterations'), 'Loop respected its max iteration cap').to_be_less_or_equal(3);

    validate_workflow_telemetry(l_session_id, 'Loop workflow');
  end execute_loop_workflow;


  procedure execute_loop_workflow_better
  as
    l_workflow_id  number;
    l_session_id   varchar2(100 char);
    l_result       json_object_t;
    l_final_msg    clob;
    l_status       varchar2(50 char);
    l_workflow_def clob;
  begin
    -- Create loop workflow definition (runs max 3 iterations)
    l_workflow_def := q'#{
      "workflow_type": "loop",
      "pre_steps": [
        {
          "agent_code": "#' || gc_haiku_creator_agent_code || q'#",
          "input_mapping": {
            "topic": "{$.input.topic}"
          },
          "output_key": "current_haiku"
        }
      ],
      "steps": [
       {
          "agent_code": "#' || gc_haiku_rater_agent_code || q'#",
          "input_mapping": {
            "haiku": "{$.steps.current_haiku}",
            "topic": "{$.input.topic}"
          },
          "output_key": "haiku_rating"
        },
        {
          "agent_code": "#' || gc_haiku_improver_agent_code || q'#",
          "input_mapping": {
            "topic": "{$.input.topic}",
            "feedback": "{$.steps.haiku_rating.rating_feedback}",
            "haiku": "{$.steps.current_haiku}"
          },
          "output_key": "current_haiku"
        }
      ],
      "post_steps": [
        {
          "agent_code": "#' || gc_haiku_translator_agent_code || q'#",
          "input_mapping": {
            "language": "german",
            "haiku": "{$.steps.current_haiku}"
          },
          "output_key": "translated_haiku"
        }
      ],
      "loop_config": {
        "max_iterations": 3,
        "exit_condition": "{$.steps.haiku_rating.quality} >= 8"
      },
      "final_message": "{$.steps.translated_haiku}"
    }#';

    -- Create the loop workflow agent
    uc_ai_test_agent_utils.delete_agents_cascade(gc_loop_workflow_code);
    l_workflow_id := uc_ai_agents_api.create_agent(
      p_code                => gc_loop_workflow_code,
      p_description         => 'Test loop workflow',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => l_workflow_def,
      p_max_iterations      => 3,
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;

    ut.expect(l_workflow_id).to_be_not_null();

    -- Execute the loop workflow
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_loop_workflow_code,
      p_input_parameters => json_object_t('{"topic": "Star Wars"}'),
      p_session_id       => l_session_id
    );

    sys.dbms_output.put_line('Loop Workflow result JSON: ' || l_result.to_clob);

    -- Validate result
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Loop Workflow');

    l_status := l_result.get_string('status');
    ut.expect(l_status).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Loop workflow result: ' || l_final_msg);
    ut.expect(l_final_msg).to_be_not_null();

    -- one snapshot per completed loop iteration (guards against JSON DOM reference aliasing)
    ut.expect(l_result.has('_loop_iteration_state')).to_be_true();
    ut.expect(l_result.get_array('_loop_iteration_state').get_size).to_equal(l_result.get_number('_loop_iterations'));

    validate_workflow_telemetry(l_session_id, 'Loop workflow (pre/post steps)');
  end execute_loop_workflow_better;


  /*
   * Creates the conditional workflow agent used by the conditional tests.
   * Exactly one of the two steps should run depending on input.category.
   */
  procedure create_conditional_workflow
  as
    l_workflow_id  number;
    l_workflow_def clob;
  begin
    uc_ai_test_agent_utils.delete_agents_cascade(gc_cond_workflow_code);

    l_workflow_def := q'#{
      "workflow_type": "conditional",
      "steps": [
        {
          "agent_code": "#' || gc_cond_geo_agent_code || q'#",
          "condition": "'{$.input.category}' = 'geography'",
          "input_mapping": {
            "question": "{$.input.text}"
          },
          "output_key": "geo_result"
        },
        {
          "agent_code": "#' || gc_cond_sum_agent_code || q'#",
          "condition": "'{$.input.category}' = 'summary'",
          "input_mapping": {
            "text": "{$.input.text}"
          },
          "output_key": "sum_result"
        }
      ]
    }#';

    l_workflow_id := uc_ai_agents_api.create_agent(
      p_code                => gc_cond_workflow_code,
      p_description         => 'Test conditional workflow',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => l_workflow_def,
      p_status              => uc_ai_agents_api.c_status_active
    );
    commit;

    ut.expect(l_workflow_id).to_be_not_null();
  end create_conditional_workflow;


  procedure execute_conditional_workflow
  as
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_steps      json_object_t;
    l_final_msg  clob;
  begin
    create_conditional_workflow;

    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_cond_workflow_code,
      p_input_parameters => json_object_t('{"category": "geography", "text": "What is the capital of France?"}'),
      p_session_id       => l_session_id
    );

    sys.dbms_output.put_line('Conditional workflow result JSON: ' || l_result.to_clob);

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Conditional Workflow');

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    -- Only the geography step must have run
    ut.expect(l_result.get_number('_workflow_iterations'), 'Exactly one step should have executed').to_equal(1);

    l_steps := l_result.get_object('steps');
    ut.expect(l_steps.has('geo_result'), 'Matching step (geo) should have run').to_be_true();
    ut.expect(l_steps.has('sum_result'), 'Non-matching step (sum) should have been skipped').to_be_false();

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Conditional workflow result: ' || l_final_msg);
    ut.expect(l_final_msg).to_be_not_null();

    -- Exactly one step ran, so exactly one child execution under the wrapper.
    validate_workflow_telemetry(l_session_id, 'Conditional workflow');
  end execute_conditional_workflow;


  procedure conditional_workflow_all_skipped
  as
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_steps      json_object_t;
  begin
    create_conditional_workflow;

    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_cond_workflow_code,
      p_input_parameters => json_object_t('{"category": "nomatch", "text": "hello"}'),
      p_session_id       => l_session_id
    );

    sys.dbms_output.put_line('All-skipped workflow result JSON: ' || l_result.to_clob);

    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_result.get_number('_workflow_iterations'), 'No step should have executed').to_equal(0);

    l_steps := l_result.get_object('steps');
    ut.expect(l_steps.has('geo_result'), 'Geo step should have been skipped').to_be_false();
    ut.expect(l_steps.has('sum_result'), 'Sum step should have been skipped').to_be_false();

    -- No step ran, so there is no final message
    ut.expect(l_result.get_clob('final_message')).to_be_null();

    -- Telemetry for a no-op run: the wrapper turn is still recorded, but there
    -- are no child executions, no token spend, and an empty message log.
    validate_workflow_telemetry(l_session_id, 'All-skipped workflow', p_expect_children => false);
  end conditional_workflow_all_skipped;


  procedure conditional_rejects_object_cond
  as
    l_workflow_id  number;
    l_workflow_def clob;
  begin
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_COND_WF_INVALID');

    -- condition as object was never supported and used to be silently ignored;
    -- create_agent must reject it
    l_workflow_def := q'#{
      "workflow_type": "conditional",
      "steps": [
        {
          "agent_code": "#' || gc_cond_geo_agent_code || q'#",
          "condition": {
            "type": "plsql",
            "expression": "'{$.input.category}' = 'geography'"
          },
          "input_mapping": {
            "question": "{$.input.text}"
          },
          "output_key": "geo_result"
        }
      ]
    }#';

    begin
      l_workflow_id := uc_ai_agents_api.create_agent(
        p_code                => 'TEST_COND_WF_INVALID',
        p_description         => 'Conditional workflow with invalid object condition',
        p_agent_type          => uc_ai_agents_api.c_type_workflow,
        p_workflow_definition => l_workflow_def,
        p_status              => uc_ai_agents_api.c_status_active
      );
      ut.fail('create_agent should have rejected a non-string condition');
    exception
      when others then
        ut.expect(sqlcode, 'Should raise invalid config error').to_equal(-20503);
    end;
  end conditional_rejects_object_cond;

end test_uc_ai_agent_workflow;
/
