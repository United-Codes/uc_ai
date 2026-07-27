create or replace package uc_ai_ptc_api
  authid definer
as

  /**
  * UC AI - Programmatic Tool Calling ("code mode") - tool gateway
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  *
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  *
  * Code mode lets the model author a small JavaScript program that orchestrates
  * many tool calls in-database (via Oracle MLE) and returns only the final
  * result, instead of round-tripping every tool call through the LLM. See the
  * "Programmatic Tool Calling" guide for the full picture.
  *
  * SECURITY: the model-authored JavaScript never runs in this (the install)
  * schema, and it cannot run SQL at all. It is evaluated by
  * UC_AI_MLE_SBX.uc_ai_ptc_runner in a PURE MLE execution context, which removes
  * every database-facing JavaScript API (no mle-js-oracledb via require or dynamic
  * import, no oracledb/session/soda/plsffi globals). Its tool calls are serviced
  * from PL/SQL by that runner, which - being owned by a dedicated NO AUTHENTICATION
  * low-privilege schema whose ONLY object privilege is EXECUTE on THIS package -
  * can itself reach nothing but this single gateway.
  *
  * This gateway is therefore the one, deliberately minimal, entry point the
  * sandbox is allowed to call. It enforces the per-run allow-list, call budget and
  * per-tool-call hook (uc_ai_tools_api.check_ptc_tool_allowed) before delegating to
  * the real tool executor, which runs with this schema's privileges.
  *
  * Requires Oracle MLE JavaScript with PURE contexts (23ai+). Installed only by
  * scripts/install_ptc_sandbox.sql, never by the core installer, so the
  * documented 12.2 minimum is unaffected.
  */

  /*
   * Bridge target invoked by the runner for a program's await callTool(name, args).
   *
   * Validates the requested tool against the current code-mode run's allow-list
   * and inner-call budget and fires the per-tool-call hook (raises if not
   * permitted), then delegates to the tool executor. Kept as the single, minimal
   * seam the sandbox schema is granted EXECUTE on.
   *
   * @param p_tool_code  uc_ai_tools.code of the tool to run
   * @param p_args_json  the tool arguments, serialized as a JSON string
   * @return the tool's CLOB result (typically JSON)
   */
  function call_tool_json(
    p_tool_code in uc_ai_tools.code%type
  , p_args_json in clob
  ) return clob;

end uc_ai_ptc_api;
/
