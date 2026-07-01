create or replace package body uc_ai_settings
as

  function build_from_globals return t_settings
  as
    l_s t_settings;
  begin
    l_s.initialized                    := true;

    -- common
    l_s.base_url                       := uc_ai.g_base_url;
    l_s.provider_override              := uc_ai.g_provider_override;
    l_s.apex_web_credential            := uc_ai.g_apex_web_credential;
    l_s.enable_tools                   := uc_ai.g_enable_tools;
    l_s.enable_reasoning               := uc_ai.g_enable_reasoning;
    l_s.reasoning_level                := uc_ai.g_reasoning_level;
    l_s.tool_tags                      := uc_ai.g_tool_tags;
    l_s.max_tool_calls                 := uc_ai.g_max_tool_calls;

    -- openai
    l_s.oa_use_responses_api           := uc_ai_openai.g_use_responses_api;
    l_s.oa_reasoning_effort            := uc_ai_openai.g_reasoning_effort;
    l_s.oa_apex_web_credential         := uc_ai_openai.g_apex_web_credential;

    -- anthropic
    l_s.an_max_tokens                  := uc_ai_anthropic.g_max_tokens;
    l_s.an_reasoning_budget_tokens     := uc_ai_anthropic.g_reasoning_budget_tokens;
    l_s.an_apex_web_credential         := uc_ai_anthropic.g_apex_web_credential;

    -- google
    l_s.go_reasoning_budget            := uc_ai_google.g_reasoning_budget;
    l_s.go_apex_web_credential         := uc_ai_google.g_apex_web_credential;
    l_s.go_embedding_task_type         := uc_ai_google.g_embedding_task_type;
    l_s.go_embedding_output_dimensions := uc_ai_google.g_embedding_output_dimensions;

    -- ollama
    l_s.ol_apex_web_credential         := uc_ai_ollama.g_apex_web_credential;
    l_s.ol_use_responses_api           := uc_ai_ollama.g_use_responses_api;

    -- oci
    l_s.oc_compartment_id              := uc_ai_oci.g_compartment_id;
    l_s.oc_serving_type                := uc_ai_oci.g_serving_type;
    l_s.oc_region                      := uc_ai_oci.g_region;
    l_s.oc_apex_web_credential         := uc_ai_oci.g_apex_web_credential;
    l_s.oc_use_responses_api           := uc_ai_oci.g_use_responses_api;

    -- xai
    l_s.xa_reasoning_effort            := uc_ai_xai.g_reasoning_effort;
    l_s.xa_apex_web_credential         := uc_ai_xai.g_apex_web_credential;

    -- openrouter
    l_s.or_reasoning_effort            := uc_ai_openrouter.g_reasoning_effort;
    l_s.or_apex_web_credential         := uc_ai_openrouter.g_apex_web_credential;

    -- responses api
    l_s.ra_base_url                    := uc_ai_responses_api.g_base_url;
    l_s.ra_apex_web_credential         := uc_ai_responses_api.g_apex_web_credential;
    l_s.ra_reasoning_effort            := uc_ai_responses_api.g_reasoning_effort;
    l_s.ra_reasoning_summary           := uc_ai_responses_api.g_reasoning_summary;
    l_s.ra_text_verbosity              := uc_ai_responses_api.g_text_verbosity;
    l_s.ra_store_responses             := uc_ai_responses_api.g_store_responses;
    l_s.ra_include_encrypted_reasoning := uc_ai_responses_api.g_include_encrypted_reasoning;
    l_s.ra_extra_header_name           := uc_ai_responses_api.g_extra_header_name;
    l_s.ra_extra_header_value          := uc_ai_responses_api.g_extra_header_value;
    l_s.ra_skip_auth                   := uc_ai_responses_api.g_skip_auth;

    return l_s;
  end build_from_globals;

  function new_run_state return t_run_state
  as
    l_r t_run_state;
  begin
    l_r.tool_calls           := 0;
    l_r.final_message        := null;
    l_r.input_tokens         := 0;
    l_r.output_tokens        := 0;
    l_r.reasoning_tokens     := 0;
    l_r.total_tokens         := 0;
    l_r.previous_response_id := null;
    return l_r;
  end new_run_state;

end uc_ai_settings;
/
