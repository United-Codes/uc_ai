create or replace package cc_analyst_pkg
  authid definer
as
  /**
  * UC AI tutorial — "Analyze Data at Scale"
  *
  * Two things live in this package:
  *
  * 1. The TOOL HANDLERS of the cold-chain analyst. Each function is the target
  *    of one UC AI function tool. Each one takes the tool arguments as a JSON
  *    CLOB and returns a CLOB that goes back to the model — or, in code mode,
  *    to the JavaScript program the model wrote.
  *
  * 2. The MEASURING helpers. This course is about a number: what one question
  *    costs. print_metrics writes one line for each run, in the same shape every
  *    time, so the comparison table at the end is assembled from real runs and
  *    not from memory.
  *
  * Two rules hold for every handler:
  *
  * - Read the arguments BY NAME. Every tool also receives the run context under
  *   the reserved key `_ctx`, so a handler that reasons about the shape of its
  *   arguments is wrong.
  *
  * - A refusal is a RESULT, not an error. file_claim returns a JSON object that
  *   says why it declined. In code mode this matters twice: an exception from a
  *   tool reaches the program as a rejected promise, and the model then has to
  *   guess what happened.
  */

  -- The `reason` values file_claim returns when it refuses.
  subtype reason_type is varchar2(32 char);
  c_reason_unknown_shipment constant reason_type := 'UNKNOWN_SHIPMENT';
  c_reason_no_excursion     constant reason_type := 'NO_EXCURSION';
  c_reason_wrong_amount     constant reason_type := 'WRONG_AMOUNT';
  c_reason_already_filed    constant reason_type := 'ALREADY_FILED';

  /*
   * Tool CC_LIST_SHIPMENTS — every shipment, with its id and its product class.
   * Optional argument: product_class ('FROZEN' or 'CHILLED').
   */
  function list_shipments(p_arguments in clob) return clob;

  /*
   * Tool CC_GET_READINGS — the temperature readings of ONE shipment, in time
   * order. Required argument: shipment_id (the numeric id, not the shipment
   * number).
   *
   * This is the bulk tool of the course. It returns 49 readings, which is about
   * 2 KB of JSON and about 500 tokens. Twenty-four of these calls is the whole
   * problem.
   */
  function get_readings(p_arguments in clob) return clob;

  /*
   * Tool CC_GET_LIMITS — the temperature limit and the claim rule of each
   * product class. Takes no arguments.
   */
  function get_limits(p_arguments in clob) return clob;

  /*
   * Tool CC_FILE_CLAIM — files one claim against one shipment.
   *
   * Arguments: shipment_id (required), minutes_over (required),
   *            amount_eur (required), note (optional).
   *
   * The DATABASE decides. The claim is written only when all three hold:
   *   1. the shipment exists
   *   2. the shipment really broke the cold chain, by the run-length rule
   *   3. minutes_over and amount_eur match what the database computes
   *
   * So the model cannot file a claim for a shipment that only looked warm, and
   * it cannot file one for the wrong amount.
   */
  function file_claim(p_arguments in clob) return clob;

  /*
   * The excursion rule, in SQL, for one shipment. Returns the total minutes
   * this shipment spent in runs that are LONGER than its class allows. Returns
   * 0 when the shipment never broke the cold chain.
   *
   * This is the ground truth of the whole course. file_claim checks against it,
   * and the verification blocks of the lessons print it.
   */
  function minutes_over(p_shipment_id in number) return number;

  /*
   * True when the model answered with a program instead of calling tools one at
   * a time. Reads the messages array of a generate_text result and looks for a
   * tool call named uc_ai__run_code.
   */
  function used_program(p_result in json_object_t) return boolean;

  /*
   * How many times UC AI called the provider for this result. One assistant
   * message is one HTTPS request.
   */
  function round_trips(p_result in json_object_t) return pls_integer;

  /*
   * The JavaScript the model wrote, or null when it wrote none. Lesson 3 prints
   * this.
   */
  function program_source(p_result in json_object_t) return clob;

  /*
   * One line of measurement for one run, on dbms_output. Print the header first
   * with print_header.
   */
  procedure print_header;

  procedure print_metrics(
    p_label   in varchar2
  , p_result  in json_object_t
  , p_seconds in number default null
  );

end cc_analyst_pkg;
/
