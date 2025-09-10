alter table uc_ai_tool_parameters drop constraint uc_ai_tool_parameters_array_props_ck;

alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_array_props_ck check (
      (is_array = 1) 
      or 
      (is_array = 0 and array_min_items is null and array_max_items is null)
  );

drop sequence uc_ai_tool_categories_seq;
drop table uc_ai_tool_categories;

drop sequence uc_ai_categories_seq;
drop table uc_ai_categories;

create sequence uc_ai_tool_tags_seq;

create table uc_ai_tool_tags(
  id                   number default on null uc_ai_tool_tags_seq.nextval not null,
  tool_id              number not null,
  tag_name             varchar2(255 char) not null,
  created_by           varchar2(255 char) not null,
  created_at           timestamp not null,
  updated_by           varchar2(255 char) not null,
  updated_at           timestamp not null,
  constraint uc_ai_tool_tags_pk primary key (id),
  constraint uc_ai_tool_tags_uk unique (tool_id, tag_name),
  constraint uc_ai_tool_tags_tool_id_fk foreign key (tool_id) references uc_ai_tools(id) on delete cascade,
  constraint uc_ai_tool_tags_tag_lower_ck check (tag_name = lower(tag_name))
);

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
