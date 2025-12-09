create or replace package uc_ai_xai as
  -- @dblinter ignore(g-7230): allow use of global variables

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */


  -- get from https://docs.x.ai/docs/models
  c_model_grok_4_1_fast constant uc_ai.model_type := 'grok-4-1-fast-non-reasoning';
  c_model_grok_4_fast constant uc_ai.model_type := 'grok-4-fast-non-reasoning';
  c_model_grok_4 constant uc_ai.model_type := 'grok-4';
  c_model_grok_3_mini constant uc_ai.model_type := 'grok-3-mini';
  c_model_grok_3 constant uc_ai.model_type := 'grok-3';
  c_model_grok_2_vision constant uc_ai.model_type := 'grok-2-vision';

  c_model_grok_code_fast_1 constant uc_ai.model_type := 'grok-code-fast-1';

  -- How many reasoning tokens to generate before creating a response
  -- More info at https://docs.x.ai/docs/guides/reasoning#control-how-hard-the-model-thinks
  g_reasoning_effort varchar2(32 char) := 'low'; -- 'low', 'high'

  -- type: HTTP-Header, credential-name: Authorization, value: Bearer <token>
  g_apex_web_credential varchar2(255 char);

end uc_ai_xai;
/
