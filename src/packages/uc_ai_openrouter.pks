create or replace package uc_ai_openrouter 
  authid definer
as
  -- @dblinter ignore(g-7230): allow use of global variables

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */


  -- get models from https://openrouter.ai/models

  -- Decisions (uc_ai.decide with uc_ai.c_provider_openrouter), alpha endpoint
  -- POST /api/alpha/decisions. Text only. Default model for decisions.
  -- Chat models do not apply: decisions need a model that OpenRouter lists for the endpoint.
  c_decision_model_jev constant uc_ai.model_type := 'typesafe/jev-1.13';

  -- How many reasoning tokens to generate before creating a response
  -- More info at https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request#request.body.reasoning
  g_reasoning_effort varchar2(32 char) := 'low'; -- 'minimal', 'low', 'medium', 'high'

  -- type: HTTP-Header, credential-name: Authorization, value: Bearer <token>
  g_apex_web_credential varchar2(255 char);

end uc_ai_openrouter;
/
