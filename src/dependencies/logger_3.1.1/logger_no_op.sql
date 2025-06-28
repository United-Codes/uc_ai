-- This file installs a NO-OP version of the logger package that has all of the same procedures and functions,
-- but does not actually write to any tables. Additionally, it has no other object dependencies.
-- You can review the documentation at https://github.com/OraOpenSource/Logger for more information.

alter session set plsql_ccflags='logger_no_op_install:true' 
/ 


PROMPT tables/logger_logs.sql 
-- Initial table script built from 1.4.0
declare
  l_count pls_integer;
  l_nullable user_tab_columns.nullable%type;

  type typ_required_columns is table of varchar2(30) index by pls_integer;
  l_required_columns typ_required_columns;


  type typ_tab_col is record (
    column_name varchar2(30),
    data_type varchar2(100));
  type typ_arr_tab_col is table of typ_tab_col index by pls_integer;

  l_new_col typ_tab_col;
  l_new_cols typ_arr_tab_col;

begin
  -- Create Table
  select count(1)
  into l_count
  from user_tables
  where table_name = 'LOGGER_LOGS';

  if l_count = 0 then
    execute immediate '
create table logger_logs(
  id number,
  logger_level number,
  text varchar2(4000),
  time_stamp timestamp,
  scope varchar2(1000),
  module varchar2(100),
  action varchar2(100),
  user_name varchar2(255),
  client_identifier varchar2(255),
  call_stack varchar2(4000),
  unit_name varchar2(255),
  line_no varchar2(100),
  scn number,
  extra clob,
  constraint logger_logs_pk primary key (id) enable,
  constraint logger_logs_lvl_ck check(logger_level in (1,2,4,8,16,32,64,128))
)
    ';
  end if;

  -- 2.0.0
  l_required_columns(l_required_columns.count+1) := 'LOGGER_LEVEL';
  l_required_columns(l_required_columns.count+1) := 'TIME_STAMP';

  for i in l_required_columns.first .. l_required_columns.last loop

    select nullable
    into l_nullable
    from user_tab_columns
    where table_name = 'LOGGER_LOGS'
      and column_name = upper(l_required_columns(i));

    if l_nullable = 'Y' then
      execute immediate 'alter table logger_logs modify ' || l_required_columns(i) || ' not null';
    end if;
  end loop;


  -- 2.2.0
  -- Add additional columns
  -- #51
  l_new_col.column_name := 'SID';
  l_new_col.data_type := 'NUMBER';
  l_new_cols(l_new_cols.count+1) := l_new_col;

  -- #25
  l_new_col.column_name := 'CLIENT_INFO';
  l_new_col.data_type := 'VARCHAR2(64)'; -- taken from v$session.client_info
  l_new_cols(l_new_cols.count+1) := l_new_col;


  for i in 1 .. l_new_cols.count loop
    select count(1)
    into l_count
    from user_tab_columns
    where 1=1
      and table_name = 'LOGGER_LOGS'
      and column_name = l_new_cols(i).column_name;

    if l_count = 0 then
      execute immediate 'alter table LOGGER_LOGS add (' || l_new_cols(i).column_name || ' ' || l_new_cols(i).data_type || ')';
    end if;
  end loop;


  $if $$logger_no_op_install $then
    null;
  $else
    -- SEQUENCE
    select count(1)
    into l_count
    from user_sequences
    where sequence_name = 'LOGGER_LOGS_SEQ';

    if l_count = 0 then
      execute immediate '
        create sequence logger_logs_seq
            minvalue 1
            maxvalue 999999999999999999999999999
            start with 1
            increment by 1
            cache 20
      ';
    end if;

    -- INDEXES
    select count(1)
    into l_count
    from user_indexes
    where index_name = 'LOGGER_LOGS_IDX1';

    if l_count = 0 then
      execute immediate 'create index logger_logs_idx1 on logger_logs(time_stamp,logger_level)';
    end if;
  $end

end;
/


