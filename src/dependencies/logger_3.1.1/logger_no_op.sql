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


-- Append existing PLSQL_CCFLAGS
-- Since may be set with existing flags (specifically no_op)
var cur_plsql_ccflags varchar2(500);

declare
  parnam varchar2(256);
  intval binary_integer;
  strval varchar2(500);
  partyp binary_integer;
begin
  partyp := dbms_utility.get_parameter_value('plsql_ccflags',intval, strval);

  if strval is not null then
    strval := ',' || strval;
  end if;
  :cur_plsql_ccflags := strval;
end;
/

-- Convert bind variable to substitution string
-- https://blogs.oracle.com/opal/entry/sqlplus_101_substitution_varia
column cur_plsql_ccflags new_value cur_plsql_ccflags
select :cur_plsql_ccflags cur_plsql_ccflags from dual;

alter session set plsql_ccflags='currently_installing:true&cur_plsql_ccflags'
/

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

    $if $$currently_installing is null or not $$currently_installing $then
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
    $end
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
package body logger                                                                                                                                                                                     
as                                                                                                                                                                                                      
-- Note: The license is defined in the package specification of the logger package                                                                                                                      
--                                                                                                                                                                                                      
-- Conditional Compilation variables:                                                                                                                                                                   
-- $$NO_OP                                                                                                                                                                                              
--  When true, completely disables all logger DML.Also used to generate the logger_no_op.sql file                                                                                                       
--                                                                                                                                                                                                      
-- $$RAC_LT_11_2:                                                                                                                                                                                       
--  Set in logger_configure.                                                                                                                                                                            
--  Handles the fact that RAC doesn't support global app contexts until 11.2                                                                                                                            
--                                                                                                                                                                                                      
-- $$FLASHBACK_ENABLED                                                                                                                                                                                  
--  Set in logger_configure.                                                                                                                                                                            
--  Determine whether or not we can grab the scn from dbms_flashback.                                                                                                                                   
--  Primarily used in the trigger on logger_logs.                                                                                                                                                       
--                                                                                                                                                                                                      
-- $$APEX                                                                                                                                                                                               
--  Set in logger_configure.                                                                                                                                                                            
--  True if we can query a local synonym to wwv_flow_data to snapshot the APEX session state.                                                                                                           
--                                                                                                                                                                                                      
-- $$LOGGER_DEBUG                                                                                                                                                                                       
--  Only to be used during development of logger                                                                                                                                                        
--  Primarily used for dbms_output.put_line calls                                                                                                                                                       
--  Part of #64                                                                                                                                                                                         
--                                                                                                                                                                                                      
-- $$LOGGER_PLUGIN_<TYPE> : For each type of plugin                                                                                                                                                     
--  Introduced with #46                                                                                                                                                                                 
--  $$LOGGER_PLUGIN_ERROR                                                                                                                                                                               
--                                                                                                                                                                                                      
-- TYPES                                                                                                                                                                                                
type ts_array is table of timestamp index by varchar2(100);                                                                                                                                             
-- VARIABLES                                                                                                                                                                                            
g_log_id number;                                                                                                                                                                                        
g_proc_start_times ts_array;                                                                                                                                                                            
g_running_timers pls_integer := 0;                                                                                                                                                                      
-- #46                                                                                                                                                                                                  
g_plug_logger_log_error rec_logger_log;                                                                                                                                                                 
g_in_plugin_error boolean := false;                                                                                                                                                                     
-- CONSTANTS                                                                                                                                                                                            
gc_line_feed constant varchar2(1) := chr(10);                                                                                                                                                           
gc_cflf constant varchar2(2) := chr(13)||chr(10);                                                                                                                                                       
gc_date_format constant varchar2(255) := 'DD-MON-YYYY HH24:MI:SS';                                                                                                                                      
gc_timestamp_format constant varchar2(255) := gc_date_format || ':FF';                                                                                                                                  
gc_timestamp_tz_format constant varchar2(255) := gc_timestamp_format || ' TZR';                                                                                                                         
gc_ctx_attr_level constant varchar2(5) := 'level';                                                                                                                                                      
gc_ctx_attr_include_call_stack constant varchar2(18) := 'include_call_stack';                                                                                                                           
-- #46 Plugin context names                                                                                                                                                                             
gc_ctx_plugin_fn_log constant varchar2(30) := 'plugin_fn_log';                                                                                                                                          
gc_ctx_plugin_fn_info constant varchar2(30) := 'plugin_fn_information';                                                                                                                                 
gc_ctx_plugin_fn_warn constant varchar2(30) := 'plugin_fn_warning';                                                                                                                                     
gc_ctx_plugin_fn_error constant varchar2(30) := 'plugin_fn_error';                                                                                                                                      
gc_ctx_plugin_fn_perm constant varchar2(30) := 'plugin_fn_permanent';                                                                                                                                   
-- #113 Preference names                                                                                                                                                                                
gc_pref_level constant logger_prefs.pref_name%type := 'LEVEL';                                                                                                                                          
gc_pref_include_call_stack constant logger_prefs.pref_name%type := 'INCLUDE_CALL_STACK';                                                                                                                
gc_pref_protect_admin_procs constant logger_prefs.pref_name%type := 'PROTECT_ADMIN_PROCS';                                                                                                              
gc_pref_install_schema constant logger_prefs.pref_name%type := 'INSTALL_SCHEMA';                                                                                                                        
gc_pref_purge_after_days constant logger_prefs.pref_name%type := 'PURGE_AFTER_DAYS';                                                                                                                    
gc_pref_purge_min_level constant logger_prefs.pref_name%type := 'PURGE_MIN_LEVEL';                                                                                                                      
gc_pref_logger_version constant logger_prefs.pref_name%type := 'LOGGER_VERSION';                                                                                                                        
gc_pref_client_id_expire_hours constant logger_prefs.pref_name%type := 'PREF_BY_CLIENT_ID_EXPIRE_HOURS';                                                                                                
gc_pref_logger_debug constant logger_prefs.pref_name%type := 'LOGGER_DEBUG';                                                                                                                            
gc_pref_plugin_fn_error constant logger_prefs.pref_name%type := 'PLUGIN_FN_ERROR';                                                                                                                      
-- *** PRIVATE ***                                                                                                                                                                                      
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created                                                                                                                                                                                              
* @param p_str                                                                                                                                                                                          
* @return True if p_str is a number                                                                                                                                                                     
*/                                                                                                                                                                                                      
function is_number(p_str in varchar2)                                                                                                                                                                   
return boolean                                                                                                                                                                                          
as                                                                                                                                                                                                      
l_num number;                                                                                                                                                                                           
begin                                                                                                                                                                                                   
l_num := to_number(p_str);                                                                                                                                                                              
return true;                                                                                                                                                                                            
exception                                                                                                                                                                                               
when others then                                                                                                                                                                                        
return false;                                                                                                                                                                                           
end is_number;                                                                                                                                                                                          
/**                                                                                                                                                                                                     
* Validates assertion. Will raise an application error if assertion is false                                                                                                                            
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 29-Mar-2013                                                                                                                                                                                  
* @param p_condition Boolean condition to validate                                                                                                                                                      
* @param p_message Message to include in application error if p_condition fails                                                                                                                         
*/                                                                                                                                                                                                      
procedure assert(                                                                                                                                                                                       
p_condition in boolean,                                                                                                                                                                                 
p_message in varchar2)                                                                                                                                                                                  
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end assert;                                                                                                                                                                                             
/**                                                                                                                                                                                                     
* Returns the display/print friendly parameter information                                                                                                                                              
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 20-Jan-2013                                                                                                                                                                                  
* @param p_parms Array of parameters (can be null)                                                                                                                                                      
* @return Clob of param information                                                                                                                                                                     
*/                                                                                                                                                                                                      
function get_param_clob(p_params in logger.tab_param)                                                                                                                                                   
return clob                                                                                                                                                                                             
as                                                                                                                                                                                                      
l_return clob;                                                                                                                                                                                          
l_no_vars constant varchar2(255) := 'No params defined';                                                                                                                                                
l_index pls_integer;                                                                                                                                                                                    
begin                                                                                                                                                                                                   
return null;                                                                                                                                                                                            
end get_param_clob;                                                                                                                                                                                     
/**                                                                                                                                                                                                     
* Sets the global context                                                                                                                                                                               
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_attribute Attribute for context to set                                                                                                                                                       
* @param p_value Value                                                                                                                                                                                  
* @param p_client_id Optional client_id. If specified will only set the attribute/value for specific client_id (not global)                                                                             
*/                                                                                                                                                                                                      
procedure save_global_context(                                                                                                                                                                          
p_attribute in varchar2,                                                                                                                                                                                
p_value in varchar2,                                                                                                                                                                                    
p_client_id in varchar2 default null)                                                                                                                                                                   
is                                                                                                                                                                                                      
pragma autonomous_transaction;                                                                                                                                                                          
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
commit; -- MD: moved commit to outside of the NO_OP check since commit or rollback must occur in this procedure                                                                                         
end save_global_context;                                                                                                                                                                                
/**                                                                                                                                                                                                     
* Will return the extra column appended with the display friendly parameters                                                                                                                            
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 1-May-2013                                                                                                                                                                                   
* @param p_extra Current "Extra" field                                                                                                                                                                  
* @param p_params Parameters. If null, then no changes to the Extra column                                                                                                                              
*/                                                                                                                                                                                                      
function set_extra_with_params(                                                                                                                                                                         
p_extra in logger_logs.extra%type,                                                                                                                                                                      
p_params in tab_param                                                                                                                                                                                   
)                                                                                                                                                                                                       
return logger_logs.extra%type                                                                                                                                                                           
as                                                                                                                                                                                                      
l_extra logger_logs.extra%type;                                                                                                                                                                         
begin                                                                                                                                                                                                   
return null;                                                                                                                                                                                            
end set_extra_with_params;                                                                                                                                                                              
/**                                                                                                                                                                                                     
* Returns common system level context values                                                                                                                                                            
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_detail_level USER, ALL, NLS, USER, or INSTANCe                                                                                                                                               
* @param p_vertical True of values should have a line break after each value. False for comman seperated list.                                                                                          
* @param p_show_null Show null values                                                                                                                                                                   
* @return                                                                                                                                                                                               
*/                                                                                                                                                                                                      
function get_sys_context(                                                                                                                                                                               
p_detail_level in varchar2 default 'USER', -- ALL, NLS, USER, INSTANCE                                                                                                                                  
p_vertical in boolean default false,                                                                                                                                                                    
p_show_null in boolean default false)                                                                                                                                                                   
return clob                                                                                                                                                                                             
is                                                                                                                                                                                                      
l_ctx clob;                                                                                                                                                                                             
l_detail_level varchar2(20) := upper(p_detail_level);                                                                                                                                                   
procedure append_ctx(p_name in varchar2)                                                                                                                                                                
is                                                                                                                                                                                                      
r_pad number := 30;                                                                                                                                                                                     
l_value varchar2(100);                                                                                                                                                                                  
invalid_userenv_parm exception;                                                                                                                                                                         
pragma exception_init(invalid_userenv_parm, -2003);                                                                                                                                                     
begin                                                                                                                                                                                                   
l_value := sys_context('USERENV',p_name);                                                                                                                                                               
if p_show_null or l_value is not null then                                                                                                                                                              
if p_vertical then                                                                                                                                                                                      
l_ctx := l_ctx || rpad(p_name,r_pad,' ')||': '|| l_value || gc_cflf;                                                                                                                                    
else                                                                                                                                                                                                    
l_ctx := l_ctx || p_name||': '|| l_value ||', ';                                                                                                                                                        
end if;                                                                                                                                                                                                 
end if;                                                                                                                                                                                                 
exception                                                                                                                                                                                               
when invalid_userenv_parm then                                                                                                                                                                          
null;                                                                                                                                                                                                   
end append_ctx;                                                                                                                                                                                         
begin                                                                                                                                                                                                   
return null;                                                                                                                                                                                            
end get_sys_context;                                                                                                                                                                                    
/**                                                                                                                                                                                                     
* Checks if admin functions can be run                                                                                                                                                                  
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @return True if user can run admin procs.                                                                                                                                                             
*/                                                                                                                                                                                                      
function admin_security_check                                                                                                                                                                           
return boolean                                                                                                                                                                                          
is                                                                                                                                                                                                      
l_protect_admin_procs logger_prefs.pref_value%type;                                                                                                                                                     
l_return boolean default false;                                                                                                                                                                         
begin                                                                                                                                                                                                   
l_return := true;                                                                                                                                                                                       
return l_return;                                                                                                                                                                                        
end admin_security_check;                                                                                                                                                                               
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #111 Use get_pref to remove duplicate code                                                                                                                                                         
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param                                                                                                                                                                                                
* @return If client level specified will return it, otherwise global level.                                                                                                                             
*/                                                                                                                                                                                                      
function get_level_number                                                                                                                                                                               
return number                                                                                                                                                                                           
is                                                                                                                                                                                                      
l_level number;                                                                                                                                                                                         
l_level_char varchar2(50);                                                                                                                                                                              
begin                                                                                                                                                                                                   
return g_off;                                                                                                                                                                                           
end get_level_number;                                                                                                                                                                                   
/**                                                                                                                                                                                                     
* Determines if callstack should be while logging                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @return                                                                                                                                                                                               
*/                                                                                                                                                                                                      
function include_call_stack                                                                                                                                                                             
return boolean                                                                                                                                                                                          
is                                                                                                                                                                                                      
l_call_stack_pref logger_prefs.pref_value%type;                                                                                                                                                         
begin                                                                                                                                                                                                   
return false;                                                                                                                                                                                           
end include_call_stack;                                                                                                                                                                                 
/**                                                                                                                                                                                                     
* Returns date diff in "... sectons/minutes/days/etc ago" format                                                                                                                                        
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_date_start                                                                                                                                                                                   
* @param p_date_stop                                                                                                                                                                                    
* @return Text version of date diff                                                                                                                                                                     
*/                                                                                                                                                                                                      
function date_text_format_base (                                                                                                                                                                        
p_date_start in date,                                                                                                                                                                                   
p_date_stop  in date)                                                                                                                                                                                   
return varchar2                                                                                                                                                                                         
as                                                                                                                                                                                                      
x varchar2(20);                                                                                                                                                                                         
begin                                                                                                                                                                                                   
return null;                                                                                                                                                                                            
end date_text_format_base;                                                                                                                                                                              
/**                                                                                                                                                                                                     
* Parses the callstack to get unit and line number                                                                                                                                                      
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Private                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_callstack                                                                                                                                                                                    
* @param o_unit                                                                                                                                                                                         
* @param o_lineno                                                                                                                                                                                       
*/                                                                                                                                                                                                      
procedure get_debug_info(                                                                                                                                                                               
p_callstack in clob,                                                                                                                                                                                    
o_unit out varchar2,                                                                                                                                                                                    
o_lineno out varchar2 )                                                                                                                                                                                 
as                                                                                                                                                                                                      
--                                                                                                                                                                                                      
l_callstack varchar2(10000) := p_callstack;                                                                                                                                                             
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end get_debug_info;                                                                                                                                                                                     
/**                                                                                                                                                                                                     
* Main procedure that will store log data into logger_logs table                                                                                                                                        
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Modifications                                                                                                                                                                                         
*  - 2.1.0: If text is > 4000 characters, it will be moved to the EXTRA column                                                                                                                          
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_text                                                                                                                                                                                         
* @param p_log_level                                                                                                                                                                                    
* @param p_scope                                                                                                                                                                                        
* @param p_extra                                                                                                                                                                                        
* @param p_callstack                                                                                                                                                                                    
* @param p_params                                                                                                                                                                                       
*                                                                                                                                                                                                       
*/                                                                                                                                                                                                      
procedure log_internal(                                                                                                                                                                                 
p_text in varchar2,                                                                                                                                                                                     
p_log_level in number,                                                                                                                                                                                  
p_scope in varchar2,                                                                                                                                                                                    
p_extra in clob default null,                                                                                                                                                                           
p_callstack in varchar2 default null,                                                                                                                                                                   
p_params in tab_param default logger.gc_empty_tab_param)                                                                                                                                                
is                                                                                                                                                                                                      
l_proc_name varchar2(100);                                                                                                                                                                              
l_lineno varchar2(100);                                                                                                                                                                                 
l_text varchar2(32767);                                                                                                                                                                                 
l_callstack varchar2(3000);                                                                                                                                                                             
l_extra logger_logs.extra%type;                                                                                                                                                                         
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end log_internal;                                                                                                                                                                                       
/**                                                                                                                                                                                                     
* Run plugin                                                                                                                                                                                            
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Currently only supports error type plugin but has been built to support other types                                                                                                                
*  - -- FUTURE mdsouza: When supporting other plugin types put conditional compilation where applicable                                                                                                 
*  - -- FUTURE mdsouza: Include this in tests (#86)                                                                                                                                                     
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #46                                                                                                                                                                                                
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 11-Mar-2015                                                                                                                                                                                  
* @param p_logger_log Record that plugin should be run for                                                                                                                                              
*/                                                                                                                                                                                                      
procedure run_plugin(p_logger_log in logger.rec_logger_log)                                                                                                                                             
as                                                                                                                                                                                                      
l_plugin_fn logger_prefs.pref_value%type;                                                                                                                                                               
l_plugin_ctx varchar2(30);                                                                                                                                                                              
l_sql varchar2(255);                                                                                                                                                                                    
-- For exception block                                                                                                                                                                                  
l_params logger.tab_param;                                                                                                                                                                              
l_scope logger_logs.scope%type;                                                                                                                                                                         
-- Mark "in_plugin" as true/false                                                                                                                                                                       
-- Put in separate procedure since more logic may be applied                                                                                                                                            
-- And called from exception block as well                                                                                                                                                              
procedure start_stop_plugin(                                                                                                                                                                            
p_in_plugin boolean -- True/False depending on action                                                                                                                                                   
)                                                                                                                                                                                                       
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
if p_logger_log.logger_level = logger.g_error then                                                                                                                                                      
g_in_plugin_error := p_in_plugin;                                                                                                                                                                       
end if;                                                                                                                                                                                                 
end start_stop_plugin;                                                                                                                                                                                  
function f_get_set_global_context(                                                                                                                                                                      
p_ctx in varchar2                                                                                                                                                                                       
)                                                                                                                                                                                                       
return varchar2                                                                                                                                                                                         
as                                                                                                                                                                                                      
l_return varchar2(255);                                                                                                                                                                                 
begin                                                                                                                                                                                                   
l_return := upper(get_pref(p_pref_name =>                                                                                                                                                               
case                                                                                                                                                                                                    
when p_logger_log.logger_level = g_error then gc_ctx_plugin_fn_error                                                                                                                                    
end                                                                                                                                                                                                     
));                                                                                                                                                                                                     
save_global_context(p_attribute => p_ctx, p_value => l_return);                                                                                                                                         
return l_return;                                                                                                                                                                                        
end f_get_set_global_context;                                                                                                                                                                           
begin                                                                                                                                                                                                   
start_stop_plugin(p_in_plugin => true);                                                                                                                                                                 
if 1=2 then                                                                                                                                                                                             
null;                                                                                                                                                                                                   
elsif p_logger_log.logger_level = logger.g_error then                                                                                                                                                   
l_plugin_ctx := gc_ctx_plugin_fn_error;                                                                                                                                                                 
end if;                                                                                                                                                                                                 
if l_plugin_ctx is not null then                                                                                                                                                                        
l_plugin_fn := coalesce(                                                                                                                                                                                
sys_context(g_context_name, l_plugin_ctx),                                                                                                                                                              
f_get_set_global_context(p_ctx => l_plugin_ctx));                                                                                                                                                       
if 1=1                                                                                                                                                                                                  
and l_plugin_fn is not null                                                                                                                                                                             
and l_plugin_fn != 'NONE' then                                                                                                                                                                          
l_sql := 'begin ' || l_plugin_fn || '(logger.get_plugin_rec(' || p_logger_log.logger_level || ')); end;';                                                                                               
execute immediate l_sql;                                                                                                                                                                                
else                                                                                                                                                                                                    
-- Should never reach this point since plugin_fn should have a value                                                                                                                                    
logger.log_error('Error l_plugin_fn does not have value');                                                                                                                                              
end if; -- l_plugin_fn                                                                                                                                                                                  
else                                                                                                                                                                                                    
-- Should never reach this point since plugin_ctx should have a value                                                                                                                                   
logger.log_error('Error l_plugin_ctx does not have value');                                                                                                                                             
end if; -- l_plugin_ctx is not null                                                                                                                                                                     
start_stop_plugin(p_in_plugin => false);                                                                                                                                                                
exception                                                                                                                                                                                               
when others then                                                                                                                                                                                        
logger.append_param(l_params, 'Logger.id', p_logger_log.id);                                                                                                                                            
logger.append_param(l_params, 'Logger.logger_level', p_logger_log.logger_level);                                                                                                                        
logger.append_param(l_params, 'Plugin Function', l_plugin_fn);                                                                                                                                          
select scope                                                                                                                                                                                            
into l_scope                                                                                                                                                                                            
from logger_logs_5_min                                                                                                                                                                                  
where 1=1                                                                                                                                                                                               
and id = p_logger_log.id;                                                                                                                                                                               
logger.log_error('Exception in plugin procedure: ' || l_plugin_fn, l_scope, null, l_params);                                                                                                            
start_stop_plugin(p_in_plugin => false);                                                                                                                                                                
raise;                                                                                                                                                                                                  
end run_plugin;                                                                                                                                                                                         
-- **** PUBLIC ****                                                                                                                                                                                     
/**                                                                                                                                                                                                     
* Sets all the contexts to null                                                                                                                                                                         
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Though this is public it is not a documented procedure. Only used with logger_configure.                                                                                                           
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #46 Plugin support                                                                                                                                                                                 
*  - #110 Clear all contexts (including ones with client identifier)                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
*/                                                                                                                                                                                                      
procedure null_global_contexts                                                                                                                                                                          
is                                                                                                                                                                                                      
pragma autonomous_transaction;                                                                                                                                                                          
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
commit;                                                                                                                                                                                                 
end null_global_contexts;                                                                                                                                                                               
/**                                                                                                                                                                                                     
* Converts string names to text value                                                                                                                                                                   
*                                                                                                                                                                                                       
* Changes                                                                                                                                                                                               
*  - 2.1.0: Start to use global variables and correct numbers                                                                                                                                           
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
*                                                                                                                                                                                                       
* @param p_level String representation of level                                                                                                                                                         
* @return level number. -1 if not found                                                                                                                                                                 
*/                                                                                                                                                                                                      
function convert_level_char_to_num(                                                                                                                                                                     
p_level in varchar2)                                                                                                                                                                                    
return number                                                                                                                                                                                           
is                                                                                                                                                                                                      
l_level         number;                                                                                                                                                                                 
begin                                                                                                                                                                                                   
return null;                                                                                                                                                                                            
return l_level;                                                                                                                                                                                         
end convert_level_char_to_num;                                                                                                                                                                          
/**                                                                                                                                                                                                     
* Converts the logger level num to char format                                                                                                                                                          
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #48                                                                                                                                                                                                
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 14-Jun-2014                                                                                                                                                                                  
* @param p_level                                                                                                                                                                                        
* @return Logger level string format                                                                                                                                                                    
*/                                                                                                                                                                                                      
function convert_level_num_to_char(                                                                                                                                                                     
p_level in number)                                                                                                                                                                                      
return varchar2                                                                                                                                                                                         
is                                                                                                                                                                                                      
l_return varchar2(255);                                                                                                                                                                                 
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
return l_return;                                                                                                                                                                                        
end convert_level_num_to_char;                                                                                                                                                                          
/**                                                                                                                                                                                                     
* Determines if the statement can be stored in LOGGER_LOGS                                                                                                                                              
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #44: Expose publically                                                                                                                                                                             
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
*                                                                                                                                                                                                       
* @param p_level Level (number)                                                                                                                                                                         
* @return True of statement can be logged to LOGGER_LOGS                                                                                                                                                
*/                                                                                                                                                                                                      
function ok_to_log(p_level in number)                                                                                                                                                                   
return boolean                                                                                                                                                                                          
is                                                                                                                                                                                                      
l_level number;                                                                                                                                                                                         
l_level_char varchar2(50);                                                                                                                                                                              
begin                                                                                                                                                                                                   
return false;                                                                                                                                                                                           
end ok_to_log;                                                                                                                                                                                          
/**                                                                                                                                                                                                     
* Determines if log statements will actually be stored.                                                                                                                                                 
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 25-Jul-2013                                                                                                                                                                                  
*                                                                                                                                                                                                       
* @param p_level Level (DEBUG etc..)                                                                                                                                                                    
* @return True of log statements for that level or below will be logged                                                                                                                                 
*/                                                                                                                                                                                                      
function ok_to_log(p_level in varchar2)                                                                                                                                                                 
return boolean                                                                                                                                                                                          
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
return false;                                                                                                                                                                                           
end ok_to_log;                                                                                                                                                                                          
/**                                                                                                                                                                                                     
* ???                                                                                                                                                                                                   
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_date                                                                                                                                                                                         
* @return                                                                                                                                                                                               
*/                                                                                                                                                                                                      
function date_text_format (p_date in date)                                                                                                                                                              
return varchar2                                                                                                                                                                                         
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
return null;                                                                                                                                                                                            
end date_text_format;                                                                                                                                                                                   
function get_character_codes(                                                                                                                                                                           
p_string        in varchar2,                                                                                                                                                                            
p_show_common_codes   in boolean default true)                                                                                                                                                          
return varchar2                                                                                                                                                                                         
is                                                                                                                                                                                                      
l_string  varchar2(32767);                                                                                                                                                                              
l_dump    varchar2(32767);                                                                                                                                                                              
l_return  varchar2(32767);                                                                                                                                                                              
begin                                                                                                                                                                                                   
-- replace tabs with ^                                                                                                                                                                                  
l_string := replace(p_string,chr(9),'^');                                                                                                                                                               
-- replace all other control characters such as carriage return / line feeds with ~                                                                                                                     
l_string := regexp_replace(l_string,'[[:cntrl:]]','~',1,0,'m');                                                                                                                                         
select dump(p_string) into l_dump from dual;                                                                                                                                                            
l_dump  := regexp_replace(l_dump,'(^.+?:)(.*)','\2',1,0); -- get everything after the :                                                                                                                 
l_dump  := ','||l_dump||','; -- leading and trailing commas                                                                                                                                             
l_dump  := replace(l_dump,',',',,'); -- double the commas. this is for the regex.                                                                                                                       
l_dump  := regexp_replace(l_dump,'(,)([[:digit:]]{1})(,)','\1  \2\3',1,0); -- lpad all single digit numbers out to 3                                                                                    
l_dump  := regexp_replace(l_dump,'(,)([[:digit:]]{2})(,)','\1 \2\3',1,0);  -- lpad all double digit numbers out to 3                                                                                    
l_dump  := ltrim(replace(l_dump,',,',','),','); -- remove the double commas                                                                                                                             
l_dump  := lpad(' ',(5-instr(l_dump,',')),' ')||l_dump;                                                                                                                                                 
-- replace every individual character with 2 spaces, itself and a comma so it lines up with the dump output                                                                                             
l_string := ' '||regexp_replace(l_string,'(.){1}','  \1,',1,0);                                                                                                                                         
l_return := rtrim(l_dump,',') || chr(10) || rtrim(l_string,',');                                                                                                                                        
if p_show_common_codes then                                                                                                                                                                             
l_return := 'Common Codes: 13=Line Feed, 10=Carriage Return, 32=Space, 9=Tab'||chr(10) ||l_return;                                                                                                      
end if;                                                                                                                                                                                                 
return l_return;                                                                                                                                                                                        
end get_character_codes;                                                                                                                                                                                
/**                                                                                                                                                                                                     
* Store APEX items in logger_logs_apex_items                                                                                                                                                            
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #115: Only log not-null values                                                                                                                                                                     
*  - #114: Bulk insert (no more row by row)                                                                                                                                                             
*  - #54: Support for p_item_type                                                                                                                                                                       
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_log_id logger_logs.id to reference                                                                                                                                                           
* @param p_item_type Either the g_apex_item_type_... type or just the APEX page number for a specific page. It is assumed that it has been validated by the time it hits here.                          
* @param p_log_null_items If set to false, null values won't be logged                                                                                                                                  
*/                                                                                                                                                                                                      
procedure snapshot_apex_items(                                                                                                                                                                          
p_log_id in logger_logs.id%type,                                                                                                                                                                        
p_item_type in varchar2,                                                                                                                                                                                
p_log_null_items in boolean)                                                                                                                                                                            
is                                                                                                                                                                                                      
l_app_session number;                                                                                                                                                                                   
l_app_id number;                                                                                                                                                                                        
l_log_null_item_yn varchar2(1);                                                                                                                                                                         
l_item_type varchar2(30) := upper(p_item_type);                                                                                                                                                         
l_item_type_page_id number;                                                                                                                                                                             
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
-- $$no_op                                                                                                                                                                                              
end snapshot_apex_items;                                                                                                                                                                                
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #46: Added plugin support                                                                                                                                                                          
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_text                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_extra                                                                                                                                                                                        
* @param p_params                                                                                                                                                                                       
*/                                                                                                                                                                                                      
procedure log_error(                                                                                                                                                                                    
p_text in varchar2 default null,                                                                                                                                                                        
p_scope in varchar2 default null,                                                                                                                                                                       
p_extra in clob default null,                                                                                                                                                                           
p_params in tab_param default logger.gc_empty_tab_param)                                                                                                                                                
is                                                                                                                                                                                                      
l_proc_name varchar2(100);                                                                                                                                                                              
l_lineno varchar2(100);                                                                                                                                                                                 
l_text varchar2(32767);                                                                                                                                                                                 
l_call_stack varchar2(4000);                                                                                                                                                                            
l_extra clob;                                                                                                                                                                                           
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end log_error;                                                                                                                                                                                          
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_text                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_extra                                                                                                                                                                                        
* @param p_params                                                                                                                                                                                       
*/                                                                                                                                                                                                      
procedure log_permanent(                                                                                                                                                                                
p_text in varchar2,                                                                                                                                                                                     
p_scope in varchar2 default null,                                                                                                                                                                       
p_extra in clob default null,                                                                                                                                                                           
p_params in tab_param default logger.gc_empty_tab_param)                                                                                                                                                
is                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end log_permanent;                                                                                                                                                                                      
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_text                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_extra                                                                                                                                                                                        
* @param p_params                                                                                                                                                                                       
*/                                                                                                                                                                                                      
procedure log_warning(                                                                                                                                                                                  
p_text in varchar2,                                                                                                                                                                                     
p_scope in varchar2 default null,                                                                                                                                                                       
p_extra in clob default null,                                                                                                                                                                           
p_params in tab_param default logger.gc_empty_tab_param)                                                                                                                                                
is                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end log_warning;                                                                                                                                                                                        
/**                                                                                                                                                                                                     
* Wrapper for log_warning                                                                                                                                                                               
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - #80                                                                                                                                                                                                
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 9-9-Mar-2015                                                                                                                                                                                 
* @param p_text                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_extra                                                                                                                                                                                        
* @param p_params                                                                                                                                                                                       
*/                                                                                                                                                                                                      
procedure log_warn(                                                                                                                                                                                     
p_text in varchar2,                                                                                                                                                                                     
p_scope in varchar2 default null,                                                                                                                                                                       
p_extra in clob default null,                                                                                                                                                                           
p_params in tab_param default logger.gc_empty_tab_param)                                                                                                                                                
is                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
logger.log_warning(                                                                                                                                                                                     
p_text => p_text,                                                                                                                                                                                       
p_scope => p_scope,                                                                                                                                                                                     
p_extra => p_extra,                                                                                                                                                                                     
p_params => p_params                                                                                                                                                                                    
);                                                                                                                                                                                                      
end log_warn;                                                                                                                                                                                           
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_text                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_extra                                                                                                                                                                                        
* @param p_params                                                                                                                                                                                       
*/                                                                                                                                                                                                      
procedure log_information(                                                                                                                                                                              
p_text in varchar2,                                                                                                                                                                                     
p_scope in varchar2 default null,                                                                                                                                                                       
p_extra in clob default null,                                                                                                                                                                           
p_params in tab_param default logger.gc_empty_tab_param)                                                                                                                                                
is                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end log_information;                                                                                                                                                                                    
/**                                                                                                                                                                                                     
* Wrapper for short call to log_information                                                                                                                                                             
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #80                                                                                                                                                                                                
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 9-Mar-2015                                                                                                                                                                                   
* @param p_text                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_extra                                                                                                                                                                                        
* @param p_params                                                                                                                                                                                       
*/                                                                                                                                                                                                      
procedure log_info(                                                                                                                                                                                     
p_text in varchar2,                                                                                                                                                                                     
p_scope in varchar2 default null,                                                                                                                                                                       
p_extra in clob default null,                                                                                                                                                                           
p_params in tab_param default logger.gc_empty_tab_param)                                                                                                                                                
is                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
logger.log_information(                                                                                                                                                                                 
p_text => p_text,                                                                                                                                                                                       
p_scope => p_scope,                                                                                                                                                                                     
p_extra => p_extra,                                                                                                                                                                                     
p_params => p_params                                                                                                                                                                                    
);                                                                                                                                                                                                      
end log_info;                                                                                                                                                                                           
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_text                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_extra                                                                                                                                                                                        
* @param p_params                                                                                                                                                                                       
*/                                                                                                                                                                                                      
procedure log(                                                                                                                                                                                          
p_text in varchar2,                                                                                                                                                                                     
p_scope in varchar2 default null,                                                                                                                                                                       
p_extra in clob default null,                                                                                                                                                                           
p_params in tab_param default logger.gc_empty_tab_param)                                                                                                                                                
is                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end log;                                                                                                                                                                                                
/**                                                                                                                                                                                                     
* Get list of CGI values                                                                                                                                                                                
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_show_null                                                                                                                                                                                    
* @return CGI values                                                                                                                                                                                    
*/                                                                                                                                                                                                      
function get_cgi_env(                                                                                                                                                                                   
p_show_null   in boolean default false)                                                                                                                                                                 
return clob                                                                                                                                                                                             
is                                                                                                                                                                                                      
l_cgienv clob;                                                                                                                                                                                          
begin                                                                                                                                                                                                   
return null;                                                                                                                                                                                            
end get_cgi_env;                                                                                                                                                                                        
/**                                                                                                                                                                                                     
* Logs system environment variables                                                                                                                                                                     
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
* - #29 Support for definging level                                                                                                                                                                     
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_detail_level USER, ALL, NLS, INSTANCE                                                                                                                                                        
* @param p_show_null                                                                                                                                                                                    
* @param p_scope                                                                                                                                                                                        
* @param p_level Highest level to run at (default logger.g_debug). Example. If you set to logger.g_error it will work when both in DEBUG and ERROR modes. However if set to logger.g_debug(default) will
not store values when level is set to ERROR.                                                                                                                                                            
*/                                                                                                                                                                                                      
procedure log_userenv(                                                                                                                                                                                  
p_detail_level in varchar2 default 'USER',-- ALL, NLS, USER, INSTANCE,                                                                                                                                  
p_show_null in boolean default false,                                                                                                                                                                   
p_scope in logger_logs.scope%type default null,                                                                                                                                                         
p_level in logger_logs.logger_level%type default null)                                                                                                                                                  
is                                                                                                                                                                                                      
l_extra clob;                                                                                                                                                                                           
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end log_userenv;                                                                                                                                                                                        
/**                                                                                                                                                                                                     
* Logs CGI environment variables                                                                                                                                                                        
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_show_null                                                                                                                                                                                    
* @param p_scope                                                                                                                                                                                        
* @param p_level Highest level to run at (default logger.g_debug). Example. If you set to logger.g_error it will work when both in DEBUG and ERROR modes. However if set to logger.g_debug(default) will
not store values when level is set to ERROR.                                                                                                                                                            
*/                                                                                                                                                                                                      
procedure log_cgi_env(                                                                                                                                                                                  
p_show_null in boolean default false,                                                                                                                                                                   
p_scope in logger_logs.scope%type default null,                                                                                                                                                         
p_level in logger_logs.logger_level%type default null)                                                                                                                                                  
is                                                                                                                                                                                                      
l_extra clob;                                                                                                                                                                                           
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end log_cgi_env;                                                                                                                                                                                        
/**                                                                                                                                                                                                     
* Logs character codes for given string                                                                                                                                                                 
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_text                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_show_common_codes                                                                                                                                                                            
* @param p_level Highest level to run at (default logger.g_debug). Example. If you set to logger.g_error it will work when both in DEBUG and ERROR modes. However if set to logger.g_debug(default) will
not store values when level is set to ERROR.                                                                                                                                                            
*/                                                                                                                                                                                                      
procedure log_character_codes(                                                                                                                                                                          
p_text in varchar2,                                                                                                                                                                                     
p_scope in logger_logs.scope%type default null,                                                                                                                                                         
p_show_common_codes in boolean default true,                                                                                                                                                            
p_level in logger_logs.logger_level%type default null)                                                                                                                                                  
is                                                                                                                                                                                                      
l_error varchar2(4000);                                                                                                                                                                                 
l_dump clob;                                                                                                                                                                                            
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end log_character_codes;                                                                                                                                                                                
/**                                                                                                                                                                                                     
* Log's APEX items                                                                                                                                                                                      
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #115 Only log not-null values                                                                                                                                                                      
*  - #29 Support for definging level                                                                                                                                                                    
*  - #54: Add p_item_type                                                                                                                                                                               
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_text                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_item_type Either the g_apex_item_type_... type or just the APEX page number for a specific page.                                                                                             
* @param p_log_null_items If set to false, null values won't be logged                                                                                                                                  
* @param p_level Highest level to run at (default logger.g_debug). Example. If you set to logger.g_error it will work when both in DEBUG and ERROR modes. However if set to logger.g_debug(default) will
not store values when level is set to ERROR.                                                                                                                                                            
*/                                                                                                                                                                                                      
procedure log_apex_items(                                                                                                                                                                               
p_text in varchar2 default 'Log APEX Items',                                                                                                                                                            
p_scope in logger_logs.scope%type default null,                                                                                                                                                         
p_item_type in varchar2 default logger.g_apex_item_type_all,                                                                                                                                            
p_log_null_items in boolean default true,                                                                                                                                                               
p_level in logger_logs.logger_level%type default null)                                                                                                                                                  
is                                                                                                                                                                                                      
l_error varchar2(4000);                                                                                                                                                                                 
pragma autonomous_transaction;                                                                                                                                                                          
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
commit;                                                                                                                                                                                                 
end log_apex_items;                                                                                                                                                                                     
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #73/#75: Use localtimestamp                                                                                                                                                                        
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_unit                                                                                                                                                                                         
* @param p_log_in_table                                                                                                                                                                                 
*/                                                                                                                                                                                                      
procedure time_start(                                                                                                                                                                                   
p_unit in varchar2,                                                                                                                                                                                     
p_log_in_table in boolean default true)                                                                                                                                                                 
is                                                                                                                                                                                                      
l_proc_name varchar2(100);                                                                                                                                                                              
l_text varchar2(4000);                                                                                                                                                                                  
l_pad varchar2(100);                                                                                                                                                                                    
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end time_start;                                                                                                                                                                                         
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #73: Remove additional timer decrement since it was already happening in function time_stop                                                                                                        
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_scope                                                                                                                                                                                        
* @param p_unit                                                                                                                                                                                         
*/                                                                                                                                                                                                      
procedure time_stop(                                                                                                                                                                                    
p_unit in varchar2,                                                                                                                                                                                     
p_scope in varchar2 default null)                                                                                                                                                                       
is                                                                                                                                                                                                      
l_time_string varchar2(50);                                                                                                                                                                             
l_text varchar2(4000);                                                                                                                                                                                  
l_pad varchar2(100);                                                                                                                                                                                    
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end time_stop;                                                                                                                                                                                          
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #73/#75: Trim timezone from systimestamp to localtimestamp                                                                                                                                         
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_unit                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_log_in_table                                                                                                                                                                                 
* @return Timer string                                                                                                                                                                                  
*/                                                                                                                                                                                                      
function time_stop(                                                                                                                                                                                     
p_unit in varchar2,                                                                                                                                                                                     
p_scope in varchar2 default null,                                                                                                                                                                       
p_log_in_table IN boolean default true)                                                                                                                                                                 
return varchar2                                                                                                                                                                                         
is                                                                                                                                                                                                      
l_time_string varchar2(50);                                                                                                                                                                             
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end time_stop;                                                                                                                                                                                          
/**                                                                                                                                                                                                     
*                                                                                                                                                                                                       
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #73/#75: Trim timezone from systimestamp to localtimestamp                                                                                                                                         
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_unit                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_log_in_table                                                                                                                                                                                 
* @return Timer in seconds                                                                                                                                                                              
*/                                                                                                                                                                                                      
function time_stop_seconds(                                                                                                                                                                             
p_unit in varchar2,                                                                                                                                                                                     
p_scope in varchar2 default null,                                                                                                                                                                       
p_log_in_table in boolean default true                                                                                                                                                                  
)                                                                                                                                                                                                       
return number                                                                                                                                                                                           
is                                                                                                                                                                                                      
l_time_string varchar2(50);                                                                                                                                                                             
l_seconds number;                                                                                                                                                                                       
l_interval interval day to second;                                                                                                                                                                      
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end time_stop_seconds;                                                                                                                                                                                  
/**                                                                                                                                                                                                     
* Resets all timers                                                                                                                                                                                     
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
*/                                                                                                                                                                                                      
procedure time_reset                                                                                                                                                                                    
is                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end time_reset;                                                                                                                                                                                         
/**                                                                                                                                                                                                     
* Returns Global or User preference                                                                                                                                                                     
* User preference is only valid for LEVEL and INCLUDE_CALL_STACK                                                                                                                                        
*  - If a user setting exists, it will be returned, if not the system level preference will be return                                                                                                   
*                                                                                                                                                                                                       
* Updates                                                                                                                                                                                               
*  - 2.0.0: Added user preference support                                                                                                                                                               
*  - 2.1.2: Fixed issue when calling set_level with the same client_id multiple times                                                                                                                   
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #127: Added logger_prefs.pref_type                                                                                                                                                                 
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
*                                                                                                                                                                                                       
* @param p_pref_name                                                                                                                                                                                    
* @param p_pref_type Namespace for preference                                                                                                                                                           
*/                                                                                                                                                                                                      
function get_pref(                                                                                                                                                                                      
p_pref_name in logger_prefs.pref_name%type,                                                                                                                                                             
p_pref_type in logger_prefs.pref_type%type default logger.g_pref_type_logger)                                                                                                                           
return varchar2                                                                                                                                                                                         
result_cache                                                                                                                                                                                            
is                                                                                                                                                                                                      
l_scope varchar2(30) := 'get_pref';                                                                                                                                                                     
l_pref_value logger_prefs.pref_value%type;                                                                                                                                                              
l_client_id logger_prefs_by_client_id.client_id%type;                                                                                                                                                   
l_pref_name logger_prefs.pref_name%type := upper(p_pref_name);                                                                                                                                          
l_pref_type logger_prefs.pref_type%type := upper(p_pref_type);                                                                                                                                          
begin                                                                                                                                                                                                   
return null;                                                                                                                                                                                            
exception                                                                                                                                                                                               
when no_data_found then                                                                                                                                                                                 
return null;                                                                                                                                                                                            
when others then                                                                                                                                                                                        
raise;                                                                                                                                                                                                  
end get_pref;                                                                                                                                                                                           
/**                                                                                                                                                                                                     
* Sets a preference                                                                                                                                                                                     
* If it does not exist, it will insert one                                                                                                                                                              
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Does not support setting system preferences                                                                                                                                                        
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #127                                                                                                                                                                                               
*                                                                                                                                                                                                       
* @author Alex Nuijten / Martin D'Souza                                                                                                                                                                 
* @created 24-APR-2015                                                                                                                                                                                  
* @param p_pref_type                                                                                                                                                                                    
* @param p_pref_name                                                                                                                                                                                    
* @param p_pref_value                                                                                                                                                                                   
*/                                                                                                                                                                                                      
procedure set_pref(                                                                                                                                                                                     
p_pref_type in logger_prefs.pref_type%type,                                                                                                                                                             
p_pref_name in logger_prefs.pref_name%type,                                                                                                                                                             
p_pref_value in logger_prefs.pref_value%type)                                                                                                                                                           
as                                                                                                                                                                                                      
l_pref_type logger_prefs.pref_type%type := trim(upper(p_pref_type));                                                                                                                                    
l_pref_name logger_prefs.pref_name%type := trim(upper(p_pref_name));                                                                                                                                    
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
-- $no_op                                                                                                                                                                                               
end set_pref;                                                                                                                                                                                           
/**                                                                                                                                                                                                     
* Removes a Preference                                                                                                                                                                                  
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Does not support setting system preferences                                                                                                                                                        
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #127                                                                                                                                                                                               
*                                                                                                                                                                                                       
* @author Alex Nuijten / Martin D'Souza                                                                                                                                                                 
* @created 30-APR-2015                                                                                                                                                                                  
*                                                                                                                                                                                                       
* @param p_pref_type                                                                                                                                                                                    
* @param p_pref_name                                                                                                                                                                                    
*/                                                                                                                                                                                                      
procedure del_pref(                                                                                                                                                                                     
p_pref_type in logger_prefs.pref_type%type,                                                                                                                                                             
p_pref_name in logger_prefs.pref_name%type)                                                                                                                                                             
is                                                                                                                                                                                                      
l_pref_type logger_prefs.pref_type%type := trim(upper(p_pref_type));                                                                                                                                    
l_pref_name logger_prefs.pref_name%type := trim(upper (p_pref_name));                                                                                                                                   
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end del_pref;                                                                                                                                                                                           
/**                                                                                                                                                                                                     
* Purges logger_logs data                                                                                                                                                                               
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #48 Support for overloading                                                                                                                                                                        
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 14-Jun-2014                                                                                                                                                                                  
* @param p_purge_after_days                                                                                                                                                                             
* @param p_purge_min_level                                                                                                                                                                              
*/                                                                                                                                                                                                      
procedure purge(                                                                                                                                                                                        
p_purge_after_days in number default null,                                                                                                                                                              
p_purge_min_level in number)                                                                                                                                                                            
is                                                                                                                                                                                                      
pragma autonomous_transaction;                                                                                                                                                                          
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
commit;                                                                                                                                                                                                 
end purge;                                                                                                                                                                                              
/**                                                                                                                                                                                                     
* Wrapper for Purge (to accept number for purge_min_level)                                                                                                                                              
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_purge_after_days                                                                                                                                                                             
* @param p_purge_min_level                                                                                                                                                                              
*/                                                                                                                                                                                                      
procedure purge(                                                                                                                                                                                        
p_purge_after_days in varchar2 default null,                                                                                                                                                            
p_purge_min_level in varchar2 default null)                                                                                                                                                             
is                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end purge;                                                                                                                                                                                              
/**                                                                                                                                                                                                     
* Purges all records that aren't marked as permanent                                                                                                                                                    
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
*/                                                                                                                                                                                                      
procedure purge_all                                                                                                                                                                                     
is                                                                                                                                                                                                      
l_purge_level number  := g_permanent;                                                                                                                                                                   
pragma autonomous_transaction;                                                                                                                                                                          
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
commit;                                                                                                                                                                                                 
end purge_all;                                                                                                                                                                                          
/**                                                                                                                                                                                                     
* Displays Logger's current status                                                                                                                                                                      
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
* @param p_output_format SQL-DEVELOPER | HTML | DBMS_OUPUT                                                                                                                                              
*/                                                                                                                                                                                                      
procedure status(                                                                                                                                                                                       
p_output_format in varchar2 default null) -- SQL-DEVELOPER | HTML | DBMS_OUPUT                                                                                                                          
is                                                                                                                                                                                                      
l_debug varchar2(50) := 'Disabled';                                                                                                                                                                     
l_apex varchar2(50) := 'Disabled';                                                                                                                                                                      
l_flashback varchar2(50) := 'Disabled';                                                                                                                                                                 
dummy varchar2(255);                                                                                                                                                                                    
l_output_format varchar2(30);                                                                                                                                                                           
l_version varchar2(20);                                                                                                                                                                                 
l_client_identifier logger_prefs_by_client_id.client_id%type;                                                                                                                                           
-- For current client info                                                                                                                                                                              
l_cur_logger_level logger_prefs_by_client_id.logger_level%type;                                                                                                                                         
l_cur_include_call_stack logger_prefs_by_client_id.include_call_stack%type;                                                                                                                             
l_cur_expiry_date logger_prefs_by_client_id.expiry_date%type;                                                                                                                                           
procedure display_output(                                                                                                                                                                               
p_name  in varchar2,                                                                                                                                                                                    
p_value in varchar2)                                                                                                                                                                                    
is                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
if l_output_format = 'SQL-DEVELOPER' then                                                                                                                                                               
dbms_output.put_line('<pre>'||rpad(p_name,25)||': <strong>'||p_value||'</strong></pre>');                                                                                                               
elsif l_output_format = 'HTTP' then                                                                                                                                                                     
htp.p('<br />'||p_name||': <strong>'||p_value||'</strong>');                                                                                                                                            
else                                                                                                                                                                                                    
dbms_output.put_line(rpad(p_name,25)||': '||p_value);                                                                                                                                                   
end if;                                                                                                                                                                                                 
end display_output;                                                                                                                                                                                     
begin                                                                                                                                                                                                   
if p_output_format is null then                                                                                                                                                                         
begin                                                                                                                                                                                                   
dummy := owa_util.get_cgi_env('HTTP_HOST');                                                                                                                                                             
l_output_format := 'HTTP';                                                                                                                                                                              
exception                                                                                                                                                                                               
when value_error then                                                                                                                                                                                   
l_output_format := 'DBMS_OUTPUT';                                                                                                                                                                       
dbms_output.enable;                                                                                                                                                                                     
end;                                                                                                                                                                                                    
else                                                                                                                                                                                                    
l_output_format := p_output_format;                                                                                                                                                                     
end if;                                                                                                                                                                                                 
display_output('Project Home Page','https://github.com/oraopensource/logger/');                                                                                                                         
display_output('Debug Level','NO-OP, Logger completely disabled.');                                                                                                                                     
end status;                                                                                                                                                                                             
/**                                                                                                                                                                                                     
* Sets the logger level                                                                                                                                                                                 
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #60 Allow security check to be bypassed for client specific logging level                                                                                                                          
*  - #48 Allow of numbers to be passed in p_level. Did not overload (see ticket comments as to why)                                                                                                     
*  - #110 Clear context values when level changes globally                                                                                                                                              
*  - #29 If p_level is deprecated, set to DEBUG                                                                                                                                                         
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
*                                                                                                                                                                                                       
* @param p_level Valid values: OFF,PERMANENT,ERROR,WARNING,INFORMATION,DEBUG,TIMING                                                                                                                     
* @param p_client_id Optional: If defined, will set the level for the given client identifier. If null will affect global settings                                                                      
* @param p_include_call_stack Optional: Only valid if p_client_id is defined Valid values: TRUE, FALSE. If not set will use the default system pref in logger_prefs.                                    
* @param p_client_id_expire_hours If p_client_id, expire after number of hours. If not defined, will default to system preference PREF_BY_CLIENT_ID_EXPIRE_HOURS                                        
*/                                                                                                                                                                                                      
procedure set_level(                                                                                                                                                                                    
p_level in varchar2 default logger.g_debug_name,                                                                                                                                                        
p_client_id in varchar2 default null,                                                                                                                                                                   
p_include_call_stack in varchar2 default null,                                                                                                                                                          
p_client_id_expire_hours in number default null                                                                                                                                                         
)                                                                                                                                                                                                       
is                                                                                                                                                                                                      
l_level varchar2(20);                                                                                                                                                                                   
l_ctx varchar2(2000);                                                                                                                                                                                   
l_include_call_stack varchar2(255);                                                                                                                                                                     
l_client_id_expire_hours number;                                                                                                                                                                        
l_expiry_date logger_prefs_by_client_id.expiry_date%type;                                                                                                                                               
l_id logger_logs.id%type;                                                                                                                                                                               
pragma autonomous_transaction;                                                                                                                                                                          
begin                                                                                                                                                                                                   
raise_application_error (-20000,                                                                                                                                                                        
'Either the NO-OP version of Logger is installed or it is compiled for NO-OP,  so you cannot set the level.');                                                                                          
commit;                                                                                                                                                                                                 
end set_level;                                                                                                                                                                                          
/**                                                                                                                                                                                                     
* Unsets a logger level for a given client_id                                                                                                                                                           
* This will only unset for client specific logger levels                                                                                                                                                
* Note: An explicit commit will occur in this procedure                                                                                                                                                 
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 6-Apr-2013                                                                                                                                                                                   
*                                                                                                                                                                                                       
* @param p_client_id Client identifier (case sensitive) to unset logger level in.                                                                                                                       
*/                                                                                                                                                                                                      
procedure unset_client_level(p_client_id in varchar2)                                                                                                                                                   
as                                                                                                                                                                                                      
pragma autonomous_transaction;                                                                                                                                                                          
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
commit;                                                                                                                                                                                                 
end unset_client_level;                                                                                                                                                                                 
/**                                                                                                                                                                                                     
* Unsets client_level that are stale (i.e. past thier expiry date)                                                                                                                                      
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 7-Apr-2013                                                                                                                                                                                   
*                                                                                                                                                                                                       
* @param p_unset_after_hours If null then preference UNSET_CLIENT_ID_LEVEL_AFTER_HOURS                                                                                                                  
*/                                                                                                                                                                                                      
procedure unset_client_level                                                                                                                                                                            
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end unset_client_level;                                                                                                                                                                                 
/**                                                                                                                                                                                                     
* Unsets all client specific preferences                                                                                                                                                                
* An implicit commit will occur as unset_client_level makes a commit                                                                                                                                    
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 7-Apr-2013                                                                                                                                                                                   
*                                                                                                                                                                                                       
*/                                                                                                                                                                                                      
procedure unset_client_level_all                                                                                                                                                                        
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end unset_client_level_all;                                                                                                                                                                             
/**                                                                                                                                                                                                     
* Displays commonly used dbms_output SQL*Plus settings                                                                                                                                                  
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  -                                                                                                                                                                                                    
*                                                                                                                                                                                                       
* @author Tyler Muth                                                                                                                                                                                    
* @created ???                                                                                                                                                                                          
*/                                                                                                                                                                                                      
procedure sqlplus_format                                                                                                                                                                                
is                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
execute immediate 'begin dbms_output.enable(1000000); end;';                                                                                                                                            
dbms_output.put_line('set linesize 200');                                                                                                                                                               
dbms_output.put_line('set pagesize 100');                                                                                                                                                               
dbms_output.put_line('column id format 999999');                                                                                                                                                        
dbms_output.put_line('column text format a75');                                                                                                                                                         
dbms_output.put_line('column call_stack format a100');                                                                                                                                                  
dbms_output.put_line('column extra format a100');                                                                                                                                                       
end sqlplus_format;                                                                                                                                                                                     
/**                                                                                                                                                                                                     
* Converts parameter to varchar2                                                                                                                                                                        
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - As this function could be useful for non-logging purposes will not apply a NO_OP to it for conditional compilation                                                                                 
*  - Need to call this tochar instead of to_char since there will be a conflict when calling it                                                                                                         
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #68                                                                                                                                                                                                
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 07-Jun-2014                                                                                                                                                                                  
* @param p_value                                                                                                                                                                                        
* @return varchar2 value for p_value                                                                                                                                                                    
*/                                                                                                                                                                                                      
function tochar(                                                                                                                                                                                        
p_val in number)                                                                                                                                                                                        
return varchar2                                                                                                                                                                                         
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
return to_char(p_val);                                                                                                                                                                                  
end tochar;                                                                                                                                                                                             
function tochar(                                                                                                                                                                                        
p_val in date)                                                                                                                                                                                          
return varchar2                                                                                                                                                                                         
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
return to_char(p_val, gc_date_format);                                                                                                                                                                  
end tochar;                                                                                                                                                                                             
function tochar(                                                                                                                                                                                        
p_val in timestamp)                                                                                                                                                                                     
return varchar2                                                                                                                                                                                         
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
return to_char(p_val, gc_timestamp_format);                                                                                                                                                             
end tochar;                                                                                                                                                                                             
function tochar(                                                                                                                                                                                        
p_val in timestamp with time zone)                                                                                                                                                                      
return varchar2                                                                                                                                                                                         
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
return to_char(p_val, gc_timestamp_tz_format);                                                                                                                                                          
end tochar;                                                                                                                                                                                             
function tochar(                                                                                                                                                                                        
p_val in timestamp with local time zone)                                                                                                                                                                
return varchar2                                                                                                                                                                                         
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
return to_char(p_val, gc_timestamp_tz_format);                                                                                                                                                          
end tochar;                                                                                                                                                                                             
-- #119: Return null for null booleans                                                                                                                                                                  
function tochar(                                                                                                                                                                                        
p_val in boolean)                                                                                                                                                                                       
return varchar2                                                                                                                                                                                         
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
return case p_val when true then 'TRUE' when false then 'FALSE' else null end;                                                                                                                          
end tochar;                                                                                                                                                                                             
-- Handle Parameters                                                                                                                                                                                    
/**                                                                                                                                                                                                     
* Append parameter to table of parameters                                                                                                                                                               
* Nothing is actually logged in this procedure                                                                                                                                                          
* This procedure is overloaded                                                                                                                                                                          
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #67: Updated to reference to_char functions                                                                                                                                                        
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 19-Jan-2013                                                                                                                                                                                  
*                                                                                                                                                                                                       
* @param p_params Table of parameters (param will be appended to this)                                                                                                                                  
* @param p_name Name                                                                                                                                                                                    
* @param p_val Value in its format. Will be converted to string                                                                                                                                         
*/                                                                                                                                                                                                      
procedure append_param(                                                                                                                                                                                 
p_params in out nocopy logger.tab_param,                                                                                                                                                                
p_name in varchar2,                                                                                                                                                                                     
p_val in varchar2                                                                                                                                                                                       
)                                                                                                                                                                                                       
as                                                                                                                                                                                                      
l_param logger.rec_param;                                                                                                                                                                               
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end append_param;                                                                                                                                                                                       
procedure append_param(                                                                                                                                                                                 
p_params in out nocopy logger.tab_param,                                                                                                                                                                
p_name in varchar2,                                                                                                                                                                                     
p_val in number)                                                                                                                                                                                        
as                                                                                                                                                                                                      
l_param logger.rec_param;                                                                                                                                                                               
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end append_param;                                                                                                                                                                                       
procedure append_param(                                                                                                                                                                                 
p_params in out nocopy logger.tab_param,                                                                                                                                                                
p_name in varchar2,                                                                                                                                                                                     
p_val in date)                                                                                                                                                                                          
as                                                                                                                                                                                                      
l_param logger.rec_param;                                                                                                                                                                               
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end append_param;                                                                                                                                                                                       
procedure append_param(                                                                                                                                                                                 
p_params in out nocopy logger.tab_param,                                                                                                                                                                
p_name in varchar2,                                                                                                                                                                                     
p_val in timestamp)                                                                                                                                                                                     
as                                                                                                                                                                                                      
l_param logger.rec_param;                                                                                                                                                                               
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end append_param;                                                                                                                                                                                       
procedure append_param(                                                                                                                                                                                 
p_params in out nocopy logger.tab_param,                                                                                                                                                                
p_name in varchar2,                                                                                                                                                                                     
p_val in timestamp with time zone)                                                                                                                                                                      
as                                                                                                                                                                                                      
l_param logger.rec_param;                                                                                                                                                                               
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end append_param;                                                                                                                                                                                       
procedure append_param(                                                                                                                                                                                 
p_params in out nocopy logger.tab_param,                                                                                                                                                                
p_name in varchar2,                                                                                                                                                                                     
p_val in timestamp with local time zone)                                                                                                                                                                
as                                                                                                                                                                                                      
l_param logger.rec_param;                                                                                                                                                                               
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end append_param;                                                                                                                                                                                       
procedure append_param(                                                                                                                                                                                 
p_params in out nocopy logger.tab_param,                                                                                                                                                                
p_name in varchar2,                                                                                                                                                                                     
p_val in boolean)                                                                                                                                                                                       
as                                                                                                                                                                                                      
l_param logger.rec_param;                                                                                                                                                                               
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
end append_param;                                                                                                                                                                                       
/**                                                                                                                                                                                                     
* Handles inserts into LOGGER_LOGS.                                                                                                                                                                     
*                                                                                                                                                                                                       
* Replaces trigger for both performance issues and to be a single location for all insert statements                                                                                                    
*                                                                                                                                                                                                       
* autonomous_transaction so commit will be performed after insert                                                                                                                                       
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 30-Jul-2013                                                                                                                                                                                  
*                                                                                                                                                                                                       
* Related Issues                                                                                                                                                                                        
*  - #31: Initial ticket                                                                                                                                                                                
*  - #51: Added SID column                                                                                                                                                                              
*  - #70: Fixed missing no_op flag                                                                                                                                                                      
*  - #109: Fix length check for multibyte characters                                                                                                                                                    
*                                                                                                                                                                                                       
* @param p_logger_level                                                                                                                                                                                 
* @param p_text                                                                                                                                                                                         
* @param p_scope                                                                                                                                                                                        
* @param p_call_stack                                                                                                                                                                                   
* @param p_unit_name                                                                                                                                                                                    
* @param p_line_no                                                                                                                                                                                      
* @param p_extra                                                                                                                                                                                        
* @param po_id ID entered into logger_logs for this record                                                                                                                                              
*/                                                                                                                                                                                                      
procedure ins_logger_logs(                                                                                                                                                                              
p_logger_level in logger_logs.logger_level%type,                                                                                                                                                        
p_text in varchar2 default null, -- Not using type since want to be able to pass in 32767 characters                                                                                                    
p_scope in logger_logs.scope%type default null,                                                                                                                                                         
p_call_stack in logger_logs.call_stack%type default null,                                                                                                                                               
p_unit_name in logger_logs.unit_name%type default null,                                                                                                                                                 
p_line_no in logger_logs.line_no%type default null,                                                                                                                                                     
p_extra in logger_logs.extra%type default null,                                                                                                                                                         
po_id out nocopy logger_logs.id%type                                                                                                                                                                    
)                                                                                                                                                                                                       
as                                                                                                                                                                                                      
pragma autonomous_transaction;                                                                                                                                                                          
l_id logger_logs.id%type;                                                                                                                                                                               
l_text varchar2(32767) := p_text;                                                                                                                                                                       
l_extra logger_logs.extra%type := p_extra;                                                                                                                                                              
l_tmp_clob clob;                                                                                                                                                                                        
begin                                                                                                                                                                                                   
null;                                                                                                                                                                                                   
-- $$NO_OP                                                                                                                                                                                              
commit;                                                                                                                                                                                                 
end ins_logger_logs;                                                                                                                                                                                    
/**                                                                                                                                                                                                     
* Does string replacement similar to C's sprintf                                                                                                                                                        
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - Uses the following replacement algorithm (in following order)                                                                                                                                      
*    - Replaces %s<n> with p_s<n>                                                                                                                                                                       
*    - Occurrences of %s (no number) are replaced with p_s1..p_s10 in order that they appear in text                                                                                                    
*    - %% is escaped to %                                                                                                                                                                               
*  - As this function could be useful for non-logging purposes will not apply a NO_OP to it for conditional compilation                                                                                 
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #32: Also see #59                                                                                                                                                                                  
*  - #95: Remove no_op clause                                                                                                                                                                           
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 15-Jun-2014                                                                                                                                                                                  
* @param p_str Messsage to format using %s and %d replacement strings                                                                                                                                   
* @param p_s1                                                                                                                                                                                           
* @param p_s2                                                                                                                                                                                           
* @param p_s3                                                                                                                                                                                           
* @param p_s4                                                                                                                                                                                           
* @param p_s5                                                                                                                                                                                           
* @param p_s6                                                                                                                                                                                           
* @param p_s7                                                                                                                                                                                           
* @param p_s8                                                                                                                                                                                           
* @param p_s9                                                                                                                                                                                           
* @param p_s10                                                                                                                                                                                          
* @return p_msg with strings replaced                                                                                                                                                                   
*/                                                                                                                                                                                                      
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
return varchar2                                                                                                                                                                                         
as                                                                                                                                                                                                      
l_return varchar2(4000);                                                                                                                                                                                
c_substring_regexp constant varchar2(10) := '%s';                                                                                                                                                       
begin                                                                                                                                                                                                   
l_return := p_str;                                                                                                                                                                                      
-- Replace %s<n> with p_s<n>``                                                                                                                                                                          
for i in 1..10 loop                                                                                                                                                                                     
l_return := regexp_replace(l_return, c_substring_regexp || i,                                                                                                                                           
case                                                                                                                                                                                                    
when i = 1 then p_s1                                                                                                                                                                                    
when i = 2 then p_s2                                                                                                                                                                                    
when i = 3 then p_s3                                                                                                                                                                                    
when i = 4 then p_s4                                                                                                                                                                                    
when i = 5 then p_s5                                                                                                                                                                                    
when i = 6 then p_s6                                                                                                                                                                                    
when i = 7 then p_s7                                                                                                                                                                                    
when i = 8 then p_s8                                                                                                                                                                                    
when i = 9 then p_s9                                                                                                                                                                                    
when i = 10 then p_s10                                                                                                                                                                                  
else null                                                                                                                                                                                               
end,                                                                                                                                                                                                    
1,0,'c');                                                                                                                                                                                               
end loop;                                                                                                                                                                                               
-- Replace any occurences of %s with p_s<n> (in order) and escape %% to %                                                                                                                               
l_return := sys.utl_lms.format_message(l_return,p_s1, p_s2, p_s3, p_s4, p_s5, p_s6, p_s7, p_s8, p_s9, p_s10);                                                                                           
return l_return;                                                                                                                                                                                        
end sprintf;                                                                                                                                                                                            
/**                                                                                                                                                                                                     
* Returns the rec_logger_logs for given logger_level                                                                                                                                                    
* Used for plugin.                                                                                                                                                                                      
* Not meant to be called by general public, and thus not documented                                                                                                                                     
*                                                                                                                                                                                                       
* Notes:                                                                                                                                                                                                
*  - -- FUTURE mdsouza: Add tests for this (#86)                                                                                                                                                        
*                                                                                                                                                                                                       
* Related Tickets:                                                                                                                                                                                      
*  - #46                                                                                                                                                                                                
*                                                                                                                                                                                                       
* @author Martin D'Souza                                                                                                                                                                                
* @created 11-Mar-2015                                                                                                                                                                                  
* @param p_logger_level Logger level of plugin wanted to return                                                                                                                                         
* @return Logger rec based on plugin type                                                                                                                                                               
*/                                                                                                                                                                                                      
function get_plugin_rec(                                                                                                                                                                                
p_logger_level in logger_logs.logger_level%type)                                                                                                                                                        
return logger.rec_logger_log                                                                                                                                                                            
as                                                                                                                                                                                                      
begin                                                                                                                                                                                                   
if p_logger_level = logger.g_error then                                                                                                                                                                 
return g_plug_logger_log_error;                                                                                                                                                                         
end if;                                                                                                                                                                                                 
end get_plugin_rec;                                                                                                                                                                                     
end logger;                                                                                                                                                                                             
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
