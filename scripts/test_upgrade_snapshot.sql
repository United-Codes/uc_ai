-- Dictionary snapshot of the UC AI schema objects, one sorted-friendly line per
-- fact. scripts/test_upgrade.sh compares the snapshot of an upgraded schema with
-- the snapshot of a fresh install.
--
-- Left out on purpose: column order (an added column always lands last),
-- constraint validation state (the upgrade creates some checks ENABLE
-- NOVALIDATE), and system-generated names (constraints, LOB indexes and the
-- hidden columns of function-based indexes).

set pagesize 0
set feedback off
set heading off
set linesize 4000
set long 4000
set trimspool on
set verify off
set termout on

select 'COLUMN|' || c.table_name || '.' || c.column_name || '|' || c.data_type
       || '|' || c.data_length || '|' || c.char_length || '|' || c.data_precision
       || '|' || c.data_scale || '|' || c.nullable || '|' || c.default_on_null
       || '|' || c.virtual_column
  from user_tab_cols c
  join user_tables t on t.table_name = c.table_name
 where c.table_name like 'UC\_AI%' escape '\'
   and c.hidden_column = 'NO';

-- The default expression is a LONG, so it can only be selected on its own.
select 'DEFAULT|' || c.table_name || '.' || c.column_name || '|' || c.data_default
  from user_tab_columns c
 where c.table_name like 'UC\_AI%' escape '\'
   and c.data_default is not null;

select 'CONSTRAINT|' || case when c.constraint_name like 'SYS\_%' escape '\' then 'SYSTEM' else c.constraint_name end
       || '|' || c.table_name || '|' || c.constraint_type
       || '|' || regexp_replace(c.search_condition_vc, '[[:space:]]+', ' ')
       || '|' || c.status || '|' || c.delete_rule || '|' || c.r_constraint_name
  from user_constraints c
 where c.table_name like 'UC\_AI%' escape '\'
   and c.constraint_type in ('P', 'U', 'R', 'C');

select 'CONSTRAINT_COLUMNS|' || cc.constraint_name || '|'
       || listagg(cc.column_name, ',') within group (order by cc.position)
  from user_cons_columns cc
  join user_constraints c on c.constraint_name = cc.constraint_name
 where c.table_name like 'UC\_AI%' escape '\'
   and c.constraint_type in ('P', 'U', 'R')
 group by cc.constraint_name;

select 'INDEX|' || i.index_name || '|' || i.table_name || '|' || i.uniqueness
       || '|' || i.index_type || '|'
       || (select listagg(regexp_replace(ic.column_name, '^SYS_NC[0-9]+\$$', 'EXPRESSION'), ',')
                  within group (order by ic.column_position)
             from user_ind_columns ic
            where ic.index_name = i.index_name)
  from user_indexes i
 where i.table_name like 'UC\_AI%' escape '\'
   and i.index_type <> 'LOB';

select 'SEQUENCE|' || sequence_name || '|' || increment_by || '|' || min_value
  from user_sequences
 where sequence_name like 'UC\_AI%' escape '\';

select 'TRIGGER|' || trigger_name || '|' || table_name || '|' || trigger_type
       || '|' || triggering_event || '|' || status
  from user_triggers
 where trigger_name like 'UC\_AI%' escape '\';

select 'VIEW|' || view_name
  from user_views
 where view_name like 'UC\_AI%' escape '\';

select 'OBJECT|' || object_type || '|' || object_name || '|' || status
  from user_objects
 where object_name like 'UC\_AI%' escape '\'
   and object_type in ('PACKAGE', 'PACKAGE BODY', 'FUNCTION', 'VIEW', 'TRIGGER');

select 'TABLE_COMMENT|' || table_name || '|' || comments
  from user_tab_comments
 where table_name like 'UC\_AI%' escape '\'
   and comments is not null;

select 'COLUMN_COMMENT|' || table_name || '.' || column_name || '|' || comments
  from user_col_comments
 where table_name like 'UC\_AI%' escape '\'
   and comments is not null;

exit
