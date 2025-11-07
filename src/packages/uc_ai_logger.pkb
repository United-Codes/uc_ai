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
    return clob
  is
    l_message clob;
  begin
    l_message := p_text;
    
    if p_scope is not null then
      l_message := '[' || p_scope || '] ' || l_message;
    end if;
    
    if p_params.count > 0 then
      l_message := l_message || params_to_string(p_params);
    end if;

    if p_extra is not null then
      l_message := l_message || ' | Extra: ' || p_extra;
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
      l_message clob;
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
      
      -- Log in chunks of max 4000 characters
      declare
        c_max_chunk_size constant pls_integer := 4000;
        c_indicator_overhead constant pls_integer := 20; -- Reserve space for "[999/999] " indicator
        l_message_length pls_integer;
        l_offset pls_integer := 1;
        l_chunk varchar2(4000 char);
        l_chunk_num pls_integer := 1;
        l_total_chunks pls_integer;
        l_actual_chunk_size pls_integer;
        l_indicator varchar2(20 char);
      begin
        l_message_length := length(l_message);
        
        -- Calculate if we need to split and adjust chunk size accordingly
        if l_message_length > c_max_chunk_size then
          l_actual_chunk_size := c_max_chunk_size - c_indicator_overhead;
          l_total_chunks := ceil(l_message_length / l_actual_chunk_size);
        else
          l_actual_chunk_size := c_max_chunk_size;
          l_total_chunks := 1;
        end if;
        
        while l_offset <= l_message_length loop
          l_chunk := substr(l_message, l_offset, l_actual_chunk_size);
          
          -- Add chunk indicator if message is split
          if l_total_chunks > 1 then
            l_indicator := '[' || l_chunk_num || '/' || l_total_chunks || '] ';
            l_chunk := l_indicator || l_chunk;
          end if;
          
          case upper(p_level)
            when 'ERROR' then
              apex_debug.error(l_chunk);
            when 'WARNING' then
              apex_debug.warn(l_chunk);
            when 'INFO' then
              apex_debug.info(l_chunk);
            when 'DEBUG' then
              apex_debug.trace(l_chunk);
            else
              -- Default to log
              apex_debug.info(l_chunk);
          end case;
          
          l_offset := l_offset + l_actual_chunk_size;
          l_chunk_num := l_chunk_num + 1;
        end loop;
      end;
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
    l_sec_group_id number;
  begin
    -- thanks anton nielsen: https://apexdebug.com/using-apexdebug-without-an-apex-session
    if sys_context('APEX$SESSION','WORKSPACE_ID') is null then
      l_sec_group_id := apex_util.find_security_group_id(p_workspace => p_workspace);

      if l_sec_group_id is null then
        raise_application_error(
          -20001,
          'Workspace "' || p_workspace || '" not found. Cannot enable APEX debug.');
      end if;

      apex_util.set_security_group_id(
        p_security_group_id => l_sec_group_id
      );

    end if;
    apex_debug.enable(apex_debug.c_log_level_app_trace);
  end enable_apex_debug;

end uc_ai_logger;
/
