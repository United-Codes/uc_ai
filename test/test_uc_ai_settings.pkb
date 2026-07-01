create or replace package body test_uc_ai_settings as
  -- @dblinter ignore(g-5010): allow logger in test packages

  procedure build_captures_globals
  as
    l_s uc_ai_settings.t_settings;
  begin
    -- Set a distinct sentinel on a representative field of every provider group,
    -- then assert build_from_globals copied it into the record.
    uc_ai.reset_globals;
    uc_ai.g_base_url            := 'https://sentinel.example/v1';
    uc_ai.g_provider_override   := uc_ai.c_provider_openrouter;
    uc_ai.g_apex_web_credential := 'ROOT_CRED';
    uc_ai.g_enable_tools        := true;
    uc_ai.g_enable_reasoning    := true;
    uc_ai.g_reasoning_level     := uc_ai.c_reasoning_level_high;
    uc_ai.g_tool_tags           := apex_t_varchar2('tag_a', 'tag_b');
    uc_ai.g_max_tool_calls      := 42;

    uc_ai_openai.g_use_responses_api := false;
    uc_ai_openai.g_reasoning_effort  := 'high';
    uc_ai_openai.g_apex_web_credential := 'OA_CRED';

    uc_ai_anthropic.g_max_tokens := 4242;
    uc_ai_anthropic.g_reasoning_budget_tokens := 2048;
    uc_ai_anthropic.g_apex_web_credential := 'AN_CRED';

    uc_ai_google.g_reasoning_budget := 1234;
    uc_ai_google.g_apex_web_credential := 'GO_CRED';
    uc_ai_google.g_embedding_task_type := 'CLASSIFICATION';
    uc_ai_google.g_embedding_output_dimensions := 768;

    uc_ai_ollama.g_apex_web_credential := 'OL_CRED';
    uc_ai_ollama.g_use_responses_api := false;

    uc_ai_oci.g_compartment_id := 'ocid1.sentinel';
    uc_ai_oci.g_serving_type := 'DEDICATED';
    uc_ai_oci.g_region := 'eu-frankfurt-1';
    uc_ai_oci.g_apex_web_credential := 'OC_CRED';
    uc_ai_oci.g_use_responses_api := false;

    uc_ai_xai.g_reasoning_effort := 'high';
    uc_ai_xai.g_apex_web_credential := 'XA_CRED';

    uc_ai_openrouter.g_reasoning_effort := 'high';
    uc_ai_openrouter.g_apex_web_credential := 'OR_CRED';

    uc_ai_responses_api.g_base_url := 'https://resp.example/v1';
    uc_ai_responses_api.g_reasoning_effort := 'high';
    uc_ai_responses_api.g_reasoning_summary := 'detailed';
    uc_ai_responses_api.g_text_verbosity := 'high';
    uc_ai_responses_api.g_store_responses := true;
    uc_ai_responses_api.g_include_encrypted_reasoning := true;
    uc_ai_responses_api.g_apex_web_credential := 'RA_CRED';
    uc_ai_responses_api.g_extra_header_name := 'opc-compartment-id';
    uc_ai_responses_api.g_extra_header_value := 'ocid1.hdr';
    uc_ai_responses_api.g_skip_auth := true;

    l_s := uc_ai_settings.build_from_globals;

    ut.expect(l_s.initialized).to_be_true();
    -- common
    ut.expect(l_s.base_url).to_equal('https://sentinel.example/v1');
    ut.expect(l_s.provider_override).to_equal(uc_ai.c_provider_openrouter);
    ut.expect(l_s.apex_web_credential).to_equal('ROOT_CRED');
    ut.expect(l_s.enable_tools).to_be_true();
    ut.expect(l_s.enable_reasoning).to_be_true();
    ut.expect(l_s.reasoning_level).to_equal(uc_ai.c_reasoning_level_high);
    ut.expect(l_s.tool_tags.count).to_equal(2);
    ut.expect(l_s.max_tool_calls).to_equal(42);
    -- openai
    ut.expect(l_s.oa_use_responses_api).to_be_false();
    ut.expect(l_s.oa_reasoning_effort).to_equal('high');
    ut.expect(l_s.oa_apex_web_credential).to_equal('OA_CRED');
    -- anthropic
    ut.expect(l_s.an_max_tokens).to_equal(4242);
    ut.expect(l_s.an_reasoning_budget_tokens).to_equal(2048);
    ut.expect(l_s.an_apex_web_credential).to_equal('AN_CRED');
    -- google
    ut.expect(l_s.go_reasoning_budget).to_equal(1234);
    ut.expect(l_s.go_apex_web_credential).to_equal('GO_CRED');
    ut.expect(l_s.go_embedding_task_type).to_equal('CLASSIFICATION');
    ut.expect(l_s.go_embedding_output_dimensions).to_equal(768);
    -- ollama
    ut.expect(l_s.ol_apex_web_credential).to_equal('OL_CRED');
    ut.expect(l_s.ol_use_responses_api).to_be_false();
    -- oci
    ut.expect(l_s.oc_compartment_id).to_equal('ocid1.sentinel');
    ut.expect(l_s.oc_serving_type).to_equal('DEDICATED');
    ut.expect(l_s.oc_region).to_equal('eu-frankfurt-1');
    ut.expect(l_s.oc_apex_web_credential).to_equal('OC_CRED');
    ut.expect(l_s.oc_use_responses_api).to_be_false();
    -- xai / openrouter
    ut.expect(l_s.xa_reasoning_effort).to_equal('high');
    ut.expect(l_s.xa_apex_web_credential).to_equal('XA_CRED');
    ut.expect(l_s.or_reasoning_effort).to_equal('high');
    ut.expect(l_s.or_apex_web_credential).to_equal('OR_CRED');
    -- responses api
    ut.expect(l_s.ra_base_url).to_equal('https://resp.example/v1');
    ut.expect(l_s.ra_reasoning_effort).to_equal('high');
    ut.expect(l_s.ra_reasoning_summary).to_equal('detailed');
    ut.expect(l_s.ra_text_verbosity).to_equal('high');
    ut.expect(l_s.ra_store_responses).to_be_true();
    ut.expect(l_s.ra_include_encrypted_reasoning).to_be_true();
    ut.expect(l_s.ra_apex_web_credential).to_equal('RA_CRED');
    ut.expect(l_s.ra_extra_header_name).to_equal('opc-compartment-id');
    ut.expect(l_s.ra_extra_header_value).to_equal('ocid1.hdr');
    ut.expect(l_s.ra_skip_auth).to_be_true();

    uc_ai.reset_globals;
  end build_captures_globals;

  procedure new_run_state_zeroed
  as
    l_r uc_ai_settings.t_run_state;
  begin
    l_r := uc_ai_settings.new_run_state;
    ut.expect(l_r.tool_calls).to_equal(0);
    ut.expect(l_r.input_tokens).to_equal(0);
    ut.expect(l_r.output_tokens).to_equal(0);
    ut.expect(l_r.reasoning_tokens).to_equal(0);
    ut.expect(l_r.total_tokens).to_equal(0);
    ut.expect(l_r.final_message).to_be_null();
    ut.expect(l_r.previous_response_id).to_be_null();
  end new_run_state_zeroed;

  procedure config_maps_keys
  as
    l_config json_object_t;
    l_s      uc_ai_settings.t_settings;
  begin
    l_config := json_object_t('{
      "g_base_url": "https://cfg.example/v1",
      "g_enable_reasoning": true,
      "g_reasoning_level": "high",
      "g_enable_tools": true,
      "g_max_tool_calls": 7,
      "g_apex_web_credential": "CFG_CRED",
      "g_tool_tags": ["alpha", "beta"],
      "openai": {
        "g_use_responses_api": false,
        "g_reasoning_effort": "high",
        "g_apex_web_credential": "OA_CFG"
      }
    }');

    l_s := uc_ai_settings.build_from_config(l_config, uc_ai.c_provider_openai);

    ut.expect(l_s.initialized).to_be_true();
    ut.expect(l_s.base_url).to_equal('https://cfg.example/v1');
    ut.expect(l_s.enable_reasoning).to_be_true();
    ut.expect(l_s.reasoning_level).to_equal('high');
    ut.expect(l_s.enable_tools).to_be_true();
    ut.expect(l_s.max_tool_calls).to_equal(7);
    ut.expect(l_s.apex_web_credential).to_equal('CFG_CRED');
    ut.expect(l_s.tool_tags.count).to_equal(2);
    -- provider-nested
    ut.expect(l_s.oa_use_responses_api).to_be_false();
    ut.expect(l_s.oa_reasoning_effort).to_equal('high');
    ut.expect(l_s.oa_apex_web_credential).to_equal('OA_CFG');
  end config_maps_keys;

  procedure config_uses_defaults
  as
    l_s uc_ai_settings.t_settings;
  begin
    -- Empty config: every field must equal the framework default (reset_globals).
    l_s := uc_ai_settings.build_from_config(json_object_t('{}'), uc_ai.c_provider_openai);

    ut.expect(l_s.initialized).to_be_true();
    ut.expect(l_s.base_url).to_be_null();
    ut.expect(l_s.enable_tools).to_be_false();
    ut.expect(l_s.enable_reasoning).to_be_false();
    ut.expect(l_s.max_tool_calls).to_be_null();
    ut.expect(l_s.tool_tags.count).to_equal(0);
    ut.expect(l_s.oa_use_responses_api).to_be_true();
    ut.expect(l_s.oa_reasoning_effort).to_equal('low');
    ut.expect(l_s.an_max_tokens).to_equal(8192);
    ut.expect(l_s.oc_serving_type).to_equal('ON_DEMAND');
    ut.expect(l_s.ra_text_verbosity).to_equal('medium');
  end config_uses_defaults;

  procedure config_ignores_globals
  as
    l_s uc_ai_settings.t_settings;
  begin
    -- Set globals to sentinels that must NOT appear in a config-built record.
    uc_ai.reset_globals;
    uc_ai.g_base_url            := 'https://global.sentinel/v1';
    uc_ai.g_enable_tools        := true;
    uc_ai.g_apex_web_credential := 'GLOBAL_CRED';

    l_s := uc_ai_settings.build_from_config(
      json_object_t('{"g_enable_reasoning": true}')
    , uc_ai.c_provider_openai
    );

    -- Config did not set these -> they stay at defaults, NOT the global values.
    ut.expect(l_s.base_url).to_be_null();
    ut.expect(l_s.enable_tools).to_be_false();
    ut.expect(l_s.apex_web_credential).to_be_null();
    -- The one key the config did set is honoured.
    ut.expect(l_s.enable_reasoning).to_be_true();

    -- And the globals themselves must be untouched by build_from_config.
    ut.expect(uc_ai.g_base_url).to_equal('https://global.sentinel/v1');
    ut.expect(case when uc_ai.g_enable_tools then 1 else 0 end).to_equal(1);
    ut.expect(uc_ai.g_apex_web_credential).to_equal('GLOBAL_CRED');

    uc_ai.reset_globals;
  end config_ignores_globals;

  procedure config_rejects_unknown_key
  as
    l_s uc_ai_settings.t_settings;
  begin
    l_s := uc_ai_settings.build_from_config(
      json_object_t('{"g_not_a_real_key": 1}')
    , uc_ai.c_provider_openai
    );
  end config_rejects_unknown_key;

  procedure config_rejects_unknown_provider
  as
    l_s uc_ai_settings.t_settings;
  begin
    l_s := uc_ai_settings.build_from_config(json_object_t('{}'), 'not_a_provider');
  end config_rejects_unknown_provider;

end test_uc_ai_settings;
/
