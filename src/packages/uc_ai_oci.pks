create or replace package uc_ai_oci as

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
  */

  -- Oracle Cloud Infrastructure (OCI) Generative AI models
  -- See https://docs.oracle.com/en-us/iaas/Content/generative-ai/overview.htm
  
  -- Meta Llama models
  c_model_llama_3_3_70b_instruct    constant uc_ai.model_type := 'meta.llama-3.3-70b-instruct';
  c_model_llama_3_1_405b_instruct   constant uc_ai.model_type := 'meta.llama-3.1-405b-instruct';
  c_model_llama_3_1_70b_instruct    constant uc_ai.model_type := 'meta.llama-3.1-70b-instruct';
  c_model_llama_3_1_8b_instruct     constant uc_ai.model_type := 'meta.llama-3.1-8b-instruct';
  c_model_llama_3_70b_instruct      constant uc_ai.model_type := 'meta.llama-3-70b-instruct';
  
  -- Cohere Command models
  c_model_cohere_command_a_03_2025  constant uc_ai.model_type := 'cohere.command-a-03-2025';
  c_model_cohere_command_r_plus     constant uc_ai.model_type := 'cohere.command-r-plus';
  c_model_cohere_command_r          constant uc_ai.model_type := 'cohere.command-r';
  
  -- Oracle proprietary models (if available)
  c_model_oracle_genai              constant uc_ai.model_type := 'oracle.genai';

  -- Global settings for OCI
  g_compartment_id varchar2(255 char); -- OCID of the compartment to use
  g_serving_type varchar2(64 char) := 'ON_DEMAND'; -- ON_DEMAND or DEDICATED
  g_region varchar2(64 char) := 'us-ashburn-1'; -- OCI region for API endpoint
  g_apex_web_credential varchar2(255 char);

  /*
   * Oracle Cloud Infrastructure (OCI) Generative AI implementation for text generation 
   */
  function generate_text (
    p_messages       in json_array_t
  , p_model          in uc_ai.model_type
  , p_max_tool_calls in pls_integer
  ) return json_object_t;

end uc_ai_oci;
/
