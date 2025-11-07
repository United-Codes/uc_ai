create or replace package body uc_ai_logger as

  /**
   * Convert parameters to string for logging
   */
  function params_to_string(p_params in tab_param)
    return varchar2
  is
    l_result varchar2(32767 char);
  begin
    if p_params.count > 0 then
      <<params_loop>>
      for i in 1 .. p_params.count loop
        if l_result is not null then
          l_result := l_result || ', ';
        end if;
        l_result := l_result || p_params(i).name || '=' || p_params(i).val;
      end loop params_loop;
      return ' [' || l_result || ']';
    end if;
    return null;
  end params_to_string;

  /**
   * Build full message with scope, extra, and params
   */
  function build_message(
    p_text in varchar2,
    p_scope in varchar2,
    p_extra in clob,
    p_params in tab_param)
    return varchar2
  is
    l_message varchar2(32767 char);
    l_extra_str varchar2(4000 char);
  begin
    l_message := p_text;
    
    if p_scope is not null then
      l_message := '[' || p_scope || '] ' || l_message;
    end if;
    
    if p_extra is not null then
      -- Convert clob to varchar2 (truncate if too long)
      if length(p_extra) <= 4000 then
        l_extra_str := p_extra;
      else
        l_extra_str := substr(p_extra, 1, 3997) || '...';
      end if;
      l_message := l_message || ' | Extra: ' || l_extra_str;
    end if;

    if p_params.count > 0 then
      l_message := l_message || params_to_string(p_params);
    end if;
    
    return l_message;
  end build_message;

  /**
   * Internal logging procedure with conditional compilation
   * Handles both logger and apex_debug based on $$USE_LOGGER flag
   *
   * @param p_level Log level: ERROR, WARNING, INFO, DEBUG
   * @param p_text Message text
   * @param p_scope Scope/context
   * @param p_extra Additional information
   * @param p_params Array of parameters
   */
  procedure log_internal(
    p_level in varchar2,
    p_text in varchar2,
    p_scope in varchar2,
    p_extra in clob,
    p_params in tab_param)
  is
    $if $$USE_LOGGER $then
      -- Use logger package
    $else
      l_message varchar2(32767 char);
    $end
  begin
    $if $$USE_LOGGER $then
      -- Call appropriate logger procedure based on level
      case upper(p_level)
        when 'ERROR' then
          logger.log_error(
            p_text => p_text,
            p_scope => p_scope,
            p_extra => p_extra,
            p_params => p_params);
        when 'WARNING' then
          logger.log_warning(
            p_text => p_text,
            p_scope => p_scope,
            p_extra => p_extra,
            p_params => p_params);
        when 'INFO' then
          logger.log_info(
            p_text => p_text,
            p_scope => p_scope,
            p_extra => p_extra,
            p_params => p_params);
        when 'DEBUG' then
          logger.log(
            p_text => p_text,
            p_scope => p_scope,
            p_extra => p_extra,
            p_params => p_params);
        else
          -- Default to debug
          logger.log(
            p_text => p_text,
            p_scope => p_scope,
            p_extra => p_extra,
            p_params => p_params);
      end case;
    $else
      -- Use apex_debug
      l_message := build_message(
        p_text => p_text,
        p_scope => p_scope,
        p_extra => p_extra,
        p_params => p_params);
      
      case upper(p_level)
        when 'ERROR' then
          apex_debug.error(l_message);
        when 'WARNING' then
          apex_debug.warn(l_message);
        when 'INFO' then
          apex_debug.info(l_message);
        when 'DEBUG' then
          apex_debug.trace(l_message);
        else
          -- Default to log
          apex_debug.info(l_message);
      end case;
    $end
  end log_internal;

  /**
   * Log error message
   */
  procedure log_error(
    p_text in varchar2 default null,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default uc_ai_logger.gc_empty_tab_param)
  is
  begin
    log_internal(
      p_level => 'ERROR',
      p_text => nvl(p_text, 'Error occurred'),
      p_scope => p_scope,
      p_extra => p_extra,
      p_params => p_params);
  end log_error;

  /**
   * Log warning message
   */
  procedure log_warning(
    p_text in varchar2,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default uc_ai_logger.gc_empty_tab_param)
  is
  begin
    log_internal(
      p_level => 'WARNING',
      p_text => p_text,
      p_scope => p_scope,
      p_extra => p_extra,
      p_params => p_params);
  end log_warning;

  /**
   * Log warning message (alias)
   */
  procedure log_warn(
    p_text in varchar2,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default uc_ai_logger.gc_empty_tab_param)
  is
  begin
    log_warning(
      p_text => p_text,
      p_scope => p_scope,
      p_extra => p_extra,
      p_params => p_params);
  end log_warn;

  /**
   * Log info message
   */
  procedure log_info(
    p_text in varchar2,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default uc_ai_logger.gc_empty_tab_param)
  is
  begin
    log_internal(
      p_level => 'INFO',
      p_text => p_text,
      p_scope => p_scope,
      p_extra => p_extra,
      p_params => p_params);
  end log_info;

  /**
   * Log debug message
   */
  procedure log(
    p_text in varchar2,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default uc_ai_logger.gc_empty_tab_param)
  is
  begin
    log_internal(
      p_level => 'DEBUG',
      p_text => p_text,
      p_scope => p_scope,
      p_extra => p_extra,
      p_params => p_params);
  end log;

  procedure enable_apex_debug(p_workspace in varchar2)
  as
  begin
      -- thanks anton nielsen: https://apexdebug.com/using-apexdebug-without-an-apex-session
      if sys_context('APEX$SESSION','WORKSPACE_ID') is null then
        apex_util.set_security_group_id(
          p_security_group_id => apex_util.find_security_group_id(p_workspace => p_workspace)
        );

      end if;
    apex_debug.enable(p_workspace);
  end enable_apex_debug;

end uc_ai_logger;
/
