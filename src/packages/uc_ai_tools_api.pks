create or replace package uc_ai_tools_api as

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */


  gc_cohere constant varchar2(255 char) := 'cohere';


  /*
   * Returns array of all active tools formatted for specific AI provider
   *
   * This is what gets sent to AI models so they know what tools are available.
   */
  function get_tools_array (
    p_provider        in uc_ai.provider_type
  , p_additional_info in varchar2 default null
  ) return json_array_t;

  /*
   * Executes a tool by running its stored PL/SQL function
   * 
   * Finds the tool's function_call PL/SQL code, binds the arguments JSON as :ARGUMENTS,
   * executes it and returns the result. Only supports single bind variable for security.
   */
  function execute_tool(
    p_tool_code in uc_ai_tools.code%type
  , p_arguments in json_object_t
  ) return clob;


  /*
   * Returns the name of the tool's parent parameter that contains the JSON object
   * with the tool's arguments.
   */
  function get_tools_object_param_name (
    p_tool_code in uc_ai_tools.code%type
  ) return uc_ai_tool_parameters.name%type result_cache;

  /*
   * Creates a new tool definition from a JSON schema
   * 
   * Takes a JSON schema input and creates the corresponding records in
   * uc_ai_tools and uc_ai_tool_parameters tables.
   * 
   * @param p_tool_code          Unique code for the tool
   * @param p_description        Description of what the tool does
   * @param p_function_call      PL/SQL function that executes the tool
   * @param p_json_schema        JSON schema defining the tool parameters
   * @param p_active             Whether the tool is active (default 1)
   * @param p_version            Tool version (default '1.0')
   * @param p_authorization_schema Authorization schema if needed
   * @param p_created_by         User creating the tool
   * @param p_tags               Array of tags to associate with the tool
   * 
   * @return tool_id             The ID of the created tool
   */
  function create_tool_from_schema(
    p_tool_code             in uc_ai_tools.code%type,
    p_description           in uc_ai_tools.description%type,
    p_function_call         in uc_ai_tools.function_call%type,
    p_json_schema           in json_object_t,
    p_active                in uc_ai_tools.active%type default 1,
    p_version               in uc_ai_tools.version%type default '1.0',
    p_authorization_schema  in uc_ai_tools.authorization_schema%type default null,
    p_created_by            in uc_ai_tools.created_by%type default coalesce(sys_context('APEX$SESSION','app_user'), sys_context('userenv', 'session_user')),
    p_tags                  in apex_t_varchar2 default apex_t_varchar2()
  ) return uc_ai_tools.id%type;

end uc_ai_tools_api;
/
