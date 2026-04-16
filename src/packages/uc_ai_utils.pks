create or replace package uc_ai_utils
  authid definer
as

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  *
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  type r_provider_type is record (
    provider_name varchar2(64 char)
  , provider_id   varchar2(64 char)
  );

  type t_provider_tab is table of r_provider_type;

  type r_model_type is record (
    provider   varchar2(64 char)
  , model_id   varchar2(128 char)
  , model_type varchar2(16 char)
  );

  type t_model_tab is table of r_model_type;

  /*
   * Returns all available providers as a pipelined result set.
   * Useful for populating select lists in APEX or other UI frameworks.
   *
   * Example:
   *   select provider_name d, provider_id r
   *     from table(uc_ai_utils.get_providers)
   */
  function get_providers
    return t_provider_tab pipelined;

  /*
   * Returns all known model constants as a pipelined result set.
   * Optionally filter by provider.
   *
   * Example (all models):
   *   select model_id d, model_id r
   *     from table(uc_ai_utils.get_models)
   *
   * Example (filtered, e.g. for a cascading LOV):
   *   select model_id d, model_id r
   *     from table(uc_ai_utils.get_models(p_provider => 'anthropic'))
   */
  function get_models (
    p_provider in varchar2 default null
  ) return t_model_tab pipelined;

end uc_ai_utils;
/
