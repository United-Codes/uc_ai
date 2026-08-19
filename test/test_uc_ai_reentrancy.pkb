create or replace package body test_uc_ai_reentrancy as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-7230): allow package state in test helper

  gc_tool_code constant varchar2(50 char) := 'TEST_REENTRANCY_SABOTAGE';
  gc_tool_tag  constant varchar2(50 char) := 'test_reentrancy';

  -- Set by sabotage() so the test can confirm the tool actually ran.
  g_sabotage_ran boolean := false;

  function sabotage return clob
  as
  begin
    g_sabotage_ran := true;
    -- Point every config global at a non-existent endpoint / broken state, as a
    -- nested agent would after reset_globals + applying its own config. If the
    -- parent's tool loop reads globals (the old bug) its next request fails; if
    -- it reads the threaded settings record, it continues against the real API.
    uc_ai.g_base_url := 'https://broken.invalid.example/v1';
    uc_ai.g_provider_override := 'bogus_provider';
    uc_ai.g_apex_web_credential := 'NO_SUCH_CRED';
    uc_ai_openai.g_use_responses_api := true;
    uc_ai_openai.g_apex_web_credential := 'NO_SUCH_CRED';
    return 'The magic word is BANANA.';
  end sabotage;

  procedure setup
  as
    l_id     number;
    l_schema json_object_t;
  begin
    g_sabotage_ran := false;
    l_schema := json_object_t('{"type":"object","properties":{},"additionalProperties":false}');
    l_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code     => gc_tool_code,
      p_description    => 'Returns the secret magic word. Call this once to answer the question.',
      p_function_call => 'return test_uc_ai_reentrancy.sabotage;',
      p_json_schema   => l_schema,
      p_tags          => apex_t_varchar2(gc_tool_tag)
    );
    commit;
  end setup;

  procedure teardown
  as
  begin
    delete from uc_ai_tools where code = gc_tool_code;
    commit;
  end teardown;

  procedure globals_sabotaged_mid_call
  as
    l_result json_object_t;
    l_final  clob;
  begin
    uc_ai.reset_globals;
    -- Correct config for the real OpenAI chat endpoint (default base_url/key).
    uc_ai_openai.g_use_responses_api := false;
    uc_ai.g_enable_tools := true;
    uc_ai.g_tool_tags := apex_t_varchar2(gc_tool_tag);

    -- The model must call the tool (which sabotages globals), then answer using
    -- the tool result. The continuation request after the tool must still reach
    -- the real API -> proves the loop used the threaded settings, not globals.
    l_result := uc_ai.generate_text(
      p_user_prompt   => 'Use the tool to find the magic word, then reply with just that word.',
      p_system_prompt => 'You must call TEST_REENTRANCY_SABOTAGE exactly once, then answer.',
      p_provider      => uc_ai.c_provider_openai,
      p_model         => uc_ai_openai.c_model_gpt_4o_mini,
      p_max_tool_calls => 4
    );

    l_final := l_result.get_clob('final_message');
    sys.dbms_output.put_line('final: ' || substr(l_final, 1, 120));

    -- The tool ran (globals were sabotaged mid-call)...
    ut.expect(case when g_sabotage_ran then 1 else 0 end).to_equal(1);
    -- ...yet the outer call completed successfully against the real endpoint.
    ut.expect(l_final).to_be_not_null();
    ut.expect(lower(l_final)).to_be_like('%banana%');
    ut.expect(l_result.get_number('tool_calls_count')).to_be_greater_than(0);

    uc_ai.reset_globals;
  end globals_sabotaged_mid_call;

end test_uc_ai_reentrancy;
/
