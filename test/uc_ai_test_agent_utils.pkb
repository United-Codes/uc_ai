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
  gc_better_model  constant varchar2(50 char) := uc_ai_openai.c_model_gpt_5_mini;

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

    -- ===== TRAVEL ORCHESTRATION AGENT PROFILES =====
    
    -- Travel Agent Orchestrator Profile
    delete from uc_ai_prompt_profiles 
     where code = 'travel_agent_orchestrator';

    l_schema := '{
      "type": "object",
      "properties": {
        "recommended_plan": {
          "type": "string",
          "description": "The complete recommended travel plan"
        },
        "score": {
          "type": "number",
          "minimum": 0,
          "maximum": 100,
          "description": "Overall plan quality score from 0 to 100"
        },
        "score_breakdown": {
          "type": "object",
          "properties": {
            "scheduling": {
              "type": "number",
              "description": "Score for meeting scheduling constraints (0-100)"
            },
            "budget": {
              "type": "number",
              "description": "Score for staying within budget (0-100)"
            },
            "preferences": {
              "type": "number",
              "description": "Score for matching user preferences (0-100)"
            }
          }
        },
        "concerns": {
          "type": "array",
          "items": {"type": "string"},
          "description": "List of any scheduling, budget, or preference issues"
        }
      },
      "required": ["recommended_plan", "score", "score_breakdown"]
    }';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => 'travel_agent_orchestrator',
      p_description           => 'Orchestrates travel planning by delegating to specialist agents',
      p_system_prompt_template => 'You are a travel planning orchestrator. Your role is to coordinate between calendar, flight booking, hotel booking, and finance agents to plan business trips.

Analyze the user''s request and determine which agents need to be consulted. Consider:
- Calendar constraints (check calendar_agent for meeting schedules)
- Flight options (query flight_booking_agent for available flights)
- Hotel accommodations (query hotel_booking_agent for lodging options)
- Budget approval (consult finance_agent to verify costs are within budget)

First anlyze the user''s prompt, plan the delegation to each agent, and gather their responses. Don''t call all agents at the same time. As final decision consult the budget agent.
Call each agent with a prompt that includes relevant context for them from the current trip planning. {"prompt": "..."}.

After gathering information from the delegate agents, synthesize a comprehensive travel recommendation and evaluate it across three dimensions:
1. SCHEDULING (0-100): Does the plan respect all calendar constraints? Are timing/connections reasonable?
2. BUDGET (0-100): Is the plan within budget? How efficiently does it use resources?
3. PREFERENCES (0-100): Does it meet user preferences for comfort, convenience, and quality?

Calculate an overall score (average of three dimensions) and provide a complete recommendation. Identify any concerns or trade-offs.

Return your analysis as a JSON object with the recommended plan, overall score, score breakdown, and any concerns.',
      p_user_prompt_template  => 'Plan this business trip: {prompt}. 
        The user prefers hotels close to meeting venues. Favorite hotel chains: Marriott, Hilton, Hyatt. 
        Flight preferences: Aisle seat, direct flights only, budget economy class unless business justified. Favorite airlines: American, Delta, United.',
      p_provider              => gc_main_provider,
      p_model                 => gc_better_model,
      p_response_schema       => l_schema,
      p_status                => 'active'
    );

    -- Calendar Agent Profile
    delete from uc_ai_prompt_profiles 
     where code = 'calendar_agent_profile';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => 'calendar_agent_profile',
      p_description           => 'Provides calendar information and scheduling constraints',
      p_system_prompt_template => 'You are a calendar assistant with access to the following schedule data:

MONDAY 12.01.2026:
- 8:00 AM - 11:00 AM: Executive Board Meeting (New York Office, cannot be rescheduled)
- 1:00 PM - 2:00 PM: Lunch with Product Team
- 3:00 PM - 4:30 PM: Optional: Weekly Sync

TUESDAY 13.01.2026:
- 9:00 AM - 12:00 PM: Must attend Tech Conference (San Francisco)
- Free afternoon

WEDNESDAY 14.01.2026:
- Free all day

THURSDAY 15.01.2026:
- Free until 3:00 PM
- 3:00 PM - 5:00 PM: Client Call (remote, mandatory)

When asked about availability, provide specific time constraints and note which meetings are mandatory vs. optional. The user is currently in New York and needs approximately 6 hours for cross-country travel to San Francisco.

Answer shortly (no chatting) and precisely based on the above data.',
      p_user_prompt_template  => 'Calendar query: {prompt}',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    -- Flight Booking Agent Profile
    delete from uc_ai_prompt_profiles 
     where code = 'flight_booking_agent_profile';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => 'flight_booking_agent_profile',
      p_description           => 'Provides flight options based on static data',
      p_system_prompt_template => 'You are a flight booking specialist with access to the following flight options from New York (JFK) to San Francisco (SFO).

FLIGHT OPTIONS everyday (Monday to Friday):
1. Flight AA123 - Departs 12:00 PM, Arrives 3:00 PM PT
   - Price: $450
   - Class: Economy
   - Direct flight
   - Seat: Window available
   - Airline: American Airlines

2. Flight UA456 - Departs 2:00 PM, Arrives 5:00 PM PT
   - Price: $385
   - Class: Economy
   - Direct flight
   - Seat: Aisle available
   - Airline: United Airlines

3. Flight DL789 - Departs 5:00 PM, Arrives 8:00 PM PT
   - Price: $520
   - Class: Business
   - Direct flight
   - Extra legroom, complimentary meal
   - Airline: Mexican Delta