-- TRIGGER (removed as part of 2.1.0 release)
-- Drop trigger if still exists (from pre-2.1.0 releases) - Issue #31
declare
  l_count pls_integer;
  l_trigger_name user_triggers.trigger_name%type := 'BI_LOGGER_LOGS';
begin
  select count(1)
  into l_count
  from user_triggers
  where 1=1
    and trigger_name = l_trigger_name;

  if l_count > 0 then
    execute immediate 'drop trigger ' || l_trigger_name;
  end if;
end;
/

PROMPT tables/logger_prefs.sql 
-- Initial table script built from 1.4.0
declare
  l_count pls_integer;
  l_nullable user_tab_columns.nullable%type;

  type typ_required_columns is table of varchar2(30) index by pls_integer;
  l_required_columns typ_required_columns;

begin
  -- Create Table
  select count(1)
  into l_count
  from user_tables
  where table_name = 'LOGGER_PREFS';

  if l_count = 0 then
    execute immediate '
create table logger_prefs(
  pref_name	varchar2(255),
  pref_value	varchar2(255) not null,
  constraint logger_prefs_pk primary key (pref_name) enable
)
    ';
  end if;

end;
/


-- TODO mdsouza: logger 3.1.1 fix. Removed currently_installing
-- Append existing PLSQL_CCFLAGS
-- Since may be set with existing flags (specifically no_op)
-- var cur_plsql_ccflags varchar2(500);
--
-- declare
--   parnam varchar2(256);
--   intval binary_integer;
--   strval varchar2(500);
--   partyp binary_integer;
-- begin
--   partyp := dbms_utility.get_parameter_value('plsql_ccflags',intval, strval);
--
--   if strval is not null then
--     strval := ',' || strval;
--   end if;
--   :cur_plsql_ccflags := strval;
-- end;
-- /
--
-- -- Convert bind variable to substitution string
-- -- https://blogs.oracle.com/opal/entry/sqlplus_101_substitution_varia
-- column cur_plsql_ccflags new_value cur_plsql_ccflags
-- select :cur_plsql_ccflags cur_plsql_ccflags from dual;
--
-- alter session set plsql_ccflags='currently_installing:true&cur_plsql_ccflags'
-- /

create or replace trigger biu_logger_prefs
  before insert or update on logger_prefs
  for each row
begin
  $if $$logger_no_op_install $then
    null;
  $else
    :new.pref_name := upper(:new.pref_name);
    :new.pref_type := upper(:new.pref_type);

    if 1=1
      and :new.pref_type = logger.g_pref_type_logger
      and :new.pref_name = 'LEVEL' then
      :new.pref_value := upper(:new.pref_value);
    end if;

    -- TODO mdsouza: 3.1.1
    -- TODO mdsouza: if removing then decrease indent
    -- $if $$currently_installing is null or not $$currently_installing $then
      -- Since logger.pks may not be installed when this trigger is compiled, need to move some code here
      if 1=1
        and :new.pref_type = logger.g_pref_type_logger
        and :new.pref_name = 'LEVEL'
        and upper(:new.pref_value) not in (logger.g_off_name, logger.g_permanent_name, logger.g_error_name, logger.g_warning_name, logger.g_information_name, logger.g_debug_name, logger.g_timing_name, logger.g_sys_context_name, logger.g_apex_name) then
        raise_application_error(-20000, '"LEVEL" must be one of the following values: ' ||
          logger.g_off_name || ', ' || logger.g_permanent_name || ', ' || logger.g_error_name || ', ' ||
          logger.g_warning_name || ', ' || logger.g_information_name || ', ' || logger.g_debug_name || ', ' ||
          logger.g_timing_name || ', ' || logger.g_sys_context_name || ', ' || logger.g_apex_name);
      end if;

      -- Allow for null to be used for Plugins, then default to NONE
      if 1=1
        and :new.pref_type = logger.g_pref_type_logger
        and :new.pref_name like 'PLUGIN_FN%'
        and :new.pref_value is null then
        :new.pref_value := 'NONE';
      end if;

      -- #103
      -- Only predefined preferences and Custom Preferences are allowed
      -- Custom Preferences must be prefixed with CUST_
      if 1=1
        and :new.pref_type = logger.g_pref_type_logger
        and :new.pref_name not in (
          'GLOBAL_CONTEXT_NAME'
          ,'INCLUDE_CALL_STACK'
          ,'INSTALL_SCHEMA'
          ,'LEVEL'
          ,'LOGGER_DEBUG'
          ,'LOGGER_VERSION'
          ,'PLUGIN_FN_ERROR'
          ,'PREF_BY_CLIENT_ID_EXPIRE_HOURS'
          ,'PROTECT_ADMIN_PROCS'
          ,'PURGE_AFTER_DAYS'
          ,'PURGE_MIN_LEVEL'
        )
      then
        raise_application_error (-20000, 'Setting system level preferences are restricted to a set list.');
      end if;

      -- this is because the logger package is not installed yet.  We enable it in logger_configure
      logger.null_global_contexts;
    -- TODO mdsouza: 3.1.1
    -- $end
  $end -- $$logger_no_op_install
