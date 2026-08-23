create or replace trigger uc_ai_tools_biu
    before insert or update on uc_ai_tools
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_tools_biu;
/

create or replace trigger uc_ai_tool_parameters_biu
    before insert or update on uc_ai_tool_parameters
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_tool_parameters_biu;
/

create or replace trigger uc_ai_tool_tags_biu
    before insert or update on uc_ai_tool_tags
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_tool_tags_biu;
/

create or replace trigger uc_ai_prompt_profiles_biu
    before insert or update on uc_ai_prompt_profiles
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_prompt_profiles_biu;
/

create or replace trigger uc_ai_agents_biu
    before insert or update on uc_ai_agents
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_agents_biu;
/

create or replace trigger uc_ai_agent_executions_biu
    before insert or update on uc_ai_agent_executions
    for each row
begin
    if inserting
    then
        :new.started_at := systimestamp;

        -- fallbacks for inserts outside the API; API-captured values win
        if :new.created_by is null
        then
            :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
        end if;

        if :new.db_user is null
        then
            :new.db_user := user;
        end if;
    end if;

    -- audit every state change (checkpoint, completion, failure)
    :new.updated_at := systimestamp;
end uc_ai_agent_executions_biu;
/

create or replace trigger uc_ai_agent_sessions_biu
    before insert or update on uc_ai_agent_sessions
    for each row
begin
    if inserting
    then
        if :new.started_at is null
        then
            :new.started_at := systimestamp;
        end if;

        if :new.created_by is null
        then
            :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
        end if;
    end if;

    :new.updated_at := systimestamp;
end uc_ai_agent_sessions_biu;
/

create or replace trigger uc_ai_agent_messages_bi
    before insert on uc_ai_agent_messages
    for each row
begin
    if :new.created_at is null
    then
        :new.created_at := systimestamp;
    end if;
end uc_ai_agent_messages_bi;
/

-- uc_ai_memory already sets updated_by/updated_at on its own write paths, using
-- the identical expression (see current_user_id); these triggers are the backstop
-- for a hand-edited row, the same as the triggers above on tables the API also
-- writes.
--
-- uc_ai_memory_files is DELIBERATELY EXCLUDED. It has a touch-only read path that
-- sets last_accessed_at WITHOUT updated_at, so that "last modified" and "last
-- read" stay distinct (expire_files relies on both via
-- greatest(last_accessed_at, updated_at)). A before-update trigger would bump
-- updated_at on every file read and collapse that distinction, turning
-- "last modified" into "last accessed". Its write paths already maintain the
-- audit columns themselves.

create or replace trigger uc_ai_memory_stores_biu
    before insert or update on uc_ai_memory_stores
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_memory_stores_biu;
/

create or replace trigger uc_ai_memory_config_biu
    before insert or update on uc_ai_memory_config
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_memory_config_biu;
/
