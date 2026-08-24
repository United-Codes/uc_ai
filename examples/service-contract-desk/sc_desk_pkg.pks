create or replace package sc_desk_pkg
  authid definer
as
  /**
  * UC AI tutorial — "Build an Agent"
  *
  * The tool handlers of the service-contract desk.
  *
  * Every function here is the target of one UC AI function tool. Each one takes
  * the tool arguments as a JSON CLOB and returns a CLOB that goes back to the
  * model.
  *
  * Two rules hold for every handler:
  *
  * 1. The contract comes from the RUN CONTEXT, never from the model. UC AI adds
  *    the run context to the arguments under the reserved key `_ctx`, after the
  *    model produced them. No tool below declares a contract parameter, so the
  *    model cannot name a contract at all.
  *
  * 2. A refusal is a RESULT, not an error. When the database declines a request,
  *    the handler returns a JSON object that says why, in a `message` the model
  *    can read out to the user and a `reason` code your own code can test. An
  *    exception could not be explained to the user.
  */

  -- The `reason` values raise_credit_note returns when it refuses. A refusal is
  -- always one of these, so a test can assert WHICH rule refused without reading
  -- the message that is meant for the model.
  subtype reason_type is varchar2(32 char);
  c_reason_no_contract      constant reason_type := 'NO_CONTRACT';
  c_reason_unknown_invoice  constant reason_type := 'UNKNOWN_INVOICE';
  c_reason_wrong_contract   constant reason_type := 'WRONG_CONTRACT';
  c_reason_out_of_window    constant reason_type := 'OUT_OF_WINDOW';
  c_reason_not_entitled     constant reason_type := 'NOT_ENTITLED';
  c_reason_already_credited constant reason_type := 'ALREADY_CREDITED';
  c_reason_amount_too_high  constant reason_type := 'AMOUNT_TOO_HIGH';
  c_reason_bad_amount       constant reason_type := 'BAD_AMOUNT';

  /*
   * Reads the contract this run is bound to out of the tool arguments.
   * Returns null when the run carries no contract.
   */
  function bound_contract_id(p_arguments in clob) return number;

  /*
   * Tool SC_GET_CONTRACT — the contract of this run, with its customer and its
   * coverage window. Takes no arguments beyond the run context.
   */
  function get_contract(p_arguments in clob) return clob;

  /*
   * Tool SC_LIST_CALLS — the service calls of this run's contract, newest first.
   * Optional argument: max_rows.
   */
  function list_calls(p_arguments in clob) return clob;

  /*
   * Tool SC_LIST_INVOICES — the invoices of this run's contract, with how much
   * of each one is already credited. Optional argument: max_rows.
   */
  function list_invoices(p_arguments in clob) return clob;

  /*
   * Tool SC_RAISE_CREDIT_NOTE — raises a credit note against one invoice.
   *
   * Arguments: invoice_no (required), amount (required), reason (optional).
   *
   * The database decides. A credit note is created only when all four hold:
   *   1. the invoice belongs to the contract bound to this run
   *   2. the service call falls inside the contract's coverage window
   *   3. the coverage level entitles the amount (GOLD covers parts and labour,
   *      SILVER covers labour only)
   *   4. the amount does not exceed what is still uncredited on that invoice
   *
   * Returns, on success:
   *   {"status":"created","credit_note":"CN-9002","amount":780,"invoice_no":"INV-1001"}
   *
   * and on a refusal:
   *   {"status":"refused","reason":"OUT_OF_WINDOW","message":"..."}
   *
   * where `reason` is one of the c_reason_* constants above. It never raises for
   * a business refusal.
   */
  function raise_credit_note(p_arguments in clob) return clob;

end sc_desk_pkg;
/