end;
/

alter trigger biu_logger_prefs disable;

declare
begin
  $if $$logger_no_op_install $then
    null;
  $else
    -- Configure Data
    merge into logger_prefs p
    using (
      select 'PURGE_AFTER_DAYS' pref_name, '7' pref_value from dual union
      select 'PURGE_MIN_LEVEL' pref_name, 'DEBUG' pref_value from dual union
      select 'LOGGER_VERSION' pref_name, 'x.x.x' pref_value from dual union -- x.x.x will be replaced when running the build script
      select 'LEVEL' pref_name, 'DEBUG' pref_value from dual union
      select 'PROTECT_ADMIN_PROCS' pref_name, 'TRUE' pref_value from dual union
      select 'INCLUDE_CALL_STACK' pref_name, 'TRUE' pref_value from dual union
      select 'PREF_BY_CLIENT_ID_EXPIRE_HOURS' pref_name, '12' pref_value from dual union
      select 'INSTALL_SCHEMA' pref_name, sys_context('USERENV','CURRENT_SCHEMA') pref_value from dual union
      -- #46
      select 'PLUGIN_FN_ERROR' pref_name, 'NONE' pref_value from dual union
      -- #64
      select 'LOGGER_DEBUG' pref_name, 'FALSE' pref_value from dual
      ) d
      on (p.pref_name = d.pref_name)
    when matched then
      update set p.pref_value =
        case
          -- Only LOGGER_VERSION should be updated during an update
          when p.pref_name = 'LOGGER_VERSION' then d.pref_value
          else p.pref_value
        end
    when not matched then
      insert (p.pref_name,p.pref_value)
      values (d.pref_name,d.pref_value);
  $end
end;
/




-- #127: Add pref_type
declare
  type typ_tab_col is record (
    column_name varchar2(30),
    data_type varchar2(100));
  type typ_arr_tab_col is table of typ_tab_col index by pls_integer;

  l_count pls_integer;
  l_new_col typ_tab_col;
  l_new_cols typ_arr_tab_col;
begin

  l_new_col.column_name := 'PREF_TYPE';
  l_new_col.data_type := 'VARCHAR2(30)';
  l_new_cols(l_new_cols.count+1) := l_new_col;

  for i in 1 .. l_new_cols.count loop
    select count(1)
    into l_count
    from user_tab_columns
    where 1=1
      and upper(table_name) = upper('logger_prefs')
      and column_name = l_new_cols(i).column_name;

    if l_count = 0 then
      execute immediate 'alter table logger_prefs add (' || l_new_cols(i).column_name || ' ' || l_new_cols(i).data_type || ')';

      -- Custom post-add columns

      -- #127
      if lower(l_new_cols(i).column_name) = 'pref_type' then
        -- If "LOGGER" is changed then modify logger.pks g_logger_prefs_pref_type value
        execute immediate q'!update logger_prefs set pref_type = 'LOGGER'!';
        execute immediate q'!alter table logger_prefs modify pref_type not null!';
      end if;

    end if; -- l_count = 0
  end loop;

