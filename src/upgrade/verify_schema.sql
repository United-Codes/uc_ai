-- ============================================================================
-- UC AI schema verification (last phase of upgrade_uc_ai.sql)
-- ============================================================================
-- Checks that every table, column, sequence, index and named constraint of a
-- fresh install exists. It catches a DDL change in src/tables/install.sql that
-- has no guarded step in upgrade_schema.sql, and a schema that a step could not
-- bring into shape. It lists every missing object and then raises an error.
--
-- generate_upgrade_script.sh replaces the marker line in the list below with
-- the objects of install.sql (scripts/list_install_objects.awk).

-- @dblinter ignore(G-5010): an installer script runs before uc_ai_logger exists and reports to the person running it
declare
  l_expected sys.odcivarchar2list := sys.odcivarchar2list(
    -- @EXPECTED_OBJECTS@
  );
  l_missing  pls_integer := 0;
begin
  <<missing_objects>>
  for r in (
    select e.column_value as item
      from table(l_expected) e
    minus
    select d.item
      from (
        select 'TABLE|' || table_name as item from user_tables
        union all
        select 'COLUMN|' || table_name || '.' || column_name from user_tab_columns
        union all
        select 'SEQUENCE|' || sequence_name from user_sequences
        union all
        select 'INDEX|' || index_name from user_indexes
        union all
        select 'CONSTRAINT|' || constraint_name from user_constraints
      ) d
     order by item
  )
  loop
    sys.dbms_output.put_line('WARNING missing ' || lower(replace(r.item, '|', ' ')));
    l_missing := l_missing + 1;
  end loop missing_objects;

  if l_missing > 0 then
    raise_application_error(
      -20000,
      l_missing || ' object(s) of a fresh install are missing. See the WARNING lines above.'
    );
  end if;

  sys.dbms_output.put_line('Verified: the schema has every object of a fresh install ('
    || l_expected.count || ' checked).');
end;
/
