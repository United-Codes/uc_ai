create or replace package body test_uc_ai_agent_handoff as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  gc_handoff_code  constant varchar2(50 char) := 'TEST_HANDOFF';
  gc_capped_code   constant varchar2(50 char) := 'TEST_HANDOFF_CAPPED';
  gc_triage_code   constant varchar2(50 char) := 'TEST_HANDOFF_TRIAGE';
  gc_product_code  constant varchar2(50 char) := 'TEST_HANDOFF_PRODUCT';
  gc_shipping_code constant varchar2(50 char) := 'TEST_HANDOFF_SHIPPING';
  gc_customer_code constant varchar2(50 char) := 'TEST_HANDOFF_CUSTOMER';

  /*
   * Handoff config: full mesh minus self. Triage is listed as a target too so
   * specialists can transfer back to it.
   */
  function handoff_config(
    p_max_handoffs in number
  ) return clob
  as
  begin
    return '{
      "pattern_type": "handoff",
      "initial_agent_code": "' || gc_triage_code || '",
      "handoff_agents": [
        {"agent_code": "' || gc_triage_code || '", "description": "Triage and general support - transfer back for questions outside your specialty"},
        {"agent_code": "' || gc_product_code || '", "description": "Product details: specs, prices, availability of catalog products"},
        {"agent_code": "' || gc_shipping_code || '", "description": "Shipping: options, costs, delivery times"},
        {"agent_code": "' || gc_customer_code || '", "description": "Customer accounts: membership, orders, order status"}
      ],
      "max_handoffs": ' || p_max_handoffs || '
    }';
  end handoff_config;

  procedure setup
  as
    l_id number;
  begin
    uc_ai.g_enable_tools := false;
    uc_ai.g_enable_reasoning := false;

    -- Fresh start: remove leftovers from earlier runs
    uc_ai_test_agent_utils.delete_agents_cascade('TEST_HANDOFF%');

    -- Create the customer-support prompt profiles (+ product lookup tool)
    uc_ai_test_agent_utils.create_support_profiles;

    -- Specialist profile agents
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_triage_code,
      p_description         => 'Shop support triage agent',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_CS_TRIAGE',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_product_code,
      p_description         => 'Product details specialist',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_CS_PRODUCT',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_shipping_code,
      p_description         => 'Shipping specialist',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_CS_SHIPPING',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_customer_code,
      p_description         => 'Customer account specialist',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_CS_CUSTOMER',
      p_status              => uc_ai_agents_api.c_status_active
    );

    -- The handoff agent (single point of entry)
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_handoff_code,
      p_description          => 'Customer support handoff agent',
      p_agent_type           => uc_ai_agents_api.c_type_handoff,
      p_orchestration_config => handoff_config(p_max_handoffs => 3),
      p_status               => uc_ai_agents_api.c_status_active
    );

    commit; -- agents must be committed before execution (autonomous telemetry)
  end setup;

  procedure teardown
  as
  begin
    uc_ai_test_agent_utils.cleanup_test_data;
    commit;
  end teardown;

  procedure route_product_question
  as
    l_session_id     varchar2(100 char);
    l_result         json_object_t;
    l_final_msg      clob;
    l_wrapper_exec   number;
    l_count          number;
    l_wrapper_in     number;
    l_wrapper_out    number;
    l_sess_in        number;
    l_sess_out       number;
    l_exec_sum_in    number;
    l_exec_sum_out   number;
    l_turn_count     number;
  begin
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_handoff_code,
      p_input_parameters => json_object_t('{"prompt": "How much does the Aurora Desk Lamp weigh?"}'),
      p_session_id       => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Route product question');
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Product routing result: ' || l_final_msg);

    -- Only the product specialist's tool knows the weight
    ut.expect(l_final_msg, 'Answer should contain the catalog weight').to_be_like('%2.5%');

    ut.expect(l_result.get_number('handoff_count'), 'Exactly one handoff').to_equal(1);
    ut.expect(l_result.get_string('final_agent_code')).to_equal(gc_product_code);
    ut.expect(l_result.get_boolean('max_handoffs_reached')).to_be_false();

    -- Execution hierarchy: 1 top-level wrapper + 2 children (triage, product)
    l_wrapper_exec := l_result.get_number('execution_id');

    select count(*)
      into l_count
      from uc_ai_agent_executions
     where session_id = l_session_id
       and parent_execution_id is null;
    ut.expect(l_count, 'One top-level execution').to_equal(1);

    select count(*)
      into l_count
      from uc_ai_agent_executions
     where session_id = l_session_id
       and parent_execution_id = l_wrapper_exec;
    ut.expect(l_count, 'Two child executions (triage + product)').to_equal(2);

    -- The wrapper made no LLM calls itself: its own token totals stay 0
    select total_input_tokens, total_output_tokens
      into l_wrapper_in, l_wrapper_out
      from uc_ai_agent_executions
     where id = l_wrapper_exec;
    ut.expect(l_wrapper_in, 'Wrapper input tokens').to_equal(0);
    ut.expect(l_wrapper_out, 'Wrapper output tokens').to_equal(0);

    -- Session header: one turn, tokens = sum over the executions
    select turn_count, total_input_tokens, total_output_tokens
      into l_turn_count, l_sess_in, l_sess_out
      from uc_ai_agent_sessions
     where session_id = l_session_id;
    ut.expect(l_turn_count, 'One conversation turn').to_equal(1);

    select sum(total_input_tokens), sum(total_output_tokens)
      into l_exec_sum_in, l_exec_sum_out
      from uc_ai_agent_executions
     where session_id = l_session_id;
    ut.expect(l_sess_in, 'Session input tokens = sum over executions').to_equal(l_exec_sum_in);
    ut.expect(l_sess_out, 'Session output tokens = sum over executions').to_equal(l_exec_sum_out);
    ut.expect(l_sess_in, 'Children spent tokens').to_be_greater_than(0);

    -- Message log: the transfer tool call and the product lookup are recorded
    select count(*)
      into l_count
      from uc_ai_agent_messages
     where session_id = l_session_id
       and role = 'tool_call'
       and tool_name like 'transfer_to_' || lower(gc_product_code) || '%';
    ut.expect(l_count, 'Transfer tool call persisted in message log').to_be_greater_than(0);

    select count(*)
      into l_count
      from uc_ai_agent_messages
     where session_id = l_session_id
       and role = 'tool_call'
       and tool_name = 'TEST_PRODUCT_TOOL';
    ut.expect(l_count, 'Product lookup tool call persisted in message log').to_be_greater_than(0);
  end route_product_question;

  procedure route_shipping_question
  as
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_final_msg  clob;
  begin
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_handoff_code,
      p_input_parameters => json_object_t('{"prompt": "How fast is your fastest shipping option and what does it cost?"}'),
      p_session_id       => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Route shipping question');
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Shipping routing result: ' || l_final_msg);

    -- Only the shipping specialist knows the express price
    ut.expect(l_final_msg, 'Answer should contain the express price').to_be_like('%19.99%');
    ut.expect(l_result.get_number('handoff_count'), 'Exactly one handoff').to_equal(1);
    ut.expect(l_result.get_string('final_agent_code')).to_equal(gc_shipping_code);
  end route_shipping_question;

  procedure route_customer_question
  as
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_final_msg  clob;
  begin
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_handoff_code,
      p_input_parameters => json_object_t('{"prompt": "Since which year is customer 1001 a premium member?"}'),
      p_session_id       => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Route customer question');
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Customer routing result: ' || l_final_msg);

    -- Only the customer specialist knows the membership year
    ut.expect(l_final_msg, 'Answer should contain the membership year').to_be_like('%2021%');
    ut.expect(l_result.get_number('handoff_count'), 'Exactly one handoff').to_equal(1);
    ut.expect(l_result.get_string('final_agent_code')).to_equal(gc_customer_code);
  end route_customer_question;

  procedure direct_answer_no_handoff
  as
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_count      number;
  begin
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_handoff_code,
      p_input_parameters => json_object_t('{"prompt": "Hello! Have a great day!"}'),
      p_session_id       => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Direct answer');
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    sys.dbms_output.put_line('Direct answer result: ' || l_result.get_clob('final_message'));

    ut.expect(l_result.get_number('handoff_count'), 'No handoff for a greeting').to_equal(0);
    ut.expect(l_result.get_string('final_agent_code')).to_equal(gc_triage_code);

    -- Only the triage child ran
    select count(*)
      into l_count
      from uc_ai_agent_executions
     where session_id = l_session_id
       and parent_execution_id is not null;
    ut.expect(l_count, 'Exactly one child execution').to_equal(1);

    -- No transfer tool was called
    select count(*)
      into l_count
      from uc_ai_agent_messages
     where session_id = l_session_id
       and role = 'tool_call'
       and tool_name like 'transfer_to_%';
    ut.expect(l_count, 'No transfer tool calls in message log').to_equal(0);
  end direct_answer_no_handoff;

  procedure max_handoffs_guard
  as
    l_id         number;
    l_session_id varchar2(100 char);
    l_result     json_object_t;
  begin
    -- Same mesh but capped at a single handoff: after triage transfers, the
    -- specialist runs WITHOUT transfer tools and must answer.
    uc_ai_test_agent_utils.delete_agents_cascade(gc_capped_code);
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_capped_code,
      p_description          => 'Handoff agent capped at one handoff',
      p_agent_type           => uc_ai_agents_api.c_type_handoff,
      p_orchestration_config => handoff_config(p_max_handoffs => 1),
      p_status               => uc_ai_agents_api.c_status_active
    );
    commit;

    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_capped_code,
      p_input_parameters => json_object_t('{"prompt": "How much does the Aurora Desk Lamp weigh?"}'),
      p_session_id       => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Max handoffs guard');
    ut.expect(l_result.get_string('status'), 'Completes without error at the cap').to_equal(uc_ai_agents_api.c_exec_completed);

    sys.dbms_output.put_line('Capped handoff result: ' || l_result.get_clob('final_message'));

    ut.expect(l_result.get_number('handoff_count'), 'Chain stopped at the cap').to_equal(1);
    ut.expect(l_result.get_boolean('max_handoffs_reached')).to_be_true();
    ut.expect(l_result.get_clob('final_message'), 'Specialist still answered').to_be_like('%2.5%');
  end max_handoffs_guard;

end test_uc_ai_agent_handoff;
/
