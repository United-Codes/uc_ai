-- ============================================================================
-- UC AI reporting views
-- ============================================================================
-- Installed after the tables, and refreshed by upgrade_packages.sql: a view is
-- code, so a changed definition ships with a package upgrade.

-- Every memory file with its store context: what is stored where, how big it
-- is and when it was last useful — for dashboards and housekeeping decisions.
create or replace view uc_ai_v_memory_files as
select s.store_key,
       s.scope,
       s.agent_code,
       s.username,
       s.session_id,
       s.store_code,
       f.path,
       sys.dbms_lob.getlength(f.content) as char_count,
       f.created_at,
       f.updated_at,
       f.last_accessed_at,
       f.store_id,
       f.id as file_id
  from uc_ai_memory_files f
  join uc_ai_memory_stores s
    on s.id = f.store_id;

comment on table uc_ai_v_memory_files is 'Memory files joined with their store (virtual filesystem) context';
