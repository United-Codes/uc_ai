create or replace package pame_pkg as
  -- Package for Practical AI Made Easy (PAME)

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
  */


  procedure reset_global_variables;

  /**
  * Creates a new settlement record based on initial damage report
  * @param p_settlement_data JSON object containing the settlement information
  * @return CLOB containing success message with settlement ID or error message
  */
  function create_new_settlement(p_settlement_data in clob) return clob;

  /**
  * Gets user information by email address
  * @param p_email_data JSON object containing the email to search for
  * @return CLOB containing user information or error message
  */
  function get_user_info(p_email_data in clob) return clob;

  function get_tools_markdown return clob;

end pame_pkg;
/

