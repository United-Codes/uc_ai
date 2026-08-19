create or replace package body test_uc_ai_agent_handoff as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  gc_handoff_code  constant varchar2(50 char) := 'TEST_HANDOFF';
  gc_capped_code   constant varchar2(50 char) := 'TEST_HANDOFF_CAPPED';
  gc_ml_code       constant varchar2(50 char) := 'TEST_HANDOFF_ML';
  gc_triage_code   constant varchar2(50 char) := 'TEST_HANDOFF_TRIAGE';
  gc_product_code  constant varchar2(50 char) := 'TEST_HANDOFF_PRODUCT';
  gc_shipping_code constant varchar2(50 char) := 'TEST_HANDOFF_SHIPPING';
  gc_customer_code constant varchar2(50 char) := 'TEST_HANDOFF_CUSTOMER';
  gc_tech_a_code   constant varchar2(50 char) := 'TEST_HANDOFF_TECH_A';
  gc_tech_b_code   constant varchar2(50 char) := 'TEST_HANDOFF_TECH_B';
  gc_returns_code  constant varchar2(50 char) := 'TEST_HANDOFF_RETURNS';

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

  /*
   * Multi-level handoff config (can_transfer_to graph) modeling:
   *   triage -> {product, shipping, customer}
   *   product -> {tech A, tech B, triage}
   *   shipping -> {returns, triage}
   *   tech A / tech B / returns -> {triage}
   * Triage never sees the level-3 specialists.
   */
  function ml_handoff_config return clob
  as
  begin
    return '{
      "pattern_type": "handoff",
      "initial_agent_code": "' || gc_triage_code || '",
      "handoff_agents": [
        {"agent_code": "' || gc_triage_code || '", "description": "Triage and general support - transfer back for questions outside your specialty",
         "can_transfer_to": ["' || gc_product_code || '", "' || gc_shipping_code || '", "' || gc_customer_code || '"]},
        {"agent_code": "' || gc_product_code || '", "description": "Product support: specs, prices, availability and technical problems with products",
         "can_transfer_to": ["' || gc_tech_a_code || '", "' || gc_tech_b_code || '", "' || gc_triage_code || '"]},
        {"agent_code": "' || gc_shipping_code || '", "description": "Shipping and returns: options, costs, delivery times, return policy",
         "can_transfer_to": ["' || gc_returns_code || '", "' || gc_triage_code || '"]},
        {"agent_code": "' || gc_customer_code || '", "description": "Customer accounts: membership, orders, order status",
         "can_transfer_to": ["' || gc_triage_code || '"]},
        {"agent_code": "' || gc_tech_a_code || '", "description": "Technician for technical problems with the Aurora Desk Lamp",
         "can_transfer_to": ["' || gc_triage_code || '"]},
        {"agent_code": "' || gc_tech_b_code || '", "description": "Technician for technical problems with the GLX-7000 Headset",
         "can_transfer_to": ["' || gc_triage_code || '"]},
        {"agent_code": "' || gc_returns_code || '", "description": "Return policy: return window, return fees, refunds",
         "can_transfer_to": ["' || gc_triage_code || '"]}
      ],
      "max_handoffs": 5
    }';
  end ml_handoff_config;

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

    -- Level-3 specialists for multi-level routing
    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_tech_a_code,
      p_description         => 'Aurora Desk Lamp technician',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_CS_TECH_A',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_tech_b_code,
      p_description         => 'GLX-7000 Headset technician',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_CS_TECH_B',
      p_status              => uc_ai_agents_api.c_status_active
    );

    l_id := uc_ai_agents_api.create_agent(
      p_code                => gc_returns_code,
      p_description         => 'Return policy specialist',
      p_agent_type          => uc_ai_agents_api.c_type_profile,
      p_prompt_profile_code => 'TEST_AGENT_CS_RETURNS',
      p_status              => uc_ai_agents_api.c_status_active
    );

    -- The handoff agent (single point of entry, flat mesh)
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_handoff_code,
      p_description          => 'Customer support handoff agent',
      p_agent_type           => uc_ai_agents_api.c_type_handoff,
      p_orchestration_config => handoff_config(p_max_handoffs => 3),
      p_status               => uc_ai_agents_api.c_status_active
    );

    -- The multi-level handoff agent (can_transfer_to graph)
    l_id := uc_ai_agents_api.create_agent(
      p_code                 => gc_ml_code,
      p_description          => 'Customer support handoff agent with two-level specialist tree',
      p_agent_type           => uc_ai_agents_api.c_type_handoff,
      p_orchestration_config => ml_handoff_config,
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

    -- Attribution: the specialist's hop (its answer + its tool activity) is
    -- attributed to the product agent via agent_code, not the wrapper.
    select count(*)
      into l_count
      from uc_ai_agent_messages
     where session_id = l_session_id
       and role = 'assistant'
       and agent_code = gc_product_code;
    ut.expect(l_count, 'Specialist hop attributed to the product agent').to_be_greater_than(0);

    -- The product child execution is a distinct row that recorded its own LLM
    -- spend (proving it, not the wrapper, made the model call that used the
    -- catalog tool). NB: tool_calls_count / iteration_count are intentionally
    -- NOT asserted here - the completion path never populates those columns
    -- (they stay 0 for every execution), so token spend is the reliable signal.
    declare
      l_prod_agent_id number;
      l_child_in      number;
      l_child_out     number;
    begin
      select id into l_prod_agent_id
        from uc_ai_agents where code = gc_product_code and status = 'active'
       fetch first 1 row only;

      select total_input_tokens, total_output_tokens
        into l_child_in, l_child_out
        from uc_ai_agent_executions
       where session_id = l_session_id
         and agent_id = l_prod_agent_id
         and parent_execution_id is not null
       fetch first 1 row only;

      ut.expect(l_child_in, 'Product child recorded input tokens').to_be_greater_than(0);
      ut.expect(l_child_out, 'Product child recorded output tokens').to_be_greater_than(0);
    end;

    -- Full cross-table persistence invariants (executions + session + messages)
    uc_ai_test_agent_utils.validate_session_persistence(
      p_session_id       => l_session_id,
      p_root_agent_code  => gc_handoff_code,
      p_final_agent_code => gc_product_code,
      p_expected_turns   => 1,
      p_test_name        => 'Route product question'
    );
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

    uc_ai_test_agent_utils.validate_session_persistence(
      p_session_id       => l_session_id,
      p_root_agent_code  => gc_handoff_code,
      p_final_agent_code => gc_shipping_code,
      p_expected_turns   => 1,
      p_test_name        => 'Route shipping question'
    );
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

    uc_ai_test_agent_utils.validate_session_persistence(
      p_session_id       => l_session_id,
      p_root_agent_code  => gc_handoff_code,
      p_final_agent_code => gc_customer_code,
      p_expected_turns   => 1,
      p_test_name        => 'Route customer question'
    );
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

    -- Triage answered directly: it is the (only) child execution.
    uc_ai_test_agent_utils.validate_session_persistence(
      p_session_id       => l_session_id,
      p_root_agent_code  => gc_handoff_code,
      p_final_agent_code => gc_triage_code,
      p_expected_turns   => 1,
      p_test_name        => 'Direct answer'
    );
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

    -- Even a capped chain persists a clean hierarchy: capped wrapper as root,
    -- product specialist as the answering child.
    uc_ai_test_agent_utils.validate_session_persistence(
      p_session_id       => l_session_id,
      p_root_agent_code  => gc_capped_code,
      p_final_agent_code => gc_product_code,
      p_expected_turns   => 1,
      p_test_name        => 'Max handoffs guard'
    );
  end max_handoffs_guard;

  procedure multi_level_tech_question
  as
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_final_msg  clob;
    l_trail      json_array_t;
    l_entry      json_object_t;
    l_count      number;
  begin
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_ml_code,
      p_input_parameters => json_object_t('{"prompt": "My Aurora Desk Lamp will not turn on anymore. How do I reset it?"}'),
      p_session_id       => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Multi-level tech question');
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Multi-level tech result: ' || l_final_msg);

    -- Only the Aurora technician knows the reset procedure
    ut.expect(l_final_msg, 'Answer should contain the technician-only fact').to_be_like('%5 seconds%');
    ut.expect(l_result.get_number('handoff_count'), 'Two handoffs (triage -> product -> tech A)').to_equal(2);
    ut.expect(l_result.get_string('final_agent_code')).to_equal(gc_tech_a_code);

    -- The trail proves the request went THROUGH the mid-level (graph scoping:
    -- triage cannot see the technicians directly)
    l_trail := l_result.get_array('handoff_trail');
    ut.expect(l_trail.get_size, 'Trail has two hops').to_equal(2);

    l_entry := treat(l_trail.get(0) as json_object_t);
    ut.expect(l_entry.get_string('from_agent'), 'Hop 1 from').to_equal(gc_triage_code);
    ut.expect(l_entry.get_string('to_agent'), 'Hop 1 to').to_equal(gc_product_code);

    l_entry := treat(l_trail.get(1) as json_object_t);
    ut.expect(l_entry.get_string('from_agent'), 'Hop 2 from').to_equal(gc_product_code);
    ut.expect(l_entry.get_string('to_agent'), 'Hop 2 to').to_equal(gc_tech_a_code);

    -- Both transfer tool calls are persisted in the message log
    select count(*)
      into l_count
      from uc_ai_agent_messages
     where session_id = l_session_id
       and role = 'tool_call'
       and tool_name like 'transfer_to_%';
    ut.expect(l_count, 'Two transfer tool calls in message log').to_equal(2);

    -- Two-level routing must still persist as one flat session: three child
    -- executions (triage, product, tech A) under a single wrapper turn.
    select count(*)
      into l_count
      from uc_ai_agent_executions
     where session_id = l_session_id
       and parent_execution_id is not null;
    ut.expect(l_count, 'Three child executions across the two hops').to_equal(3);

    uc_ai_test_agent_utils.validate_session_persistence(
      p_session_id       => l_session_id,
      p_root_agent_code  => gc_ml_code,
      p_final_agent_code => gc_tech_a_code,
      p_expected_turns   => 1,
      p_test_name        => 'Multi-level tech question'
    );
  end multi_level_tech_question;

  procedure multi_level_returns_question
  as
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_final_msg  clob;
    l_trail      json_array_t;
    l_entry      json_object_t;
  begin
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_ml_code,
      p_input_parameters => json_object_t('{"prompt": "How many days do I have to return an item and is there a return fee?"}'),
      p_session_id       => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Multi-level returns question');
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Multi-level returns result: ' || l_final_msg);

    -- Only the return policy specialist knows the 30-day window
    ut.expect(l_final_msg, 'Answer should contain the return window').to_be_like('%30%');
    ut.expect(l_result.get_number('handoff_count'), 'Two handoffs (triage -> shipping -> returns)').to_equal(2);
    ut.expect(l_result.get_string('final_agent_code')).to_equal(gc_returns_code);

    l_trail := l_result.get_array('handoff_trail');
    ut.expect(l_trail.get_size, 'Trail has two hops').to_equal(2);
    l_entry := treat(l_trail.get(1) as json_object_t);
    ut.expect(l_entry.get_string('from_agent'), 'Hop 2 from').to_equal(gc_shipping_code);
    ut.expect(l_entry.get_string('to_agent'), 'Hop 2 to').to_equal(gc_returns_code);

    uc_ai_test_agent_utils.validate_session_persistence(
      p_session_id       => l_session_id,
      p_root_agent_code  => gc_ml_code,
      p_final_agent_code => gc_returns_code,
      p_expected_turns   => 1,
      p_test_name        => 'Multi-level returns question'
    );
  end multi_level_returns_question;

  procedure mid_level_answers_itself
  as
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_final_msg  clob;
  begin
    l_session_id := uc_ai_agents_api.generate_session_id;
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_ml_code,
      p_input_parameters => json_object_t('{"prompt": "How much does the GLX-7000 Headset cost?"}'),
      p_session_id       => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Mid-level answers itself');
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Mid-level answer result: ' || l_final_msg);

    -- A spec question is answered by product support (catalog tool) without
    -- descending to a technician
    ut.expect(l_final_msg, 'Answer should contain the catalog price').to_be_like('%129%');
    ut.expect(l_result.get_number('handoff_count'), 'Only one handoff (triage -> product)').to_equal(1);
    ut.expect(l_result.get_string('final_agent_code')).to_equal(gc_product_code);

    uc_ai_test_agent_utils.validate_session_persistence(
      p_session_id       => l_session_id,
      p_root_agent_code  => gc_ml_code,
      p_final_agent_code => gc_product_code,
      p_expected_turns   => 1,
      p_test_name        => 'Mid-level answers itself'
    );
  end mid_level_answers_itself;

  procedure sticky_follow_up_same_agent
  as
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_final_msg  clob;
    l_turn_count number;
    l_count      number;
  begin
    l_session_id := uc_ai_agents_api.generate_session_id;

    -- Turn 1: shipping question ends at the shipping specialist
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_ml_code,
      p_input_parameters => json_object_t('{"prompt": "How much does standard shipping cost?"}'),
      p_session_id       => l_session_id
    );
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Sticky same agent turn 1');
    ut.expect(l_result.get_string('final_agent_code'), 'Turn 1 ends at shipping').to_equal(gc_shipping_code);

    -- Turn 2: follow-up resumes with the shipping specialist (sticky), which
    -- answers itself - no re-routing through triage
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code        => gc_ml_code,
      p_follow_up_message => 'And how much is the express option?',
      p_session_id        => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Sticky same agent turn 2');
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Sticky follow-up result: ' || l_final_msg);

    ut.expect(l_final_msg, 'Answer should contain the express price').to_be_like('%19.99%');
    ut.expect(l_result.get_string('final_agent_code'), 'Still the shipping specialist').to_equal(gc_shipping_code);
    ut.expect(l_result.get_number('handoff_count'), 'No handoff needed').to_equal(0);

    -- Session header reflects two turns
    select turn_count
      into l_turn_count
      from uc_ai_agent_sessions
     where session_id = l_session_id;
    ut.expect(l_turn_count, 'Two conversation turns').to_equal(2);

    select count(*)
      into l_count
      from uc_ai_agent_executions
     where session_id = l_session_id
       and turn_index = 2;
    ut.expect(l_count, 'Second top-level turn recorded').to_equal(1);

    -- Two turns persisted as two wrapper executions in one session, each with
    -- its own message delta; shipping answered both.
    uc_ai_test_agent_utils.validate_session_persistence(
      p_session_id       => l_session_id,
      p_root_agent_code  => gc_ml_code,
      p_final_agent_code => gc_shipping_code,
      p_expected_turns   => 2,
      p_test_name        => 'Sticky same agent'
    );
  end sticky_follow_up_same_agent;

  procedure sticky_follow_up_with_transfer
  as
    l_session_id varchar2(100 char);
    l_result     json_object_t;
    l_final_msg  clob;
  begin
    l_session_id := uc_ai_agents_api.generate_session_id;

    -- Turn 1: shipping question ends at the shipping specialist
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code       => gc_ml_code,
      p_input_parameters => json_object_t('{"prompt": "How long does standard shipping take?"}'),
      p_session_id       => l_session_id
    );
    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Sticky transfer turn 1');
    ut.expect(l_result.get_string('final_agent_code'), 'Turn 1 ends at shipping').to_equal(gc_shipping_code);

    -- Turn 2: topic changes to returns - the resumed shipping specialist must
    -- transfer down to the return policy specialist
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code        => gc_ml_code,
      p_follow_up_message => 'One more thing: how many days do I have to return an item?',
      p_session_id        => l_session_id
    );

    uc_ai_test_agent_utils.validate_agent_result(l_result, 'Sticky transfer turn 2');
    ut.expect(l_result.get_string('status')).to_equal(uc_ai_agents_api.c_exec_completed);

    l_final_msg := l_result.get_clob('final_message');
    sys.dbms_output.put_line('Sticky transfer result: ' || l_final_msg);

    ut.expect(l_final_msg, 'Answer should contain the return window').to_be_like('%30%');
    ut.expect(l_result.get_string('final_agent_code'), 'Return specialist took over').to_equal(gc_returns_code);
    ut.expect(l_result.get_number('handoff_count'), 'One handoff in the follow-up turn').to_equal(1);

    -- Follow-up turn that transferred onward still reconciles: two wrapper
    -- turns, the return specialist ran as a child, message log spans both turns.
    uc_ai_test_agent_utils.validate_session_persistence(
      p_session_id       => l_session_id,
      p_root_agent_code  => gc_ml_code,
      p_final_agent_code => gc_returns_code,
      p_expected_turns   => 2,
      p_test_name        => 'Sticky transfer'
    );
  end sticky_follow_up_with_transfer;

end test_uc_ai_agent_handoff;
/
