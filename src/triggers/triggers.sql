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


create or replace trigger uc_ai_categories_biu
    before insert or update on uc_ai_categories
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_categories_biu;

create or replace trigger uc_ai_tool_categories_biu
    before insert or update on uc_ai_tool_categories
    for each row
begin
    if inserting
    then
        :new.created_at := systimestamp;
        :new.created_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
    end if;

    :new.updated_at := systimestamp;
    :new.updated_by := coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
end uc_ai_tool_categories_biu;
