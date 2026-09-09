create or replace package uc_ai_mistral
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


  -- get models from https://docs.mistral.ai/getting-started/models/models_overview/
  c_model_mistral_large    constant uc_ai.model_type := 'mistral-large-latest';
  c_model_mistral_medium   constant uc_ai.model_type := 'mistral-medium-latest';
  c_model_mistral_small    constant uc_ai.model_type := 'mistral-small-latest';
  c_model_magistral_medium constant uc_ai.model_type := 'magistral-medium-latest';
  c_model_magistral_small  constant uc_ai.model_type := 'magistral-small-latest';
  c_model_codestral        constant uc_ai.model_type := 'codestral-latest';
  c_model_devstral_medium  constant uc_ai.model_type := 'devstral-medium-latest';
  c_model_devstral_small   constant uc_ai.model_type := 'devstral-small-latest';
  c_model_ministral_3_14b  constant uc_ai.model_type := 'ministral-3-14b-25-12';
  c_model_ministral_8b     constant uc_ai.model_type := 'ministral-8b-latest';
  c_model_ministral_3b     constant uc_ai.model_type := 'ministral-3b-latest';
  c_model_pixtral_large    constant uc_ai.model_type := 'pixtral-large-latest';
  c_model_zai_glm_5_2      constant uc_ai.model_type := 'zai-glm-5-2';

  -- embedding models
  c_model_mistral_embed    constant uc_ai.model_type := 'mistral-embed';
  c_model_codestral_embed  constant uc_ai.model_type := 'codestral-embed';

  -- Note: Mistral has no reasoning effort parameter; the magistral models reason by default.

  -- type: HTTP-Header, credential-name: Authorization, value: Bearer <token>
  g_apex_web_credential varchar2(255 char);

end uc_ai_mistral;
/
