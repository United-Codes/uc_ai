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

  -- Reserved tool code for the programmatic tool-calling ("code mode") meta-tool.
  -- Not a row in uc_ai_tools; get_tools_array synthesizes it when p_programmatic_tools is
  -- true, and execute_agent_tool routes it to the sandboxed MLE runner instead of
  -- execute_tool.
  c_code_mode_tool_code constant varchar2(30 char) := 'uc_ai__run_code';

  -- Local synonym pointing at the MLE runner in the dedicated low-privilege sandbox
  -- schema (code mode runs there, never in the install schema). Both schema names are
  -- chosen by the DBA running scripts/install_ptc_sandbox.sql, which creates this
  -- synonym in THIS schema - so the runner is located at runtime and every UC AI
  -- install in the database gets its own sandbox.
  c_ptc_runner_synonym constant varchar2(30 char) := 'UC_AI_PTC_RUNNER';


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
  , p_programmatic_tools       in boolean default false
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
   * Provider-facing tool executor that is aware of code mode.
   *
   * For a normal tool this is just execute_tool. For the code-mode meta-tool
   * (c_code_mode_tool_code) it runs the model-authored JavaScript in the
   * dedicated low-privilege sandbox schema (via the c_ptc_runner_synonym synonym),
   * having first published this run's allow-list + inner-call budget (derived from
   * p_settings) so the gateway can enforce them. Raises a clear error if code mode
   * is requested but the sandbox is not installed.
   *
   * Tools called by the program run in the CALLER's transaction, exactly like a
   * direct tool call, so tools stay in charge of their own transaction handling.
   * The generated JavaScript itself cannot commit or roll back anything: the runner
   * evaluates it in a PURE MLE context, which has no SQL access at all, and services
   * every callTool() from PL/SQL.
   *
   * A nested code-mode run (a program calling an agent-as-tool whose agent uses
   * code mode) saves and restores the outer run's context.
   *
   * Providers call this in place of execute_tool; they keep their own
   * before_tool_call invocation and error handling unchanged. The hook is fired
   * again per inner callTool() (see check_ptc_tool_allowed).
   *
   * @param p_tool_code  tool code (or c_code_mode_tool_code)
   * @param p_arguments  the tool arguments (for code mode: { "code": "<js>" })
   * @param p_settings   per-call settings (supplies tool_tags / enable_tools)
   * @return the tool's (or the program's) CLOB result
   */
  function execute_agent_tool(
    p_tool_code in uc_ai_tools.code%type
  , p_arguments in json_object_t
  , p_settings  in uc_ai_settings.t_settings default null
  ) return clob;

  /*
   * Guard called by the uc_ai_ptc_api gateway for every callTool() from inside a
   * code-mode program. Raises c_err_invalid_config if the requested tool is not
   * part of the current run's exposed (enabled + tag-filtered) set, or if the
   * inner-call budget for this run is exceeded. Only meaningful inside a run
   * bracketed by execute_agent_tool (raises otherwise).
   *
   * It also fires the per-tool-call hook (before_tool_call) for the inner call, so
   * hook-based authorization and auditing cover tools called from a program. A veto
   * blocks the call and makes execute_agent_tool abort the request after the run.
   */
  procedure check_ptc_tool_allowed(
    p_tool_code in uc_ai_tools.code%type
  );


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
   * @param p_code_mode_access   Code-mode availability: 'direct' (normal tool only),
   *                             'code' (only callable via callTool in a program), or
   *                             'both' (default)
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
    p_tags                  in apex_t_varchar2 default apex_t_varchar2(),
    p_code_mode_access      in uc_ai_tools.code_mode_access%type default 'both'
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
   * @param p_code_mode_access   Code-mode availability: 'direct' (normal tool only),
   *                             'code' (only callable via callTool in a program), or
   *                             'both'. Null (the default) keeps the value already
   *                             stored for an existing tool and uses 'both' for a
   *                             new one, so re-running a merge script never widens
   *                             a tool that was deliberately narrowed.
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
    p_tags                  in apex_t_varchar2 default apex_t_varchar2(),
    p_code_mode_access      in uc_ai_tools.code_mode_access%type default null
  ) return uc_ai_tools.id%type;

end uc_ai_tools_api;
/
