create or replace package uc_ai_tools_api 
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


  gc_cohere constant varchar2(255 char) := 'cohere';


  /*
   * Returns array of all active tools formatted for specific AI provider
   *
   * This is what gets sent to AI models so they know what tools are available.
   *
   * p_provider_tools (uc_ai.g_provider_tools) are raw, provider-native tool
   * definitions appended verbatim after the local function tools — executed
   * server-side by the provider, not locally. They are returned even when
   * p_enable_tools is false (local function tools disabled), so callers should
   * still attach the array whenever it is non-empty.
   */
  function get_tools_array (
    p_provider        in uc_ai.provider_type
  , p_additional_info in varchar2 default null
  , p_tool_tags       in apex_t_varchar2 default null
  , p_enable_tools    in boolean default null
  , p_provider_tools  in json_array_t default null
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
   * Fires the optional per-tool-call execution hook for a tool that is about to
   * run, extracting the caller/agent context from the per-call settings record.
   *
   * Providers MUST call this immediately before execute_tool, OUTSIDE any local
   * error handling that swallows tool failures (some providers turn a failed tool
   * into an error-string result and continue) — otherwise a hook veto meant to
   * stop the run would be swallowed. A raise from the hook propagates out of
   * generate_text and stops the run mid-flight. No-ops when no hook is installed.
   *
   * @param p_tool_code  uc_ai_tools.code about to be executed
   * @param p_settings   the current per-call settings (carries the exec context)
   */
  procedure before_tool_call(
    p_tool_code in uc_ai_tools.code%type
  , p_settings  in uc_ai_settings.t_settings default null
  );


  /*
   * Executes an inline PL/SQL function-call snippet (same contract as a tool's
   * function_call) without requiring a registered tool.
   *
   * Scans the snippet for bind variables (:PARAM_NAME) - only ONE is allowed for
   * security - binds the entire p_arguments JSON object to it, runs the snippet and
   * returns its CLOB result. Used by execute_tool and by workflow PL/SQL steps.
   *
   * @param p_function_call  PL/SQL function body returning a CLOB (e.g. 'return f(:parameters);')
   * @param p_arguments      JSON object bound to the single parameter
   * @return the CLOB returned by the snippet
   */
  function exec_function_call(
    p_function_call in clob
  , p_arguments     in json_object_t
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

  /*
   * Creates or updates a tool definition from a JSON schema
   *
   * Takes a JSON schema input and creates or updates the corresponding records in
   * uc_ai_tools, uc_ai_tool_parameters, and uc_ai_tool_tags tables.
   * If a tool with the same code already exists, it will be updated and its
   * parameters and tags will be replaced.
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
   * @return tool_id             The ID of the created or updated tool
   */
  function merge_tool_from_schema(
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
