create or replace package test_uc_ai_spec_wire as

  --%suite(Wire tests for the settings the package specs carry (LLM-free))
  --%suitepath(uc_ai)

  -- Two changes widened a package spec, and both are only observable on the wire:
  --   * uc_ai_oci.g_endpoint_id / uc_ai_settings.oc_endpoint_id, which turn
  --     servingType DEDICATED from a refusal into a DedicatedServingMode body
  --   * uc_ai_responses_api.convert_lm_messages_to_items, whose po_instructions
  --     is a CLOB, so a system prompt over 32 KB reaches the request whole
  --
  -- Same setup as test_uc_ai_wire: uc_ai_test_http_mock answers every provider
  -- request, and the assertions read the body UC AI built. No test resolves an
  -- API key; every call names an APEX web credential.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- oci serving mode -----------------------------------------------------------
  --%test(OCI chat sends a DedicatedServingMode with the endpoint id and no model id)
  procedure oci_dedicated_chat_serving_mode;

  --%test(OCI embeddings send a DedicatedServingMode with the endpoint id and no model id)
  procedure oci_dedicated_embeddings_serving_mode;

  --%test(OCI raises -20502 and sends nothing when DEDICATED has no endpoint id)
  procedure oci_dedicated_without_endpoint_raises;

  --%test(OCI keeps the on-demand serving mode at modelId plus servingType)
  procedure oci_on_demand_serving_mode_unchanged;

  -- responses api instructions --------------------------------------------------
  --%test(A 40 000 character system prompt reaches the Responses API instructions whole)
  procedure responses_api_long_system_prompt;

end test_uc_ai_spec_wire;
/
