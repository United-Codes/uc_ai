create or replace package uc_ai_ptc_runner
  authid definer
as

  /**
  * UC AI - Programmatic Tool Calling ("code mode") - MLE runner
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  *
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  *
  * THIS PACKAGE IS INSTALLED INTO THE DEDICATED LOW-PRIVILEGE SANDBOX SCHEMA
  * (default UC_AI_MLE_SBX) by scripts/install_ptc_sandbox.sql - never into the
  * UC AI install schema.
  *
  * It runs the model-authored JavaScript via Oracle MLE in a PURE (restricted)
  * execution context. In a PURE context MLE removes every database-facing API
  * from the JavaScript: mle-js-oracledb cannot be required or dynamically
  * imported, and the oracledb/session/soda/plsffi globals do not exist. The
  * generated program therefore cannot run SQL at all - it cannot read data, and
  * it cannot COMMIT or ROLLBACK the caller's transaction either (transaction
  * control needs no privilege, so a privilege wall alone would not stop it).
  *
  * Because the program has no SQL access, callTool() is serviced from PL/SQL:
  * the program awaits a tool call, control returns here, this package calls the
  * UC AI gateway (uc_ai_ptc_api, reachable through a private synonym - the one
  * object this schema is granted EXECUTE on) and resumes the program with the
  * result. Tools therefore run in the CALLER's transaction, exactly like a direct
  * tool call, and stay in full control of their own transaction handling.
  *
  * The low-privilege schema ownership is kept as defense in depth: even if the
  * JavaScript could reach SQL, the definer's rights of this package give it only
  * this schema's (near-zero) privileges with roles disabled.
  *
  * Requires Oracle MLE JavaScript with PURE execution contexts (23ai+).
  */

  /*
   * Runs a model-authored JavaScript program inside a PURE MLE context.
   *
   * The program is executed as the body of an async function, so it may await
   * callTool(name, argsObject) -> parsed result any number of times, and returns
   * its final answer by assigning to a top-level variable named `result`. Only
   * that value flows back. Any error (JS error, disallowed tool, budget exceeded,
   * tool failure) is returned AS DATA (a JSON { error, hint }) so the model can
   * correct itself on its next turn instead of aborting the run.
   *
   * @param p_code  the JavaScript source to execute
   * @return the value the program assigned to `result` (as a CLOB), or an error JSON
   */
  function run_code(
    p_code in clob
  ) return clob;

end uc_ai_ptc_runner;
/
