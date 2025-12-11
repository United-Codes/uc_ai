create or replace package test_uc_ai_prompt_profiles_api as

  --%suite(Prompt Profiles API tests)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%test(Create prompt profile - basic)
  procedure create_basic_profile;

  --%test(Create prompt profile with config)
  procedure create_profile_with_config;

  --%test(Update prompt profile by ID)
  procedure update_profile_by_id;

  --%test(Update prompt profile by code and version)
  procedure update_profile_by_code;

  --%test(Delete prompt profile by ID)
  procedure delete_profile_by_id;

  --%test(Delete prompt profile by code and version)
  procedure delete_profile_by_code;

  --%test(Change status)
  procedure change_profile_status;

  --%test(Create new version)
  procedure create_new_profile_version;

  --%test(Get prompt profile by ID)
  procedure get_profile_by_id;

  --%test(Get prompt profile by code - latest active)
  procedure get_profile_latest_active;

  --%test(Execute profile - simple text generation)
  procedure execute_simple_profile;

  --%test(Execute profile - with placeholders)
  procedure execute_profile_with_placeholders;

  --%test(Execute profile - with model config)
  procedure execute_profile_with_config;

  --%test(Execute profile - with structured output)
  procedure execute_profile_structured_output;

  --%test(Execute profile - with provider override)
  procedure execute_profile_with_override;

  --%test(Execute profile - tool usage)
  procedure execute_profile_with_tools;

end test_uc_ai_prompt_profiles_api;
/