end;
/


-- #127 If old PK, then drop it
declare
  l_count pls_integer;
begin
  select count(*)
  into l_count
  from user_cons_columns
  where 1=1
    and constraint_name = 'LOGGER_PREFS_PK'
    and column_name != 'PREF_NAME';

  if l_count = 0 then
    -- PK only has one column, drop it and it will be rebuilt below
    execute immediate 'alter table logger_prefs drop constraint logger_prefs_pk';
  end if;

end;
/


-- Ensure that pref_name is upper
declare
  type typ_constraint is record(
    name user_constraints.constraint_name%type,
    condition varchar(500)
  );

  type typ_tab_constraint is table of typ_constraint index by pls_integer;

  l_constraint typ_constraint;
  l_constraints typ_tab_constraint;
  l_count pls_integer;
  l_sql varchar2(500);
begin
  l_constraint.name := 'LOGGER_PREFS_PK';
  l_constraint.condition := 'primary key (pref_type, pref_name)';
  l_constraints(l_constraints.count+1) := l_constraint;

  l_constraint.name := 'LOGGER_PREFS_CK1';
  l_constraint.condition := 'check (pref_name = upper(pref_name))';
  l_constraints(l_constraints.count+1) := l_constraint;

  l_constraint.name := 'LOGGER_PREFS_CK2';
  l_constraint.condition := 'check (pref_type = upper(pref_type))';
  l_constraints(l_constraints.count+1) := l_constraint;


  -- All pref names/types should be upper
  update logger_prefs
  set
    pref_name = upper(pref_name),
    pref_type = upper(pref_type)
  where 1=1
    or pref_name != upper(pref_name)
    or pref_type != upper(pref_type);

  for i in l_constraints.first .. l_constraints.last loop
    select count(1)
    into l_count
    from user_constraints
    where 1=1
      and table_name = 'LOGGER_PREFS'
      and constraint_name = l_constraints(i).name;

    if l_count = 0 then
      l_sql := 'alter table logger_prefs add constraint %CONSTRAINT_NAME% %CONSTRAINT_CONDITION%';
      l_sql := replace(l_sql, '%CONSTRAINT_NAME%', l_constraints(i).name);
      l_sql := replace(l_sql, '%CONSTRAINT_CONDITION%', l_constraints(i).condition);

      execute immediate l_sql;
    end if;
  end loop; -- l_constraints

end;
/

alter trigger biu_logger_prefs enable;

PROMPT tables/logger_logs_apex_items.sql 
-- Initial table script built from 1.4.0
declare
  l_count pls_integer;
  l_nullable user_tab_columns.nullable%type;

  type typ_required_columns is table of varchar2(30) index by pls_integer;
  l_required_columns typ_required_columns;

begin

  -- Create Table
  select count(1)
  into l_count
  from user_tables
  where table_name = 'LOGGER_LOGS_APEX_ITEMS';

  if l_count = 0 then
    execute immediate '
create table logger_logs_apex_items(
    id				number not null,
    log_id          number not null,
    app_session     number not null,
    item_name       varchar2(1000) not null,
    item_value      clob,
    constraint logger_logs_apx_itms_pk primary key (id) enable,
    constraint logger_logs_apx_itms_fk foreign key (log_id) references logger_logs(id) ON DELETE CASCADE
)
    ';
  end if;


  $if $$logger_no_op_install $then
    null;
  $else
    -- SEQUENCE
    select count(1)
    into l_count
    from user_sequences
    where sequence_name = 'LOGGER_APX_ITEMS_SEQ';

    if l_count = 0 then
      execute immediate '
  create sequence logger_apx_items_seq
    minvalue 1
    maxvalue 999999999999999999999999999
    start with 1
    increment by 1
    cache 20
      ';
    end if;

    -- INDEXES
    select count(1)
    into l_count
    from user_indexes
    where index_name = 'LOGGER_APEX_ITEMS_IDX1';

    if l_count = 0 then
      execute immediate 'create index logger_apex_items_idx1 on logger_logs_apex_items(log_id)';
    end if;
  $end -- $$logger_no_op_install
