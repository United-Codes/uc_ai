create or replace package uc_ai_prompt_profiles_api as

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  c_status_draft    constant uc_ai_prompt_profiles.status%type := 'draft';
  c_status_active   constant uc_ai_prompt_profiles.status%type := 'active';
  c_status_archived constant uc_ai_prompt_profiles.status%type := 'archived';

  /*
   * Creates a new prompt profile
   * 
   * @param p_code                    Unique code for the prompt profile
   * @param p_description             Description of the prompt profile
   * @param p_system_prompt_template  System prompt template with placeholders
   * @param p_user_prompt_template    User prompt template with placeholders
   * @param p_provider                AI provider (e.g., 'openai', 'anthropic')
   * @param p_model                   Model name (e.g., 'gpt-4', 'claude-3-opus')
   * @param p_model_config_json       Optional JSON configuration for model parameters
   * @param p_response_schema         Optional JSON schema for structured output
   * @param p_parameters_schema       Optional JSON schema defining expected parameters
   * @param p_version                 Version number (default 1)
   * @param p_status                  Status: 'draft', 'active', or 'archived' (default 'draft')
   * 
   * @return id                       The ID of the created prompt profile
   */
  function create_prompt_profile(
    p_code                    in uc_ai_prompt_profiles.code%type,
    p_description             in uc_ai_prompt_profiles.description%type,
    p_system_prompt_template  in uc_ai_prompt_profiles.system_prompt_template%type,
    p_user_prompt_template    in uc_ai_prompt_profiles.user_prompt_template%type,
    p_provider                in uc_ai_prompt_profiles.provider%type,
    p_model                   in uc_ai_prompt_profiles.model%type,
    p_model_config_json       in uc_ai_prompt_profiles.model_config_json%type default null,
    p_response_schema         in uc_ai_prompt_profiles.response_schema%type default null,
    p_parameters_schema       in uc_ai_prompt_profiles.parameters_schema%type default null,
    p_version                 in uc_ai_prompt_profiles.version%type default 1,
    p_status                  in uc_ai_prompt_profiles.status%type default c_status_draft
  ) return uc_ai_prompt_profiles.id%type;


  /*
   * Updates an existing prompt profile
   * 
   * @param p_id                      ID of the prompt profile to update
   * @param p_description             Description of the prompt profile
   * @param p_system_prompt_template  System prompt template with placeholders
   * @param p_user_prompt_template    User prompt template with placeholders
   * @param p_provider                AI provider
   * @param p_model                   Model name
   * @param p_model_config_json       Optional JSON configuration for model parameters
   * @param p_response_schema         Optional JSON schema for structured output
   * @param p_parameters_schema       Optional JSON schema defining expected parameters
   */
  procedure update_prompt_profile(
    p_id                      in uc_ai_prompt_profiles.id%type,
    p_description             in uc_ai_prompt_profiles.description%type,
    p_system_prompt_template  in uc_ai_prompt_profiles.system_prompt_template%type,
    p_user_prompt_template    in uc_ai_prompt_profiles.user_prompt_template%type,
    p_provider                in uc_ai_prompt_profiles.provider%type,
    p_model                   in uc_ai_prompt_profiles.model%type,
    p_model_config_json       in uc_ai_prompt_profiles.model_config_json%type default null,
    p_response_schema         in uc_ai_prompt_profiles.response_schema%type default null,
    p_parameters_schema       in uc_ai_prompt_profiles.parameters_schema%type default null
  );


  /*
   * Updates an existing prompt profile by code and version
   * 
   * @param p_code                    Unique code for the prompt profile
   * @param p_version                 Version number
   * @param p_description             Description of the prompt profile
   * @param p_system_prompt_template  System prompt template with placeholders
   * @param p_user_prompt_template    User prompt template with placeholders
   * @param p_provider                AI provider
   * @param p_model                   Model name
   * @param p_model_config_json       Optional JSON configuration for model parameters
   * @param p_response_schema         Optional JSON schema for structured output
   * @param p_parameters_schema       Optional JSON schema defining expected parameters
   */
  procedure update_prompt_profile(
    p_code                    in uc_ai_prompt_profiles.code%type,
    p_version                 in uc_ai_prompt_profiles.version%type,
    p_description             in uc_ai_prompt_profiles.description%type,
    p_system_prompt_template  in uc_ai_prompt_profiles.system_prompt_template%type,
    p_user_prompt_template    in uc_ai_prompt_profiles.user_prompt_template%type,
    p_provider                in uc_ai_prompt_profiles.provider%type,
    p_model                   in uc_ai_prompt_profiles.model%type,
    p_model_config_json       in uc_ai_prompt_profiles.model_config_json%type default null,
    p_response_schema         in uc_ai_prompt_profiles.response_schema%type default null,
    p_parameters_schema       in uc_ai_prompt_profiles.parameters_schema%type default null
  );


  /*
   * Deletes a prompt profile by ID
   * 
   * @param p_id  ID of the prompt profile to delete
   */
  procedure delete_prompt_profile(
    p_id in uc_ai_prompt_profiles.id%type
  );


  /*
   * Deletes a prompt profile by code and version
   * 
   * @param p_code     Unique code for the prompt profile
   * @param p_version  Version number
   */
  procedure delete_prompt_profile(
    p_code    in uc_ai_prompt_profiles.code%type,
    p_version in uc_ai_prompt_profiles.version%type
  );


  /*
   * Changes the status of a prompt profile
   * 
   * @param p_id          ID of the prompt profile
   * @param p_status      New status: 'draft', 'active', or 'archived'
   */
  procedure change_status(
    p_id         in uc_ai_prompt_profiles.id%type,
    p_status     in uc_ai_prompt_profiles.status%type
  );


  /*
   * Changes the status of a prompt profile by code and version
   * 
   * @param p_code        Unique code for the prompt profile
   * @param p_version     Version number
   * @param p_status      New status: 'draft', 'active', or 'archived'
   */
  procedure change_status(
    p_code       in uc_ai_prompt_profiles.code%type,
    p_version    in uc_ai_prompt_profiles.version%type,
    p_status     in uc_ai_prompt_profiles.status%type
  );


  /*
   * Creates a new version of an existing prompt profile
   * 
   * Creates a copy of the specified profile with a new version number.
   * The new version starts in 'draft' status.
   * 
   * @param p_code                    Code of the existing prompt profile
   * @param p_source_version          Source version to copy from
   * @param p_new_version             New version number (if null, increments by 1)
   * 
   * @return id                       The ID of the new prompt profile version
   */
  function create_new_version(
    p_code           in uc_ai_prompt_profiles.code%type,
    p_source_version in uc_ai_prompt_profiles.version%type,
    p_new_version    in uc_ai_prompt_profiles.version%type default null
  ) return uc_ai_prompt_profiles.id%type;


  /*
   * Gets a prompt profile by ID
   * 
   * @param p_id  ID of the prompt profile
   * 
   * @return      The prompt profile record
   */
  function get_prompt_profile(
    p_id in uc_ai_prompt_profiles.id%type
  ) return uc_ai_prompt_profiles%rowtype;


  /*
   * Gets a prompt profile by code and version
   * 
   * @param p_code     Unique code for the prompt profile
   * @param p_version  Version number (if null, returns the latest active version)
   * 
   * @return           The prompt profile record
   */
  function get_prompt_profile(
    p_code    in uc_ai_prompt_profiles.code%type,
    p_version in uc_ai_prompt_profiles.version%type default null
  ) return uc_ai_prompt_profiles%rowtype;


  /*
   * Executes a prompt profile with parameter substitution
   * 
   * Replaces placeholders (#placeholder#) in system and user prompt templates
   * with values from the parameters JSON object. All substitutions are case-insensitive.
   * 
   * @param p_code                Code of the prompt profile to execute
   * @param p_version             Version number (if null, uses latest active version)
   * @param p_parameters          JSON object with key-value pairs for placeholder substitution
   * @param p_provider_override   Override the profile's provider setting
   * @param p_model_override      Override the profile's model setting
   * @param p_config_override     Override the profile's model_config_json setting
   * @param p_max_tool_calls      Maximum number of tool calls (passed to generate_text)
   * 
   * @return                      JSON object response from AI provider
   */
  function execute_profile(
    p_code              in uc_ai_prompt_profiles.code%type,
    p_version           in uc_ai_prompt_profiles.version%type default null,
    p_parameters        in json_object_t default null,
    p_provider_override in uc_ai_prompt_profiles.provider%type default null,
    p_model_override    in uc_ai_prompt_profiles.model%type default null,
    p_config_override   in json_object_t default null,
    p_max_tool_calls    in pls_integer default null
  ) return json_object_t;


  /*
   * Executes a prompt profile by ID with parameter substitution
   * 
   * @param p_id                  ID of the prompt profile to execute
   * @param p_parameters          JSON object with key-value pairs for placeholder substitution
   * @param p_provider_override   Override the profile's provider setting
   * @param p_model_override      Override the profile's model setting
   * @param p_config_override     Override the profile's model_config_json setting
   * @param p_max_tool_calls      Maximum number of tool calls (passed to generate_text)
   * 
   * @return                      JSON object response from AI provider
   */
  function execute_profile(
    p_id                in uc_ai_prompt_profiles.id%type,
    p_parameters        in json_object_t default null,
    p_provider_override in uc_ai_prompt_profiles.provider%type default null,
    p_model_override    in uc_ai_prompt_profiles.model%type default null,
    p_config_override   in json_object_t default null,
    p_max_tool_calls    in pls_integer default null
  ) return json_object_t;

end uc_ai_prompt_profiles_api;
/
