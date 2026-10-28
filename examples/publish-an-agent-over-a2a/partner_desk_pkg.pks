create or replace package partner_desk_pkg
  authid definer
as
  /**
  * UC AI tutorial — "Publish an Agent over A2A"
  *
  * The tool handlers of the partner service desk, and the booking rule.
  *
  * Every handler takes the tool arguments as a JSON CLOB and returns a CLOB that
  * goes back to the model. Three rules hold for all of them:
  *
  * 1. The partner comes from the RUN CONTEXT, never from the model. For an A2A
  *    run, UC AI adds the key `a2a_client` (for example 'apikey:ferrolux') to
  *    the arguments under `_ctx`, after the model produced them. The handler
  *    looks the client up in partner_clients. No tool declares a customer
  *    parameter, so the model cannot name another customer.
  *
  * 2. A refusal is a RESULT, not an error. The handler returns a JSON object
  *    with a `reason` code for your own code and a `message` for the model.
  *
  * 3. No handler commits. The A2A server owns the transaction of a run: it
  *    commits when the run completes and rolls back when the run fails.
  */

  subtype reason_type is varchar2(32 char);
  c_reason_unknown_client constant reason_type := 'UNKNOWN_CLIENT';
  c_reason_no_asset       constant reason_type := 'NO_ASSET';
  c_reason_bad_date       constant reason_type := 'BAD_DATE';
  c_reason_out_of_cover   constant reason_type := 'OUT_OF_COVERAGE';
  c_reason_open_request   constant reason_type := 'OPEN_REQUEST';
  c_reason_too_soon       constant reason_type := 'TOO_SOON';

  -- A visit needs this many working days between today and the visit.
  c_notice_working_days constant pls_integer := 2;

  /*
   * The customer of the client in the run context. Returns null when the run has
   * no client, or when the client is not in partner_clients.
   */
  function client_customer_id(p_arguments in clob) return number;

  /*
   * The date that is the given number of working days after p_from. A working day
   * is Monday to Friday. Holidays are not modelled. The weekday test does not
   * depend on NLS settings.
   */
  function add_working_days(
    p_from in date
  , p_days in pls_integer
  ) return date;

  /*
   * The booking rule on plain values. Returns null when a visit on p_date is
   * allowed, or the reason code of the FIRST rule that refuses:
   *   1. NO_ASSET         the asset does not exist, or belongs to another customer
   *   2. OUT_OF_COVERAGE  p_date is outside the coverage window of the contract
   *   3. OPEN_REQUEST     the asset has a visit with the status REQUESTED
   *   4. TOO_SOON         p_date is less than c_notice_working_days working days
   *                       after p_today
   * p_today is a parameter so a test can fix it. It does not touch the clock.
   */
  function check_visit(
    p_asset_id    in number
  , p_date        in date
  , p_customer_id in number
  , p_today       in date default trunc(sysdate)
  ) return reason_type;

  /* Tool PARTNER_LIST_ASSETS: the machines of the customer of this client. */
  function list_assets(p_arguments in clob) return clob;

  /* Tool PARTNER_ASSET_HISTORY: the service calls of one machine. Argument: asset_tag. */
  function get_asset_history(p_arguments in clob) return clob;

  /*
   * Tool PARTNER_BOOK_VISIT: asks for a visit. Arguments: asset_tag, visit_date
   * (YYYY-MM-DD). Inserts one partner_visits row with the status REQUESTED when
   * check_visit allows it. A person at the service company confirms the request.
   */
  function book_visit(p_arguments in clob) return clob;

end partner_desk_pkg;
/
