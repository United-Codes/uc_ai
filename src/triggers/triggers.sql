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
