create or replace package body uc_ai_test_agent_utils as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): allow special others handling in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages

  gc_math_profile_code       constant varchar2(50 char) := 'TEST_AGENT_MATH';
  gc_geography_profile_code  constant varchar2(50 char) := 'TEST_AGENT_GEO';
  gc_summarizer_profile_code constant varchar2(50 char) := 'TEST_AGENT_SUM';
  gc_haiku_creator_profile_code constant varchar2(50 char) := 'TEST_AGENT_HAIKU_CREATOR';
  gc_haiku_rater_profile_code constant varchar2(50 char) := 'TEST_AGENT_HAIKU_RATER';
  gc_haiku_improver_profile_code constant varchar2(50 char) := 'TEST_AGENT_HAIKU_IMPROVER';

  gc_main_provider constant varchar2(50 char) := uc_ai.c_provider_openai;
  gc_main_model    constant varchar2(50 char) := uc_ai_openai.c_model_gpt_4o_mini;

  -- gc_main_provider constant varchar2(50 char) := uc_ai.c_provider_google;
  -- gc_main_model    constant varchar2(50 char) := uc_ai_google.c_model_gemini_2_5_flash;

  procedure create_math_profile
  as
    l_id number;
  begin
    -- Delete existing profile if it exists
    delete from uc_ai_prompt_profiles 
     where code = gc_math_profile_code;

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => gc_math_profile_code,
      p_description           => 'Simple math helper for agent testing',
      p_system_prompt_template => 'You are a math assistant. Respond with only the numeric answer.',
      p_user_prompt_template  => 'Calculate: {question}',
      p_provider              => gc_main_provider, 
      p_model                 => gc_main_model,
      p_status                => 'active'
    );
  end create_math_profile;

  procedure create_profiles
  as
    l_id number;
    l_schema clob;
  begin
    -- Delete existing profile if it exists
    delete from uc_ai_prompt_profiles 
     where code = gc_geography_profile_code;

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => gc_geography_profile_code,
      p_description           => 'Geography helper for agent testing',
      p_system_prompt_template => 'You are a geography assistant. Answer in one short sentence.',
      p_user_prompt_template  => '{question}',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    delete from uc_ai_prompt_profiles 
     where code = gc_summarizer_profile_code;

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => gc_summarizer_profile_code,
      p_description           => 'Text summarizer for agent testing',
      p_system_prompt_template => 'Summarize the given text in one sentence.',
      p_user_prompt_template  => 'Summarize: {text}',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    -- Delete existing profile if it exists
    delete from uc_ai_prompt_profiles 
     where code = gc_haiku_creator_profile_code;

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => gc_haiku_creator_profile_code,
      p_description           => 'Creates haikus about given topics',
      p_system_prompt_template => 'You are a haiku poet. Create one beautiful haiku following the traditional 5-7-5 syllable pattern.',
      p_user_prompt_template  => 'Write a haiku about: {topic}.',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );
    -- Delete existing profile if it exists
    delete from uc_ai_prompt_profiles 
     where code = gc_haiku_improver_profile_code;

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => gc_haiku_improver_profile_code,
      p_description           => 'Creates haikus about given topics',
      p_system_prompt_template => 'You are a haiku improver.',
      p_user_prompt_template  => 'Improve this haiku about "{topic}" using this feedback: {feedback}. Haiku: {haiku}',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    -- Delete existing profile if it exists
    delete from uc_ai_prompt_profiles 
     where code = gc_haiku_rater_profile_code;

    l_schema := '{
      "type": "object",
      "properties": {
        "quality": {
          "type": "number",
          "minimum": 1,
          "maximum": 10,
          "description": "Quality rating from 1 to 10"
        },
        "feedback": {
          "type": "string",
          "description": "One sentence providing constructive feedback"
        }
      },
      "required": ["quality", "feedback"]
    }';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => gc_haiku_rater_profile_code,
      p_description           => 'Rates haikus with structured output',
      p_system_prompt_template => 'You are a haiku critic. Rate haikus based on their adherence to traditional form, imagery, and emotional impact. Only respond with a JSON object containing a quality rating from 1 to 10 and a one-sentence feedback for the rating.',
      p_user_prompt_template  => 'Rate this haiku about "{topic}": {haiku}',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_response_schema       => l_schema,
      p_status                => 'active'
    );

    delete from uc_ai_prompt_profiles 
     where code = 'TEST_AGENT_HAIKU_TRANSLATOR';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => 'TEST_AGENT_HAIKU_TRANSLATOR',
      p_description           => 'Translates haikus to different languages',
      p_system_prompt_template => 'You are a haiku translator. Translate haikus to the specified language while preserving the traditional 5-7-5 syllable pattern.',
      p_user_prompt_template  => 'Translate this haiku to {language}: {haiku}',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );
    -- Delete test executions first (FK constraint)
    delete from uc_ai_agent_executions 
     where agent_id in (
       select a.id from uc_ai_agents a where code like 'TEST_%'
     );
    
  end create_profiles;

  procedure cleanup_test_data
  as
  begin
    -- Delete test agents
    delete from uc_ai_agents where code like 'TEST_%';
    
    -- Delete test profiles
    delete from uc_ai_prompt_profiles where code like 'TEST_AGENT_%';
  end cleanup_test_data;

  procedure validate_agent_result(
    p_result    in json_object_t,
    p_test_name in varchar2
  )
  as
  begin
    ut.expect(
      p_result,
      p_test_name || ': Result should not be null'
    ).to_be_not_null();

    ut.expect(
      p_result.has('final_message'),
      p_test_name || ': Result should have final_message'
    ).to_be_true();

    ut.expect(
      p_result.has('execution_id'),
      p_test_name || ': Result should have execution_id'
    ).to_be_true();

    ut.expect(
      p_result.has('status'),
      p_test_name || ': Result should have status'
    ).to_be_true();
  end validate_agent_result;

  procedure validate_execution_recorded(
    p_session_id in varchar2,
    p_test_name  in varchar2
  )
  as
    l_count number;
  begin
    select count(*) 
      into l_count
      from uc_ai_agent_executions 
     where session_id = p_session_id;

    ut.expect(
      l_count,
      p_test_name || ': Should have recorded execution'
    ).to_be_greater_than(0);
  end validate_execution_recorded;

end uc_ai_test_agent_utils;
/
