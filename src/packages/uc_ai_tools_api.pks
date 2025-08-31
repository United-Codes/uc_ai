create or replace package uc_ai_tools_api as

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
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

end uc_ai_tools_api;
/
