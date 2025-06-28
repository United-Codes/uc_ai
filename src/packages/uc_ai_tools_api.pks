/*
 * UC AI Tools API Package
 * 
 * Core package for managing and executing AI tools configured in the database.
 * Tools are defined with parameters and JSON schemas that conform to OpenAI function calling format.
 * 
 * Key workflow:
 * 1. Tools are stored in uc_ai_tools table with PL/SQL function calls
 * 2. Parameters defined in uc_ai_tool_parameters with JSON schema validation rules
 * 3. AI models call get_tools_array() to get available tools
 * 4. When AI wants to use a tool, execute_tool() runs the PL/SQL function with arguments
 * 5. Tool result is returned to AI for further processing
 */
create or replace package uc_ai_tools_api as

  /*
   * Builds JSON schema for a specific tool's parameters
   * 
   * Converts database parameter definitions into proper JSON schema format
   * that AI models can understand for function calling.
   * Handles nested objects, arrays, validation rules (min/max, patterns, enums).
   */
  function get_tool_schema(
    p_tool_id in uc_ai_tools.id%type
  ) 
    return json_object_t 
  ;

  /*
   * Returns array of all active tools formatted for specific AI provider
   * 
   * p_flavor: 'openai' wraps tools in {type: "function", function: {...}} format
   *           other values return tools in direct anthropic/claude format
   * 
   * This is what gets sent to AI models so they know what tools are available.
   */
  function get_tools_array (
    p_flavor in varchar2 default 'openai'
  ) return json_array_t;

  /*
   * Executes a tool by running its stored PL/SQL function
   * 
   * p_tool_code: the 'code' field from uc_ai_tools table (tool identifier)
   * p_arguments: JSON object with parameters the AI wants to pass
   * 
   * Finds the tool's function_call PL/SQL code, binds the arguments JSON as :ARGUMENTS,
   * executes it and returns the result. Only supports single bind variable for security.
   */
  function execute_tool(
    p_tool_code in uc_ai_tools.code%type
  , p_arguments in json_object_t
  ) return clob;

end uc_ai_tools_api;
/
