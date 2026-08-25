create or replace package ap_desk_pkg
  authid definer
as
  /**
  * UC AI tutorial — "Secure an Agent"
  *
  * The tool handlers of the payables desk, in the shape the course argues for.
  * Compare each one with ap_naive_pkg, which lesson 1 attacks.
  *
  * Four rules hold for every handler here.
  *
  * 1. THE MODEL CHOOSES AS LITTLE AS POSSIBLE. The invoice and the clerk come
  *    from the run context, which UC AI adds to the arguments under the reserved
  *    key `_ctx` after the model produced them. The amount is not an argument at
  *    all: it is read from the invoice row. approve_invoice therefore has one
  *    parameter the model may choose, and it is a sentence of explanation.
  *
  * 2. THE RUN CONTEXT CARRIES IDENTITY. THE DATABASE HOLDS AUTHORITY. `_ctx`
  *    says which clerk is asking. ap_clerks says what that clerk may approve. A
  *    limit that travelled in `_ctx` would be a limit the caller could raise.
  *
  * 3. UNTRUSTED TEXT ARRIVES LABELLED. read_supplier_email and get_vendor mark
  *    the text a stranger wrote, and the delimiter carries the row id so a
  *    forged closing marker inside the text cannot close the real one. The label
  *    lowers how often a model is fooled. It decides nothing.
  *
  * 4. A REFUSAL IS A RESULT, NOT AN ERROR, and a real error never reaches the
  *    model. A refusal returns `reason` for your tests and `message` for the
  *    model. An unexpected exception is logged to ap_desk_errors and the model
  *    is given a reference, never sqlerrm.
  */

  -- The `reason` values a refusal carries. A test asserts on these, never on the
  -- message, which is written for a model to read out.
  subtype reason_type is varchar2(32 char);
  c_reason_no_invoice       constant reason_type := 'NO_INVOICE';
  c_reason_unknown_invoice  constant reason_type := 'UNKNOWN_INVOICE';
  c_reason_unknown_clerk    constant reason_type := 'UNKNOWN_CLERK';
  c_reason_not_authorized   constant reason_type := 'NOT_AUTHORIZED';
  c_reason_wrong_entity     constant reason_type := 'WRONG_ENTITY';
  c_reason_vendor_blocked   constant reason_type := 'VENDOR_BLOCKED';
  c_reason_no_goods_receipt constant reason_type := 'NO_GOODS_RECEIPT';
  c_reason_already_approved constant reason_type := 'ALREADY_APPROVED';
  c_reason_above_limit      constant reason_type := 'ABOVE_LIMIT';
  c_reason_unknown_template constant reason_type := 'UNKNOWN_TEMPLATE';
  c_reason_not_approved     constant reason_type := 'NOT_APPROVED';
  c_reason_blocked_content  constant reason_type := 'BLOCKED_CONTENT';
  c_reason_internal         constant reason_type := 'INTERNAL';

  /* The invoice this run is bound to, or null when the run carries none. */
  function bound_invoice_id(p_arguments in clob) return number;

  /* The clerk this run is bound to, or null when the run carries none. */
  function bound_clerk(p_arguments in clob) return varchar2;

  /*
   * How many lines of a text read like an instruction to a machine rather than
   * a sentence to a person. Computed here, in PL/SQL, so the number is evidence
   * your code produced and not a claim the model made.
   */
  function count_instruction_lines(p_text in clob) return pls_integer;

  /*
   * Tool AP_GET_INVOICE — the invoice of this run, with the vendor, the gross
   * amount, and whether a goods receipt exists. Takes no arguments.
   *
   * It returns no bank account. A tool that need not read the payout account is
   * a tool that cannot leak it.
   */
  function get_invoice(p_arguments in clob) return clob;

  /*
   * Tool AP_GET_VENDOR — the vendor of the invoice of this run. Takes no
   * arguments and returns no IBAN.
   *
   * When the vendor maintains its own master data through a portal, the NAME is
   * text an outsider wrote, so it comes back wrapped and marked untrusted even
   * though it lives in a table of your own.
   */
  function get_vendor(p_arguments in clob) return clob;

  /*
   * Tool AP_READ_SUPPLIER_EMAIL — the covering mail of the invoice of this run,
   * wrapped and attributed. Takes no arguments.
   */
  function read_supplier_email(p_arguments in clob) return clob;

  /*
   * Tool AP_READ_SUPPLIER_EMAIL_RAW — the SAME mail with no wrapper and no
   * warning, exactly as ap_naive_pkg returned it.
   *
   * It exists for one reason: lesson 4 measures the labeled tool against the
   * unlabeled one, and a measurement needs both arms. Nothing else uses it, and
   * 00_teardown.sql removes its tool row.
   */
  function read_supplier_email_raw(p_arguments in clob) return clob;

  /*
   * Tool AP_APPROVE_INVOICE — approves the invoice of this run for payment.
   *
   * The model may choose ONE thing: `note`, a sentence of explanation. Nothing
   * it can write selects the invoice, the amount, the clerk or the authority.
   *
   * The database decides. The approval is written only when all seven hold:
   *   1. the run is bound to an invoice that exists
   *   2. the run is bound to a clerk that exists and is active
   *   3. the entity of the invoice is the entity of the clerk
   *   4. the vendor is not blocked
   *   5. a goods receipt is recorded against the invoice
   *   6. the invoice is not approved already
   *   7. the gross amount is at or below the approval limit of that clerk
   *
   * Returns, on success:
   *   {"status":"approved","approval_no":"AP-5002","invoice_no":"INV-88001",
   *    "amount":5712,"approved_by":"petra.k"}
   * and on a refusal:
   *   {"status":"refused","reason":"NO_GOODS_RECEIPT","message":"..."}
   *
   * It never raises for a business refusal, and it never commits.
   */
  function approve_invoice(p_arguments in clob) return clob;

  /*
   * Tool AP_SEND_VENDOR_REPLY — queues one standard reply to the supplier of the
   * invoice of this run.
   *
   * The model chooses a template CODE, never prose, and never an address: the
   * body is rendered from ap_reply_templates and the address is read from the
   * vendor row. The model has no field it can write text into.
   *
   * The vendor NAME is a different matter. For a portal-managed vendor it is text
   * the supplier typed, so the rendered reply uses the vendor number instead: a
   * template that pasted that name into an outgoing mail would carry the
   * supplier's own text back out of this company under our letterhead.
   *
   * APPROVED_FOR_PAYMENT is refused unless the invoice really is approved, so the
   * model cannot promise a payment the database did not allow.
   */
  function send_vendor_reply(p_arguments in clob) return clob;

  /*
   * Records an unexpected error and returns the reference to quote. The model is
   * told the reference. It is never told sqlerrm.
   */
  function log_error(
    p_message   in varchar2
  , p_backtrace in clob default null
  ) return varchar2;

end ap_desk_pkg;
/
