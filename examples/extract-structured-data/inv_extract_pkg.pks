create or replace package inv_extract_pkg as
  /*
   * UC AI tutorial — "Extract structured data from a PDF"
   *
   * The invoice inbox: read one PDF, check what came back, and post it.
   *
   * The four procedures below are the four things a document pipeline does, and
   * the course builds them in that order:
   *
   *   extract_document   lesson 2   send the PDF, keep the answer as it arrived
   *   validate_extraction lesson 3  decide whether a person must look at it
   *   post_extraction    lesson 4   header and lines, in one transaction
   *   run_inbox          lesson 5   all three, for every new document
   *
   * The rule the whole package follows: the model reads, the database decides.
   * Nothing here trusts a value because the answer sounded confident.
   */

  -- The extraction prompt and its schema. Lesson 5 moves both onto a prompt
  -- profile, where a new version is a row instead of a deployment.
  c_model constant uc_ai.model_type := uc_ai_openai.c_model_gpt_5_6_terra;

  -- The profile and the agent that lesson 5 registers.
  c_profile_code constant varchar2(30 char) := 'INV_EXTRACT';
  c_agent_code   constant varchar2(30 char) := 'INV_EXTRACT_AGENT';

  /*
   * Sends one document to the model and keeps the answer.
   *
   * Writes one row to inv_extractions, whatever happens: the JSON on success,
   * error_message on a failure. Sets inv_documents.status to EXTRACTED or
   * FAILED. Does NOT commit, so the caller owns the transaction.
   *
   * Returns the id of the inv_extractions row.
   */
  function extract_document (
    p_document_id in inv_documents.id%type
  ) return inv_extractions.id%type;

  /*
   * The same thing, through an agent.
   *
   * Sends the document with uc_ai_agents_api.execute_agent instead of calling
   * uc_ai.generate_text directly. The answer is identical. What you get on top is
   * a row in uc_ai_agent_executions, the messages of the run in
   * uc_ai_agent_messages, and the tokens counted for you.
   *
   * Needs the INV_EXTRACT profile and the INV_EXTRACT_AGENT agent, both active.
   * 05_inbox.sql creates them.
   *
   * Returns the id of the inv_extractions row.
   */
  function extract_with_agent (
    p_document_id in inv_documents.id%type
  ) return inv_extractions.id%type;

  /*
   * Runs the five checks over one extraction.
   *
   * Returns the reasons a person must look at this document, separated by a
   * comma, and an empty string when the document is clean. Reads the database;
   * never calls a model.
   *
   * NOT_AN_INVOICE   the document says it is something else
   * SUM_MISMATCH     the amounts on the document do not agree with each other
   * DATE_AMBIGUOUS   the printed date can be read as two different days
   * PO_NOT_FOUND     no purchase order, or one that is unknown or closed
   * OVER_PO          more than the purchase order allows
   */
  function validate_extraction (
    p_extraction_id in inv_extractions.id%type
  ) return varchar2;

  /*
   * Writes the header and its lines from one extraction.
   *
   * Runs validate_extraction and stores what it said. A document that needs a
   * review is still posted: needs_review is 'Y' and review_reasons names why.
   * Two documents are never posted: one that is not an invoice, and one with no
   * invoice number to key it by. Both get status REVIEW instead.
   *
   * Raises -20901 when this invoice number is already posted for this supplier,
   * and -20902 when this document is already posted. Does not commit.
   *
   * Returns the id of the inv_invoices row, or null when nothing was posted.
   */
  function post_extraction (
    p_extraction_id in inv_extractions.id%type
  ) return inv_invoices.id%type;

  /*
   * Extracts, checks and posts every document with status NEW, through the agent.
   *
   * Commits after each document, so one bad PDF does not roll back the good
   * ones before it. A failure sets the document to FAILED, records the message on
   * its extraction row, and the loop goes on.
   *
   * Returns how many documents it handled without an error. A document that went
   * to REVIEW is handled. A document that failed is not.
   */
  function run_inbox return pls_integer;

end inv_extract_pkg;
/
