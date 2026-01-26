create or replace package body test_uc_ai_agent_workflow as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  gc_seq_workflow_code  constant varchar2(50 char) := 'TEST_SEQ_WORKFLOW';
  gc_loop_workflow_code constant varchar2(50 char) := 'TEST_LOOP_WORKFLOW';
  gc_step1_agent_code   constant varchar2(50 char) := 'TEST_WF_STEP1';
  gc_step2_agent_code   constant varchar2(50 char) := 'TEST_WF_STEP2';
  gc_haiku_creator_agent_code constant varchar2(50 char) := 'TEST_WF_HAIKU_CREATOR';
  gc_haiku_rater_agent_code constant varchar2(50 char) := 'TEST_WF_HAIKU_RATER';
  gc_haiku_improver_agent_code constant varchar2(50 char) := 'TEST_WF_HAIKU_IMPROVER';
  gc_haiku_translator_agent_code constant varchar2(50 char) := 'TEST_WF_HAIKU_TRANSLATOR';

  procedure setup
  as
    l_id number;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Create required prompt profiles
    uc_ai_test_agent_utils.create_profiles;
    delete from uc_ai_agents
     where code in (
       gc_step1_agent_code,
       gc_step2_agent_code,
       gc_haiku_creator_agent_code,
       gc_haiku_rater_agent_code,
       gc_haiku_improver_agent_code,
       gc_haiku_translator_agent_code
     );

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
          "agent_code": "' || gc_step1_agent_code || '",
          "input_mapping": {
            "question": "$.input.question"
          },
          "output_key": "step1_result"
        },
        {
          "agent_code": "' || gc_step2_agent_code || '",
          "input_mapping": {
            "text": "$.steps.step1_result"
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

    ut.expect(l_workflow_id).to_be_not_null();

    -- Execute the workflow
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_seq_workflow_code,
      p_input_parameters => json_object_t('{"question": "What is 7 + 8?"}'),
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

    SELECT JSON_ARRAYAGG(JSON_OBJECT(*)) AS json_data 
      into l_agent_data 
      from uc_ai_agent_executions 
     where session_id = l_session_id;

    sys.dbms_output.put_line('Agent execution data: ' || json_serialize(l_agent_data));
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
              "expression": "case when '{$.steps.haiku_rating.rating_feedback}' is not null then 'Improve this haiku about {$.input.topic}. Use this feedback: {$.steps.haiku_rating.rating_feedback}. Haiku: {$.steps.haiku_result}' else '{$.input.topic}' end",
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
    l_workflow_id := uc_ai_agents_api.create_agent(
      p_code                => gc_loop_workflow_code,
      p_description         => 'Test loop workflow',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => l_workflow_def,
      p_max_iterations      => 3,
      p_status              => uc_ai_agents_api.c_status_active
    );

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
    l_workflow_id := uc_ai_agents_api.create_agent(
      p_code                => gc_loop_workflow_code,
      p_description         => 'Test loop workflow',
      p_agent_type          => uc_ai_agents_api.c_type_workflow,
      p_workflow_definition => l_workflow_def,
      p_max_iterations      => 3,
      p_status              => uc_ai_agents_api.c_status_active
    );

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
  end execute_loop_workflow_better;

end test_uc_ai_agent_workflow;
/