end;
/


create or replace trigger biu_logger_apex_items
  before insert or update on logger_logs_apex_items
for each row
begin
  $if $$logger_no_op_install $then
    null;
  $else
    :new.id := logger_apx_items_seq.nextval;
  $end
end;
/

PROMPT tables/logger_prefs_by_client_id.sql 
declare
  l_count pls_integer;
  l_nullable user_tab_columns.nullable%type;

  type typ_required_columns is table of varchar2(30) index by pls_integer;
  l_required_columns typ_required_columns;

  l_sql varchar2(2000);

begin
  -- Create Table
  select count(1)
  into l_count
  from user_tables
  where table_name = 'LOGGER_PREFS_BY_CLIENT_ID';

  if l_count = 0 then
    execute immediate q'!
create table logger_prefs_by_client_id(
  client_id varchar2(64) not null,
  logger_level varchar2(20) not null,
  include_call_stack varchar2(5) not null,
  created_date date default sysdate not null,
  expiry_date date not null,
  constraint logger_prefs_by_client_id_pk primary key (client_id) enable,
  constraint logger_prefs_by_client_id_ck1 check (logger_level in ('OFF','PERMANENT','ERROR','WARNING','INFORMATION','DEBUG','TIMING')),
  constraint logger_prefs_by_client_id_ck2 check (expiry_date >= created_date),
  constraint logger_prefs_by_client_id_ck3 check (include_call_stack in ('TRUE', 'FALSE'))
)
    !';
  end if;

  -- COMMENTS
  execute immediate q'!comment on table logger_prefs_by_client_id is 'Client specific logger levels. Only active client_ids/logger_levels will be maintained in this table'!';
  execute immediate q'!comment on column logger_prefs_by_client_id.client_id is 'Client identifier'!';
  execute immediate q'!comment on column logger_prefs_by_client_id.logger_level is 'Logger level. Must be OFF, PERMANENT, ERROR, WARNING, INFORMATION, DEBUG, TIMING'!';
  execute immediate q'!comment on column logger_prefs_by_client_id.include_call_stack is 'Include call stack in logging'!';
  execute immediate q'!comment on column logger_prefs_by_client_id.created_date is 'Date that entry was created on'!';
  execute immediate q'!comment on column logger_prefs_by_client_id.expiry_date is 'After the given expiry date the logger_level will be disabled for the specific client_id. Unless sepcifically removed from this table a job will clean up old entries'!';


  -- 92: Missing APEX and SYS_CONTEXT support
  l_sql := 'alter table logger_prefs_by_client_id drop constraint logger_prefs_by_client_id_ck1';
  execute immediate l_sql;

  -- Rebuild constraint
  l_sql := q'!alter table logger_prefs_by_client_id
    add constraint logger_prefs_by_client_id_ck1
    check (logger_level in ('OFF','PERMANENT','ERROR','WARNING','INFORMATION','DEBUG','TIMING', 'APEX', 'SYS_CONTEXT'))!';
  execute immediate l_sql;

end;
/

PROMPT views/logger_logs_5_min.sql 
create or replace force view logger_logs_5_min as
	select * 
      from logger_logs 
	 where time_stamp > systimestamp - (5/1440)
/
PROMPT views/logger_logs_60_min.sql 
create or replace force view logger_logs_60_min as
	select * 
      from logger_logs 
	 where time_stamp > systimestamp - (1/24)
/

PROMPT views/logger_logs_terse.sql
set termout off
-- setting termout off as this view will install with an error as it depends on logger.date_text_format
create or replace force view logger_logs_terse as
 select id, logger_level, 
        substr(logger.date_text_format(time_stamp),1,20) time_ago,
        substr(text,1,200) text
   from logger_logs
  where time_stamp > systimestamp - (5/1440)
  order by id asc
