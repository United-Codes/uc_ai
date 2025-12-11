create sequence uc_ai_tools_seq;

create table uc_ai_tools(
  id                   number default on null uc_ai_tools_seq.nextval not null,
  code                 varchar2(255 char)  not null,
  description          varchar2(4000 char) not null,
  active               number(1) default on null 1 not null,
  response_schema      clob,
  version              varchar2(50 char) default on null '1.0' not null,
  function_call        clob not null,
  authorization_schema varchar2(255 char),
  created_by           varchar2(255 char) not null,
  created_at           timestamp not null,
  updated_by           varchar2(255 char) not null,
  updated_at           timestamp not null,
  constraint uc_ai_tools_pk primary key (id),
  constraint uc_ai_tools_uk unique (code),
  constraint uc_ai_tools_active_ck check (active in (0,1))
);  

create sequence uc_ai_tool_parameters_seq;

create table uc_ai_tool_parameters(
  id                  number default on null uc_ai_tool_parameters_seq.nextval not null,
  tool_id             number not null,
  name                varchar2(255 char)  not null,
  description         varchar2(4000 char) not null,
  required            number(1) default on null 1 not null,
  data_type           varchar2(255 char) not null,
  min_num_val         number,
  max_num_val         number,
  enum_values         varchar2(4000 char),                -- For parameters with enumerated values, : seperated
  default_value       varchar2(4000 char),                -- Default value for the parameter
  is_array            number(1) default on null 0 not null,  -- Specify if the data_type is expected as an array (e. g. number -> number[])
  array_min_items     number,                        -- Minimum number of items in array
  array_max_items     number,                        -- Maximum number of items in array
  pattern             varchar2(4000 char),                -- Regex pattern for string validation
  format              varchar2(255 char),                 -- Format specifier (e.g., date-time, email)
  min_length          number,                        -- For string parameters
  max_length          number,                        -- For string parameters
  parent_param_id     number,                        -- For nested parameters
  created_by          varchar2(255 char) not null,
  created_at          timestamp not null,
  updated_by          varchar2(255 char) not null,
  updated_at          timestamp not null,
  constraint uc_ai_tool_parameters_pk primary key (id),
  constraint uc_ai_tool_parameters_uk unique (tool_id, name)
);

alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_required_ck check (required in (0,1));

alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_tool_id_fk foreign key (tool_id) references uc_ai_tools(id) on delete cascade;

alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_data_type_ck check (
    data_type in ('string', 'number', 'integer', 'boolean', 'object')
  );

  -- For number/integer type: only min_num_val and max_num_val should be filled
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_number_cols_ck check (
      (data_type in ('number', 'integer') and 
      (min_length is null and max_length is null and pattern is null)) 
      or 
      (data_type not in ('number', 'integer'))
  );

  -- For string type: only min_length, max_length, pattern, and format should be filled
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_string_cols_ck check (
      (data_type = 'string' and 
      (min_num_val is null and max_num_val is null)) 
      or 
      (data_type != 'string')
  );

  -- For boolean type: most validation fields should be null
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_boolean_cols_ck check (
      (data_type = 'boolean' and 
      (min_num_val is null and max_num_val is null and 
        min_length is null and max_length is null and 
        pattern is null and format is null)) 
      or 
      (data_type != 'boolean')
  );

  -- For array type: ensure array flags are properly set
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_array_cols_ck check (
      (data_type = 'array' and is_array = 1) 
      or 
      (data_type != 'array')
  );

  -- Ensure array properties are only set when is_array = 1
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_array_props_ck check (
      (is_array = 1) 
      or 
      (is_array = 0 and array_min_items is null and array_max_items is null)
  );

  -- For enum values: ensure they're only used with appropriate types
alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_enum_ck check (
      (enum_values is not null and data_type in ('string', 'number', 'integer')) 
      or 
      (enum_values is null)
  );

alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_parent_param_id_fk foreign key (parent_param_id) references uc_ai_tool_parameters(id) on delete cascade
;  


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


create sequence uc_ai_prompt_profiles_seq;

create table uc_ai_prompt_profiles (
  id                     number default on null uc_ai_prompt_profiles_seq.nextval not null,
  code                   varchar2(255 char)  not null,
  version                number default on null 1 not null,
  status                 varchar2(50 char) default on null 'draft' not null,
  description            varchar2(4000 char) not null,

  system_prompt_template clob not null,
  user_prompt_template   clob not null,
  provider               varchar2(512 char) not null,
  model                  varchar2(512 char) not null,
  model_config_json      clob,
  response_schema        clob,
  parameters_schema      clob,

  created_by             varchar2(255 char) not null,
  created_at             timestamp not null,
  updated_by             varchar2(255 char) not null,
  updated_at             timestamp not null,
  constraint uc_ai_prompt_profiles_pk primary key (id),
  constraint uc_ai_prompt_profiles_uk unique (code, version),
  constraint uc_ai_prompt_profiles_status_ck check (status in ('draft', 'active', 'archived'))
);