4. Flight B6999 - Departs 7:00 PM, Arrives 10:00 PM PT
   - Price: $340
   - Class: Economy
   - Direct flight
   - Red-eye discount
   - Airline: Budget Air

Return flights happen 2 hours later same day.

Return the three best flight options based on user preferences and constraints provided in the prompt. Consider price, timing, and seat preferences.
Only return the flight options, no additional text.',
      p_user_prompt_template  => 'Flight search: {prompt}',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    -- Hotel Booking Agent Profile
    delete from uc_ai_prompt_profiles 
     where code = 'hotel_booking_agent_profile';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => 'hotel_booking_agent_profile',
      p_description           => 'Provides hotel accommodation options',
      p_system_prompt_template => 'You are a hotel booking specialist with access to the following hotel options near the Tech Conference venue in San Francisco:

HOTEL OPTIONS (per night) - still rooms available in Monday 12.01.2026 - Friday 16.01.2026:
1. Grand Hyatt San Francisco
   - Distance: 0.2 miles from conference venue (2 min walk)
   - Price: $320/night
   - Amenities: Free WiFi, Gym, Business center, Restaurant
   - Rating: 4.5/5 stars
   - Notes: Most convenient location

2. Holiday Inn Downtown
   - Distance: 0.8 miles from conference venue (10 min walk)
   - Price: $180/night
   - Amenities: Free WiFi, Breakfast included, Gym
   - Rating: 3.8/5 stars
   - Notes: Budget-friendly option

3. Marriott Marquis
   - Distance: 0.5 miles from conference venue (6 min walk)
   - Price: $280/night
   - Amenities: Free WiFi, Pool, Spa, Multiple restaurants
   - Rating: 4.3/5 stars
   - Notes: Good balance of price and location

4. Airport Hotel Express
   - Distance: 15 miles from conference venue (30 min drive)
   - Price: $120/night
   - Amenities: Free airport shuttle, WiFi, Parking
   - Rating: 3.5/5 stars
   - Notes: Cheapest option but requires transportation

Return the three best hotel options based on user preferences and constraints provided in the prompt. Consider price, location, and amenities.
Only return the hotel options, no additional text.',
      p_user_prompt_template  => 'Hotel search: {prompt}',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    -- Finance Agent Profile
    delete from uc_ai_prompt_profiles 
     where code = 'finance_agent_profile';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => 'finance_agent_profile',
      p_description           => 'Reviews travel costs against budget constraints',
      p_system_prompt_template => 'You are a corporate finance controller responsible for approving business travel expenses. Your budget guidelines are:

TRAVEL BUDGET POLICY:
- Total trip budget: $1,200 per person
- Flight budget: Maximum $500
- Hotel budget: Maximum $300/night
- Daily meals: $75/day allowance
- Ground transportation: $100 total

APPROVAL RULES:
- Under budget: Approved immediately
- 1-10% over budget: Requires justification
- 11-20% over budget: Needs VP approval
- Over 20%: Denied, must find alternatives

When reviewing travel costs, calculate the total expense and compare against the $1,200 budget. Consider:
- Flight cost
- Hotel cost × number of nights
- Meals (automatic $75/day allocation)
- Transportation estimates

Provide a clear approval status: APPROVED, REQUIRES_JUSTIFICATION, NEEDS_VP_APPROVAL, or DENIED. Include the total cost breakdown and percentage of budget used.',
      p_user_prompt_template  => 'Review these travel expenses: {prompt}. Your role: {role}.',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    -- Party planning agent profils

    -- party brainstormer
    delete from uc_ai_prompt_profiles 
     where code = 'party_brainstormer_profile';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => 'party_brainstormer_profile',
      p_description           => 'Generate wild, fun ideas without worrying about cost yet.',
      p_system_prompt_template => 'You are Brainstormer. Propose 2-3 creative, exciting party ideas/activities based on the task and chat history.
Be enthusiastic! Ignore budget/cost for now.
Structure: "Idea 1: [desc]. Idea 2: [desc]. What do you think?"
Speak only when selected. Reference recent messages.',
      p_user_prompt_template  => 'Generate or refine party ideas: {prompt}. Your role: {role}.',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    -- party critic
    delete from uc_ai_prompt_profiles 
     where code = 'party_critic_profile';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => 'party_critic_profile',
      p_description           => 'Poke holes in ideas, focus on budget, safety, feasibility.',
      p_system_prompt_template => 'You are Critic. Analyze previous ideas harshly: Check budget, safety for kids 8-10, backyard limits.
Suggest fixes or kills bad ideas.
Structure: "Critique: [idea] is [good/bad because...]. Fix: [suggestion]. Next?"
Be realistic and picky. Reference history.',
      p_user_prompt_template  => 'Chat history: {prompt}. Your role: {role}.',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    -- party synthesizer
    delete from uc_ai_prompt_profiles 
     where code = 'party_synthesizer_profile';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => 'party_synthesizer_profile',
      p_description           => 'Combine best ideas into a cohesive plan, check consensus, propose final.',
      p_system_prompt_template => 'You are Synthesizer. Merge good ideas from history into 1 polished plan.
Estimate total cost. Check if ready to end.
Structure: "Combined Plan: 1. [activity] ($X). 2. [food] ($Y). Total: $Z. Agree?"
Only finalize if budget ok and no major critiques left. If you finalize, say "Final Plan: ..."',
      p_user_prompt_template  => 'Chat history: {prompt}',
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