/

set termout on


alter trigger biu_logger_prefs compile;


prompt *** logger.pks *** 

create or replace package logger
  authid definer
as
  -- This project using the following MIT License:
  --
  -- The MIT License (MIT)
  --
  -- Copyright (c) 2015 OraOpenSource
  --
  -- Permission is hereby granted, free of charge, to any person obtaining a copy
  -- of this software and associated documentation files (the "Software"), to deal
  -- in the Software without restriction, including without limitation the rights
  -- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  -- copies of the Software, and to permit persons to whom the Software is
  -- furnished to do so, subject to the following conditions:
  --
  -- The above copyright notice and this permission notice shall be included in all
  -- copies or substantial portions of the Software.
  --
  -- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  -- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  -- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  -- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  -- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  -- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  -- SOFTWARE.


  -- TYPES
  type rec_param is record(
    name varchar2(255),
    val varchar2(4000));

  type tab_param is table of rec_param index by binary_integer;

  type rec_logger_log is record(
    id logger_logs.id%type,
    logger_level logger_logs.logger_level%type
  );


  -- VARIABLES
	g_logger_version constant varchar2(10) := 'x.x.x'; -- Don't change this. Build script will replace with right version number
	g_context_name constant varchar2(35) := substr(sys_context('USERENV','CURRENT_SCHEMA'),1,23)||'_LOGCTX';

  g_off constant number := 0;
  g_permanent constant number := 1;
	g_error constant number := 2;
	g_warning constant number := 4;
	g_information constant number := 8;
  g_debug constant number := 16;
	g_timing constant number := 32;
  g_sys_context constant number := 64;
  g_apex constant number := 128;

  -- #44
  g_off_name constant varchar2(30) := 'OFF';
  g_permanent_name constant varchar2(30) := 'PERMANENT';
  g_error_name constant varchar2(30) := 'ERROR';
  g_warning_name constant varchar2(30) := 'WARNING';
  g_information_name constant varchar2(30) := 'INFORMATION';
  g_debug_name constant varchar2(30) := 'DEBUG';
  g_timing_name constant varchar2(30) := 'TIMING';
  g_sys_context_name constant varchar2(30) := 'SYS_CONTEXT';
  g_apex_name constant varchar2(30) := 'APEX';

  gc_empty_tab_param tab_param;

  -- #54: Types for log_apex_items
  g_apex_item_type_all constant varchar2(30) := 'ALL'; -- Application items and page items
  g_apex_item_type_app constant varchar2(30) := 'APP'; -- All application items
  g_apex_item_type_page constant varchar2(30) := 'PAGE'; -- All page items
  -- To log items on a particular page, just enter the page number

  -- #127
  -- Note to developers: This is only for internal Logger code. Do not use this as part of your code.
  g_pref_type_logger constant logger_prefs.pref_type%type := 'LOGGER'; -- If this changes need to modify logger_prefs.sql as it has a dependancy.

  -- Expose private functions only for testing during development
  $if $$logger_debug $then
    function is_number(p_str in varchar2)
      return boolean;

    procedure assert(
      p_condition in boolean,
      p_message in varchar2);

    function get_param_clob(p_params in logger.tab_param)
      return clob;

    procedure save_global_context(
      p_attribute in varchar2,
      p_value in varchar2,
      p_client_id in varchar2 default null);

    function set_extra_with_params(
      p_extra in logger_logs.extra%type,
      p_params in tab_param)
      return logger_logs.extra%type;

    function get_sys_context(
      p_detail_level in varchar2 default 'USER', -- ALL, NLS, USER, INSTANCE
      p_vertical in boolean default false,
      p_show_null in boolean default false)
      return clob;

    function admin_security_check
      return boolean;

    function get_level_number
      return number;

    function include_call_stack
      return boolean;

    function date_text_format_base (
      p_date_start in date,
      p_date_stop  in date)
      return varchar2;

    procedure log_internal(
      p_text in varchar2,
      p_log_level in number,
      p_scope in varchar2,
      p_extra in clob default null,
      p_callstack in varchar2 default null,
      p_params in tab_param default logger.gc_empty_tab_param);
  $end

  -- PROCEDURES and FUNCTIONS

  procedure null_global_contexts;

  function convert_level_char_to_num(
    p_level in varchar2)
    return number;

  function convert_level_num_to_char(
    p_level in number)
    return varchar2;

  function date_text_format (p_date in date)
    return varchar2;

	function get_character_codes(
		p_string 				in varchar2,
		p_show_common_codes 	in boolean default true)
    return varchar2;

  procedure log_error(
    p_text          in varchar2 default null,
    p_scope         in varchar2 default null,
    p_extra         in clob default null,
    p_params        in tab_param default logger.gc_empty_tab_param);

  procedure log_permanent(
    p_text    in varchar2,
    p_scope   in varchar2 default null,
    p_extra   in clob default null,
    p_params  in tab_param default logger.gc_empty_tab_param);

  procedure log_warning(
    p_text    in varchar2,
    p_scope   in varchar2 default null,
    p_extra   in clob default null,
    p_params  in tab_param default logger.gc_empty_tab_param);

  procedure log_warn(
    p_text in varchar2,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default logger.gc_empty_tab_param);

  procedure log_information(
    p_text    in varchar2,
    p_scope   in varchar2 default null,
    p_extra   in clob default null,
    p_params  in tab_param default logger.gc_empty_tab_param);

  procedure log_info(
    p_text in varchar2,
    p_scope in varchar2 default null,
    p_extra in clob default null,
    p_params in tab_param default logger.gc_empty_tab_param);

  procedure log(
    p_text    in varchar2,
    p_scope   in varchar2 default null,
    p_extra   in clob default null,
    p_params  in tab_param default logger.gc_empty_tab_param);

  function get_cgi_env(
    p_show_null		in boolean default false)
  	return clob;

  procedure log_userenv(
    p_detail_level in varchar2 default 'USER',-- ALL, NLS, USER, INSTANCE,
    p_show_null in boolean default false,
    p_scope in logger_logs.scope%type default null,
    p_level in logger_logs.logger_level%type default null);

  procedure log_cgi_env(
    p_show_null in boolean default false,
    p_scope in logger_logs.scope%type default null,
    p_level in logger_logs.logger_level%type default null);

  procedure log_character_codes(
    p_text in varchar2,
    p_scope in logger_logs.scope%type default null,
    p_show_common_codes in boolean default true,
    p_level in logger_logs.logger_level%type default null);

    procedure log_apex_items(
      p_text in varchar2 default 'Log APEX Items',
      p_scope in logger_logs.scope%type default null,
      p_item_type in varchar2 default logger.g_apex_item_type_all,
      p_log_null_items in boolean default true,
      p_level in logger_logs.logger_level%type default null);

	procedure time_start(
		p_unit in varchar2,
    p_log_in_table in boolean default true);

	procedure time_stop(
		p_unit in varchar2,
    p_scope in varchar2 default null);

  function time_stop(
    p_unit in varchar2,
    p_scope in varchar2 default null,
    p_log_in_table in boolean default true)
    return varchar2;

  function time_stop_seconds(
    p_unit in varchar2,
    p_scope in varchar2 default null,
    p_log_in_table in boolean default true)
    return number;

  procedure time_reset;

  function get_pref(
    p_pref_name in logger_prefs.pref_name%type,
    p_pref_type in logger_prefs.pref_type%type default logger.g_pref_type_logger)
    return varchar2
    $if not dbms_db_version.ver_le_10_2  $then
      result_cache
    $end;

  -- #103
  procedure set_pref(
    p_pref_type in logger_prefs.pref_type%type,
    p_pref_name in logger_prefs.pref_name%type,
    p_pref_value in logger_prefs.pref_value%type);

  -- #103
  procedure del_pref(
    p_pref_type in logger_prefs.pref_type%type,
    p_pref_name in logger_prefs.pref_name%type);

	procedure purge(
		p_purge_after_days in varchar2 default null,
		p_purge_min_level	in varchar2	default null);

  procedure purge(
    p_purge_after_days in number default null,
    p_purge_min_level in number);

	procedure purge_all;

	procedure status(
		p_output_format	in varchar2 default null); -- SQL-DEVELOPER | HTML | DBMS_OUPUT

  procedure sqlplus_format;

  procedure set_level(
    p_level in varchar2 default logger.g_debug_name,
    p_client_id in varchar2 default null,
    p_include_call_stack in varchar2 default null,
    p_client_id_expire_hours in number default null
  );

  procedure unset_client_level(p_client_id in varchar2);

  procedure unset_client_level;

  procedure unset_client_level_all;


  procedure append_param(
    p_params in out nocopy logger.tab_param,
    p_name in varchar2,
    p_val in varchar2);

  procedure append_param(
    p_params in out nocopy logger.tab_param,
    p_name in varchar2,
    p_val in number);

  procedure append_param(
    p_params in out nocopy logger.tab_param,
    p_name in varchar2,
    p_val in date);

  procedure append_param(
    p_params in out nocopy logger.tab_param,
    p_name in varchar2,
    p_val in timestamp);

  procedure append_param(
    p_params in out nocopy logger.tab_param,
    p_name in varchar2,
    p_val in timestamp with time zone);

  procedure append_param(
    p_params in out nocopy logger.tab_param,
    p_name in varchar2,
    p_val in timestamp with local time zone);

  procedure append_param(
    p_params in out nocopy logger.tab_param,
    p_name in varchar2,
    p_val in boolean);

  function ok_to_log(p_level in number)
    return boolean;

  function ok_to_log(p_level in varchar2)
    return boolean;

  function tochar(
    p_val in number)
    return varchar2;

  function tochar(
    p_val in date)
    return varchar2;

  function tochar(
    p_val in timestamp)
    return varchar2;

  function tochar(
    p_val in timestamp with time zone)
    return varchar2;

  function tochar(
    p_val in timestamp with local time zone)
    return varchar2;

  function tochar(
    p_val in boolean)
    return varchar2;

  procedure ins_logger_logs(
    p_logger_level in logger_logs.logger_level%type,
    p_text in varchar2 default null, -- Not using type since want to be able to pass in 32767 characters
    p_scope in logger_logs.scope%type default null,
    p_call_stack in logger_logs.call_stack%type default null,
    p_unit_name in logger_logs.unit_name%type default null,
    p_line_no in logger_logs.line_no%type default null,
    p_extra in logger_logs.extra%type default null,
    po_id out nocopy logger_logs.id%type
  );


  function sprintf(
    p_str in varchar2,
    p_s1 in varchar2 default null,
    p_s2 in varchar2 default null,
    p_s3 in varchar2 default null,
    p_s4 in varchar2 default null,
    p_s5 in varchar2 default null,
    p_s6 in varchar2 default null,
    p_s7 in varchar2 default null,
    p_s8 in varchar2 default null,
    p_s9 in varchar2 default null,
    p_s10 in varchar2 default null)
    return varchar2;

  function get_plugin_rec(
    p_logger_level in logger_logs.logger_level%type)
    return logger.rec_logger_log;
end logger;
/


prompt *** logger.pkb *** 

create or replace
begin
*
ERROR at line 1:
ORA-24234: unable to get source of PACKAGE BODY "GIFFY"."LOGGER", insufficient privileges or does not exist 
ORA-06512: at "SYS.DBMS_SYS_ERROR", line 105 
ORA-06512: at "SYS.DBMS_PREPROCESSOR", line 189 
ORA-06512: at "SYS.DBMS_PREPROCESSOR", line 109 
ORA-06512: at line 2 


/


prompt
prompt *************************************************
prompt Now executing LOGGER.STATUS...
prompt 
begin 
	logger.status; 
end;
/

prompt *************************************************



alter view logger_logs_terse compile;
