create or replace package uc_ai_logger authid definer as

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
  */

  -- Type definitions matching logger package 
  type rec_param is record ( -- @dblinter ignore(g-9111): compliant with real logger
    name varchar2(255 char),
    val varchar2(4000 char)
  );

  type tab_param is table of rec_param index by binary_integer; -- @dblinter ignore(g-9112): compliant with real logger

  subtype scope is varchar2(100 char); -- @dblinter ignore(g-9115): compliant with real logger

  gc_empty_tab_param constant tab_param := tab_param();

  /**
   * Log error message
   *
   * @param p_text Error message text
   * @param p_scope Scope/context of the error
   * @param p_extra Additional information
   * @param p_params Array of parameters
   */
  procedure log_error(
    p_text in varchar2 default null,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default uc_ai_logger.gc_empty_tab_param);

  /**
   * Log warning message
   *
   * @param p_text Warning message text
   * @param p_scope Scope/context of the warning
   * @param p_extra Additional information
   * @param p_params Array of parameters
   */
  procedure log_warning(
    p_text in varchar2,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default uc_ai_logger.gc_empty_tab_param);

  /**
   * Log warning message (alias)
   *
   * @param p_text Warning message text
   * @param p_scope Scope/context of the warning
   * @param p_extra Additional information
   * @param p_params Array of parameters
   */
  procedure log_warn(
    p_text in varchar2,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default uc_ai_logger.gc_empty_tab_param);

  /**
   * Log info message
   *
   * @param p_text Info message text
   * @param p_scope Scope/context of the message
   * @param p_extra Additional information
   * @param p_params Array of parameters
   */
  procedure log_info(
    p_text in varchar2,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default uc_ai_logger.gc_empty_tab_param);

  /**
   * Log debug message
   *
   * @param p_text Debug message text
   * @param p_scope Scope/context of the message
   * @param p_extra Additional information
   * @param p_params Array of parameters
   */
  procedure log(
    p_text in varchar2,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default uc_ai_logger.gc_empty_tab_param);

  /**
   * Enable APEX debug logging if you are currently not having an APEX session
   * You don't need to call this when:
   *  - you use logger
   *  - your PL/SQL code using UC AI is called from an APEX application
   *
   * @param p_text Debug message text
   */
  procedure enable_apex_debug(p_workspace in varchar2);

end uc_ai_logger;
/
