create or replace package body test_uc_ai_reset_globals as
  -- @dblinter ignore(g-7230): allow package state in test helper

  -- Dirty every public global with a non-default sentinel value so a passing
  -- assertion proves reset_globals actually touched it.
  procedure dirty_all_globals
  as
  begin
    -- uc_ai core
    uc_ai.g_base_url           := 'https://dirty.example.com/v1';
    uc_ai.g_enable_reasoning   := true;
    uc_ai.g_reasoning_level    := uc_ai.c_reasoning_level_high;
    uc_ai.g_enable_tools       := true;
    uc_ai.g_tool_tags          := apex_t_varchar2('dirty');
    uc_ai.g_max_tool_calls     := 99;
    uc_ai.g_apex_web_credential := 'DIRTY';
    uc_ai.g_provider_override  := uc_ai.c_provider_xai;
    uc_ai.g_request_id         := 'dirtyreqid';
    uc_ai.g_callback_fatal     := true;
    uc_ai.g_extra_headers('x-dirty') := 'v';

    -- OpenAI
    uc_ai_openai.g_use_responses_api := false;
    uc_ai_openai.g_reasoning_effort  := 'high';
    uc_ai_openai.g_apex_web_credential := 'DIRTY';

    -- Shared Responses API (the globals that previously leaked across calls)
    uc_ai_responses_api.g_base_url                    := 'https://dirty.example.com/v1';
    uc_ai_responses_api.g_reasoning_effort            := 'high';
    uc_ai_responses_api.g_reasoning_summary           := 'detailed';
    uc_ai_responses_api.g_text_verbosity              := 'high';
    uc_ai_responses_api.g_store_responses             := true;
    uc_ai_responses_api.g_include_encrypted_reasoning := true;
    uc_ai_responses_api.g_apex_web_credential         := 'DIRTY';
    uc_ai_responses_api.g_skip_auth                   := true;

    -- Anthropic
    uc_ai_anthropic.g_max_tokens              := 1;
    uc_ai_anthropic.g_reasoning_budget_tokens := 2048;
    uc_ai_anthropic.g_apex_web_credential     := 'DIRTY';

    -- Google
    uc_ai_google.g_reasoning_budget            := 100;
    uc_ai_google.g_apex_web_credential         := 'DIRTY';
    uc_ai_google.g_embedding_task_type         := 'CLASSIFICATION';
    uc_ai_google.g_embedding_output_dimensions := 768;

    -- Ollama
    uc_ai_ollama.g_apex_web_credential := 'DIRTY';
    uc_ai_ollama.g_use_responses_api   := false;

    -- OCI
    uc_ai_oci.g_compartment_id     := 'ocid1.dirty';
    uc_ai_oci.g_serving_type       := 'DEDICATED';
    uc_ai_oci.g_region             := 'eu-frankfurt-1';
    uc_ai_oci.g_apex_web_credential := 'DIRTY';
    uc_ai_oci.g_use_responses_api  := false;

    -- xAI
    uc_ai_xai.g_reasoning_effort   := 'high';
    uc_ai_xai.g_apex_web_credential := 'DIRTY';

    -- OpenRouter
    uc_ai_openrouter.g_reasoning_effort    := 'high';
    uc_ai_openrouter.g_apex_web_credential := 'DIRTY';

    -- Mistral
    uc_ai_mistral.g_apex_web_credential := 'DIRTY';
  end dirty_all_globals;

  procedure resets_uc_ai_core
  as
  begin
    dirty_all_globals;
    uc_ai.reset_globals;

    ut.expect(uc_ai.g_base_url).to_be_null();
    ut.expect(uc_ai.g_enable_reasoning).to_be_false();
    ut.expect(uc_ai.g_reasoning_level).to_be_null();
    ut.expect(uc_ai.g_enable_tools).to_be_false();
    ut.expect(uc_ai.g_tool_tags.count).to_equal(0);
    ut.expect(uc_ai.g_max_tool_calls).to_be_null();
    ut.expect(uc_ai.g_apex_web_credential).to_be_null();
    ut.expect(uc_ai.g_provider_override).to_be_null();
    ut.expect(uc_ai.g_request_id).to_be_null();
    ut.expect(case when uc_ai.g_callback_fatal then 1 else 0 end).to_equal(0);
    ut.expect(uc_ai.g_extra_headers.count).to_equal(0);
  end resets_uc_ai_core;

  procedure resets_responses_api
  as
  begin
    dirty_all_globals;
    uc_ai.reset_globals;

    ut.expect(uc_ai_responses_api.g_base_url).to_be_null();
    ut.expect(uc_ai_responses_api.g_reasoning_effort).to_be_null();
    ut.expect(uc_ai_responses_api.g_reasoning_summary).to_be_null();
    ut.expect(uc_ai_responses_api.g_text_verbosity).to_equal('medium');
    ut.expect(uc_ai_responses_api.g_store_responses).to_be_false();
    ut.expect(uc_ai_responses_api.g_include_encrypted_reasoning).to_be_false();
    ut.expect(uc_ai_responses_api.g_apex_web_credential).to_be_null();
    ut.expect(uc_ai_responses_api.g_skip_auth).to_be_false();
  end resets_responses_api;

  procedure resets_providers
  as
  begin
    dirty_all_globals;
    uc_ai.reset_globals;

    -- OpenAI
    ut.expect(uc_ai_openai.g_use_responses_api).to_be_true();
    ut.expect(uc_ai_openai.g_reasoning_effort).to_equal('low');
    ut.expect(uc_ai_openai.g_apex_web_credential).to_be_null();

    -- Anthropic
    ut.expect(uc_ai_anthropic.g_max_tokens).to_equal(8192);
    ut.expect(uc_ai_anthropic.g_reasoning_budget_tokens).to_be_null();
    ut.expect(uc_ai_anthropic.g_apex_web_credential).to_be_null();

    -- Google
    ut.expect(uc_ai_google.g_reasoning_budget).to_be_null();
    ut.expect(uc_ai_google.g_apex_web_credential).to_be_null();
    ut.expect(uc_ai_google.g_embedding_task_type).to_equal('SEMANTIC_SIMILARITY');
    ut.expect(uc_ai_google.g_embedding_output_dimensions).to_equal(1536);

    -- Ollama
    ut.expect(uc_ai_ollama.g_apex_web_credential).to_be_null();
    ut.expect(uc_ai_ollama.g_use_responses_api).to_be_true();

    -- OCI
    ut.expect(uc_ai_oci.g_compartment_id).to_be_null();
    ut.expect(uc_ai_oci.g_serving_type).to_equal('ON_DEMAND');
    ut.expect(uc_ai_oci.g_region).to_equal('us-ashburn-1');
    ut.expect(uc_ai_oci.g_apex_web_credential).to_be_null();
    ut.expect(uc_ai_oci.g_use_responses_api).to_be_true();

    -- xAI
    ut.expect(uc_ai_xai.g_reasoning_effort).to_equal('low');
    ut.expect(uc_ai_xai.g_apex_web_credential).to_be_null();

    -- OpenRouter
    ut.expect(uc_ai_openrouter.g_reasoning_effort).to_equal('low');
    ut.expect(uc_ai_openrouter.g_apex_web_credential).to_be_null();

    -- Mistral
    ut.expect(uc_ai_mistral.g_apex_web_credential).to_be_null();
  end resets_providers;

end test_uc_ai_reset_globals;
/
