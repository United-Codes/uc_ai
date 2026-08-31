create or replace package ap_naive_pkg
  authid definer
as
  /**
  * UC AI tutorial — "Secure an Agent" — lesson 1 ONLY
  *
  * ############################################################################
  * #  THIS PACKAGE IS DELIBERATELY UNSAFE. DO NOT COPY IT.                    #
  * #                                                                          #
  * #  It exists so lesson 1 can show what a first draft of a tool-calling      #
  * #  agent looks like, and what a supplier can make it do. Every handler      #
  * #  below acts on arguments that the model chose, and the model chose them   #
  * #  from an email a stranger wrote.                                         #
  * #                                                                          #
  * #  Lesson 2 drops this package. So does 00_teardown.sql. If it is still in  #
  * #  your schema after lesson 2, drop it.                                     #
  * #                                                                          #
  * #  The safe version of the same desk is ap_desk_pkg, from lesson 3.         #
  * ############################################################################
  */

  /* Tool AP_GET_INVOICE_N — one invoice, chosen by the model. */
  function get_invoice(p_arguments in clob) return clob;

  /* Tool AP_READ_EMAIL_N — the covering mail, raw, with no label on it. */
  function read_email(p_arguments in clob) return clob;

  /*
   * Tool AP_APPROVE_INVOICE_N — approves an invoice.
   *
   * Three parameters, and the model chooses all three. There is no goods-receipt
   * check, no clerk, no entity check and no limit. The only thing that decides
   * what gets approved is what the model asked for.
   */
  function approve_invoice(p_arguments in clob) return clob;

  /*
   * Tool AP_UPDATE_VENDOR_BANK_N — changes where a supplier is paid.
   *
   * This is the tool the course is about. No agent needs it, and lesson 2
   * removes it.
   */
  function update_vendor_bank(p_arguments in clob) return clob;

  /* Tool AP_SEND_VENDOR_REPLY_N — writes free text to the outbound table. */
  function send_vendor_reply(p_arguments in clob) return clob;

end ap_naive_pkg;
/
