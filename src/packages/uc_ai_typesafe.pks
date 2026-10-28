create or replace package uc_ai_typesafe
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

  /*
   * TypeSafe jev (System One). EXPERIMENTAL. Use with uc_ai.decide and
   * uc_ai.c_provider_typesafe. jev cannot chat: uc_ai.generate_text does not
   * accept this provider, and the model is not part of uc_ai_utils.get_models.
   *
   * jev takes png and jpeg images (preview): any other media type in p_files raises -20508.
   *
   * Credential: a web credential through g_apex_web_credential (or the common
   * uc_ai.g_apex_web_credential), or, when none is set, the key that
   * uc_ai_get_key('typesafe') returns. Your uc_ai_get_key function needs a branch
   * for the provider 'typesafe'.
   *
   * Base URL: uc_ai.g_base_url applies as for the other providers. When it is set
   * (for example to a proxy), it also receives TypeSafe decision calls: the URL is
   * <g_base_url>/systemone. Without it the URL is https://api.typesafe.ai/v1/systemone.
   */

  -- get models from https://docs.typesafe.ai/models
  -- jev-latest is an alias; the response reports the version that answered (jev-1.13.0)
  c_model_jev_latest constant uc_ai.model_type := 'jev-latest';

  -- type: HTTP-Header, credential-name: Authorization, value: Bearer <token>
  g_apex_web_credential varchar2(255 char);

end uc_ai_typesafe;
/
