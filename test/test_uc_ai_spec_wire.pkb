create or replace package body test_uc_ai_spec_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5080): the error test catches the expected exception to assert on its code; a backtrace adds nothing

  -- The placeholder the OCI samples were recorded with.
  c_compartment constant varchar2(100 char) := 'ocid1.tenancy.oc1..aaaaaaaaXXXX...';
  c_endpoint    constant varchar2(100 char) := 'ocid1.generativeaiendpoint.oc1.eu-frankfurt-1.aaaaaaaaWIRE';
  c_llama       constant varchar2(64 char)  := 'meta.llama-3.3-70b-instruct';
  c_embed_model constant varchar2(64 char)  := 'cohere.embed-english-v3.0';

  c_recipe_prompt constant varchar2(200 char) := 'I have tomatoes, salad, potatoes, olives, and cheese. What can I cook with that?';

  e_missing_config exception;
  pragma exception_init(e_missing_config, -20502);


  -- ---- helpers (the shared ones live in test_uc_ai_wire) -------------------------

  /*
   * A config that names the web credential and the OCI compartment, plus the
   * serving-mode keys the test is about. Config-driven calls read no globals, so
   * each test states its whole setup here.
   */
  function oci_config(p_oci_json in varchar2) return json_object_t
  as
    l_config json_object_t := test_uc_ai_wire.config;
    l_oci    json_object_t := json_object_t.parse(p_oci_json);
  begin
    l_oci.put('g_compartment_id', c_compartment);
    l_config.put('oci', l_oci);
    return l_config;
  end oci_config;


  function serving_mode_of(p_index in pls_integer) return json_object_t
  as
  begin
    return uc_ai_test_http_mock.request_json(p_index).get_object('servingMode');
  end serving_mode_of;


  /*
   * DedicatedServingMode is {servingType, endpointId}: the endpoint OCID
   * addresses the cluster, and a modelId on the same object is what the API
   * rejects. Assert the absence as hard as the presence.
   */
  procedure expect_dedicated_serving_mode(p_index in pls_integer)
  as
    l_serving_mode json_object_t := serving_mode_of(p_index);
  begin
    ut.expect(l_serving_mode.get_string('servingType'), 'servingType').to_equal('DEDICATED');
    ut.expect(l_serving_mode.get_string('endpointId'), 'endpointId').to_equal(c_endpoint);
    ut.expect(case when l_serving_mode.has('modelId') then 1 else 0 end, 'modelId present').to_equal(0);
    ut.expect(l_serving_mode.get_size, 'keys on the serving mode').to_equal(2);
  end expect_dedicated_serving_mode;


  procedure expect_on_demand_serving_mode(
    p_index in pls_integer
  , p_model in varchar2
  )
  as
    l_serving_mode json_object_t := serving_mode_of(p_index);
  begin
    ut.expect(l_serving_mode.get_string('servingType'), 'servingType').to_equal('ON_DEMAND');
    ut.expect(l_serving_mode.get_string('modelId'), 'modelId').to_equal(p_model);
    ut.expect(case when l_serving_mode.has('endpointId') then 1 else 0 end, 'endpointId present').to_equal(0);
    ut.expect(l_serving_mode.get_size, 'keys on the serving mode').to_equal(2);
  end expect_on_demand_serving_mode;


  -- ---- fixture ------------------------------------------------------------------

  procedure register_mock
  as
  begin
    uc_ai_http.set_transport('uc_ai_test_http_mock');
  end register_mock;


  procedure unregister_mock
  as
  begin
    uc_ai_http.set_transport(null);
  end unregister_mock;


  procedure reset_state
  as
  begin
    uc_ai.reset_globals;
    uc_ai_test_http_mock.reset;
  end reset_state;


  -- ---- oci serving mode ---------------------------------------------------------

  procedure oci_dedicated_chat_serving_mode
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample('generic/1-simple-response');

    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_llama
    , p_config      => oci_config('{"g_serving_type":"DEDICATED","g_endpoint_id":"' || c_endpoint || '"}')
    );

    expect_dedicated_serving_mode(1);

    -- The rest of the body is untouched by the serving mode.
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('compartmentId')).to_equal(c_compartment);
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);
    test_uc_ai_wire.expect_all_consumed(1);
  end oci_dedicated_chat_serving_mode;


  procedure oci_dedicated_embeddings_serving_mode
  as
    l_vectors json_array_t;
  begin
    test_uc_ai_wire.enqueue_sample('generic/6-embedding-response');

    l_vectors := uc_ai.generate_embeddings(
      p_input    => json_array_t('["APEX Office Print"]')
    , p_provider => uc_ai.c_provider_oci
    , p_model    => c_embed_model
    , p_config   => oci_config('{"g_serving_type":"DEDICATED","g_endpoint_id":"' || c_endpoint || '"}')
    );

    expect_dedicated_serving_mode(1);

    ut.expect(l_vectors.get_size, 'one vector per input').to_equal(1);
    test_uc_ai_wire.expect_all_consumed(1);
  end oci_dedicated_embeddings_serving_mode;


  procedure oci_dedicated_without_endpoint_raises
  as
    l_result json_object_t;
    l_code   pls_integer;
  begin
    begin
      l_result := uc_ai.generate_text(
        p_user_prompt => c_recipe_prompt
      , p_provider    => uc_ai.c_provider_oci
      , p_model       => c_llama
      , p_config      => oci_config('{"g_serving_type":"DEDICATED"}')
      );
      ut.fail('expected -20502');
    exception
      when e_missing_config then
        l_code := sqlcode;
    end;

    ut.expect(l_code, 'DEDICATED without an endpoint id').to_equal(uc_ai_error.c_err_missing_config);
    -- The guard runs before the request is built, so nothing left the database.
    test_uc_ai_wire.expect_all_consumed(0);
  end oci_dedicated_without_endpoint_raises;


  procedure oci_on_demand_serving_mode_unchanged
  as
    l_result  json_object_t;
    l_vectors json_array_t;
  begin
    -- Regression guard: adding the dedicated branch must not move a key on the
    -- default path. Both OCI paths build the serving mode, so both are asserted.
    test_uc_ai_wire.enqueue_sample('generic/1-simple-response');

    l_result := uc_ai.generate_text(
      p_user_prompt => c_recipe_prompt
    , p_provider    => uc_ai.c_provider_oci
    , p_model       => c_llama
    , p_config      => oci_config('{}')
    );

    expect_on_demand_serving_mode(1, c_llama);
    ut.expect(l_result.get_string('finish_reason')).to_equal(uc_ai.c_finish_reason_stop);

    test_uc_ai_wire.enqueue_sample('generic/6-embedding-response');

    l_vectors := uc_ai.generate_embeddings(
      p_input    => json_array_t('["APEX Office Print"]')
    , p_provider => uc_ai.c_provider_oci
    , p_model    => c_embed_model
    , p_config   => oci_config('{"g_serving_type":"ON_DEMAND"}')
    );

    expect_on_demand_serving_mode(2, c_embed_model);

    ut.expect(l_vectors.get_size, 'one vector per input').to_equal(1);
    test_uc_ai_wire.expect_all_consumed(2);
  end oci_on_demand_serving_mode_unchanged;

  -- ---- responses api instructions -----------------------------------------------

  procedure responses_api_long_system_prompt
  as
    c_marker constant varchar2(100 char) := 'The last rule: answer only with the word ORACLE.';
    l_result json_object_t;
    l_system clob;
    l_sent   clob;
    l_tail   varchar2(100 char);
  begin
    -- Over 32 767 characters, so the declared type of po_instructions decides
    -- whether the prompt survives. The marker sits at the very end, where a
    -- varchar2 ceiling cuts.
    -- @dblinter ignore(g-4395): the fixed line count is what makes the prompt exceed 32 KB
    <<filler_loop>>
    for i in 1 .. 40 loop
      l_system := l_system || rpad('Filler sentence ' || to_char(i, 'fm000') || '. ', 1000, '.') || chr(10);
    end loop filler_loop;

    l_system := l_system || c_marker;
    ut.expect(sys.dbms_lob.getlength(l_system), 'system prompt length').to_be_greater_than(32767);

    test_uc_ai_wire.enqueue_sample('openai/responses/1-simple-response');

    l_result := uc_ai.generate_text(
      p_user_prompt   => 'Say "Hello, Responses API!" and nothing else.'
    , p_system_prompt => l_system
    , p_provider      => uc_ai.c_provider_openai
    , p_model         => 'gpt-4o-mini'
    , p_config        => test_uc_ai_wire.config
    );

    l_sent := uc_ai_test_http_mock.request_json(1).get_clob('instructions');
    l_tail := sys.dbms_lob.substr(l_sent, length(c_marker), sys.dbms_lob.getlength(l_sent) - length(c_marker) + 1);

    ut.expect(sys.dbms_lob.getlength(l_sent), 'instructions length on the wire')
      .to_equal(sys.dbms_lob.getlength(l_system));
    ut.expect(l_tail, 'the end of the prompt').to_equal(c_marker);
    ut.expect(l_sent, 'instructions on the wire').to_equal(l_system);

    ut.expect(l_result.get_clob('final_message')).to_equal(to_clob('Hello, Responses API!'));
    test_uc_ai_wire.expect_all_consumed(1);
  end responses_api_long_system_prompt;

end test_uc_ai_spec_wire;
/
