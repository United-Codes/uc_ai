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

  gc_calc_tool_code constant varchar2(50 char) := 'TEST_CALC_TOOL';
  gc_calc_tool_tag  constant varchar2(50 char) := 'test_calculator';

  gc_product_tool_code constant varchar2(50 char) := 'TEST_PRODUCT_TOOL';
  gc_product_tool_tag  constant varchar2(50 char) := 'test_product_details';

  procedure create_math_profile
  as
    l_id      number;
    l_tool_id number;
    l_schema  json_object_t;
  begin
    -- Create the calculator function via execute immediate
    execute immediate q'!
      create or replace function test_demo_calculate(
        p_arguments in json_object_t
      ) return clob
      as
        l_expression varchar2(4000 char);
        l_result     number;
      begin
        l_expression := p_arguments.get_string('expression');

        if l_expression is null then
          return 'Error: no expression provided.';
        end if;

        if regexp_like(l_expression, '[^0-9+*/()., ROUNDCEILFLOORMODABS' || chr(10) || chr(13) || chr(9) || '-]', 'i') then
          return 'Error: expression contains disallowed characters.';
        end if;

        execute immediate 'select ' || l_expression || ' from dual' into l_result;

        return 'Result: ' || to_char(l_result);
      exception
        when others then
          return 'Error evaluating expression: ' || sqlerrm;
      end test_demo_calculate;
    !';

    -- Register the calculator tool
    l_schema := json_object_t('{
      "type": "object",
      "properties": {
        "expression": {
          "type": "string",
          "description": "A SQL-compatible math expression, e.g. 2+2 or ROUND(17/3,2)"
        }
      },
      "required": ["expression"]
    }');

    l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code     => gc_calc_tool_code,
      p_description   => 'Evaluates a math expression in the Oracle database. Always use this tool to calculate math.',
      p_function_call => 'return test_demo_calculate(json_object_t(:arguments));',
      p_json_schema   => l_schema,
      p_tags          => apex_t_varchar2(gc_calc_tool_tag)
    );

    -- Delete existing profile if it exists
    delete from uc_ai_prompt_profiles
     where code = gc_math_profile_code;

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => gc_math_profile_code,
      p_description            => 'Math helper with calculator tool for agent testing',
      p_system_prompt_template => 'You are a math assistant. Use the calculator tool to compute math expressions. Respond with only the numeric answer.',
      p_user_prompt_template   => 'Calculate: {question}',
      p_provider               => gc_main_provider,
      p_model                  => gc_better_model,
      p_model_config_json      => '{"g_enable_tools": true, "g_tool_tags": ["' || gc_calc_tool_tag || '"], "g_max_tool_calls": 3}',
      p_status                 => 'active'
    );
  end create_math_profile;

  procedure create_support_profiles
  as
    l_id      number;
    l_tool_id number;
    l_schema  json_object_t;
  begin
    -- Product lookup function: canned catalog data for handoff tests
    execute immediate q'!
      create or replace function test_get_product_details(
        p_arguments in json_object_t
      ) return clob
      as
        l_product varchar2(4000 char);
      begin
        l_product := upper(p_arguments.get_string('product_name'));

        if l_product is null then
          return 'Error: no product_name provided.';
        end if;

        if instr(l_product, 'AURORA') > 0 or instr(l_product, 'LAMP') > 0 then
          return 'Aurora Desk Lamp: weight 2.5 kg, made of recycled aluminum, price $49, in stock.';
        elsif instr(l_product, 'GLX') > 0 or instr(l_product, 'HEADSET') > 0 then
          return 'GLX-7000 Headset: battery life 88 hours, Bluetooth 5.3, price $129, in stock.';
        elsif instr(l_product, 'TRAILMAX') > 0 or instr(l_product, 'BOOT') > 0 then
          return 'TrailMax Hiking Boots: sizes 36-47, waterproof, price $159, ships in 2 weeks.';
        else
          return 'No product found matching "' || p_arguments.get_string('product_name')
            || '". Available products: Aurora Desk Lamp, GLX-7000 Headset, TrailMax Hiking Boots.';
        end if;
      end test_get_product_details;
    !';

    l_schema := json_object_t('{
      "type": "object",
      "properties": {
        "product_name": {
          "type": "string",
          "description": "Name (or part of the name) of the product to look up"
        }
      },
      "required": ["product_name"]
    }');

    l_tool_id := uc_ai_tools_api.merge_tool_from_schema(
      p_tool_code     => gc_product_tool_code,
      p_description   => 'Looks up product details (specs, price, availability) in the shop catalog. Always use this tool for product facts.',
      p_function_call => 'return test_get_product_details(json_object_t(:arguments));',
      p_json_schema   => l_schema,
      p_tags          => apex_t_varchar2(gc_product_tool_tag)
    );

    -- Triage: single point of entry, routes via transfer tools (registered
    -- dynamically by the handoff engine - not part of this profile's config)
    delete from uc_ai_prompt_profiles
     where code = 'TEST_AGENT_CS_TRIAGE';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'TEST_AGENT_CS_TRIAGE',
      p_description            => 'Online shop triage agent for handoff testing',
      p_system_prompt_template => 'You are the triage agent of an online shop''s customer support.
You can transfer the conversation to specialist agents using the available transfer tools.
For any question about products, shipping, or customer accounts/orders you MUST transfer to the matching specialist - never answer such questions yourself, you have no reliable data.
Only greetings and smalltalk you answer yourself, briefly and politely.',
      p_user_prompt_template   => '{prompt}',
      p_provider               => gc_main_provider,
      p_model                  => gc_better_model,
      p_status                 => 'active'
    );

    -- Product details specialist: has its own catalog lookup tool
    delete from uc_ai_prompt_profiles
     where code = 'TEST_AGENT_CS_PRODUCT';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'TEST_AGENT_CS_PRODUCT',
      p_description            => 'Product details specialist for handoff testing',
      p_system_prompt_template => 'You are the product specialist of an online shop. Use the product details tool to look up product facts and answer the customer''s question concisely with the exact numbers from the catalog.
If transfer tools are available and the customer has a technical problem or how-to question about a specific product, you MUST transfer to the matching product technician instead of answering yourself. Transfer at most once - never transfer back to triage for product-related questions.',
      p_user_prompt_template   => 'Customer question: {prompt}
Triage notes: {handoff_context}',
      p_provider               => gc_main_provider,
      p_model                  => gc_better_model,
      p_model_config_json      => '{"g_enable_tools": true, "g_tool_tags": ["' || gc_product_tool_tag || '"], "g_max_tool_calls": 3}',
      p_status                 => 'active'
    );

    -- Product technicians (multi-level handoff targets): each knows one fact
    -- no other agent knows, so tests can prove the routing path
    delete from uc_ai_prompt_profiles
     where code = 'TEST_AGENT_CS_TECH_A';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'TEST_AGENT_CS_TECH_A',
      p_description            => 'Aurora Desk Lamp technician for handoff testing',
      p_system_prompt_template => 'You are the technician for the Aurora Desk Lamp. Technical knowledge:
- Reset: hold the power button for 5 seconds until the light blinks twice
- Flickering: firmly reseat the shade connector
Questions about Aurora Desk Lamp technical issues are YOURS: answer them directly and concisely based only on this knowledge - never transfer them.
Only use a transfer tool if the question is clearly not about the Aurora Desk Lamp.',
      p_user_prompt_template   => 'Customer question: {prompt}
Handoff notes: {handoff_context}',
      p_provider               => gc_main_provider,
      p_model                  => gc_main_model,
      p_status                 => 'active'
    );

    delete from uc_ai_prompt_profiles
     where code = 'TEST_AGENT_CS_TECH_B';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'TEST_AGENT_CS_TECH_B',
      p_description            => 'GLX-7000 Headset technician for handoff testing',
      p_system_prompt_template => 'You are the technician for the GLX-7000 Headset. Technical knowledge:
- Pairing problems: double-tap the left earcup to enter pairing mode
- Audio dropouts: update to firmware 4.2 via the companion app
Questions about GLX-7000 technical issues are YOURS: answer them directly and concisely based only on this knowledge - never transfer them.
Only use a transfer tool if the question is clearly not about the GLX-7000 Headset.',
      p_user_prompt_template   => 'Customer question: {prompt}
Handoff notes: {handoff_context}',
      p_provider               => gc_main_provider,
      p_model                  => gc_main_model,
      p_status                 => 'active'
    );

    -- Return policy specialist (below the shipping specialist)
    delete from uc_ai_prompt_profiles
     where code = 'TEST_AGENT_CS_RETURNS';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'TEST_AGENT_CS_RETURNS',
      p_description            => 'Return policy specialist for handoff testing',
      p_system_prompt_template => 'You are the return policy specialist of an online shop. Policy:
- Returns accepted within a 30-day window after delivery
- Return label fee: $2.50 (waived for premium members)
Questions about returns and refunds are YOURS: answer them directly and concisely with the exact numbers from this policy - never transfer them.
Only use a transfer tool if the question is clearly not about returns.',
      p_user_prompt_template   => 'Customer question: {prompt}
Handoff notes: {handoff_context}',
      p_provider               => gc_main_provider,
      p_model                  => gc_main_model,
      p_status                 => 'active'
    );

    -- Shipping specialist: rules baked into the system prompt
    delete from uc_ai_prompt_profiles
     where code = 'TEST_AGENT_CS_SHIPPING';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'TEST_AGENT_CS_SHIPPING',
      p_description            => 'Shipping specialist for handoff testing',
      p_system_prompt_template => 'You are the shipping specialist of an online shop. Shipping rules:
- Standard shipping: 4 business days, $4.99
- Express shipping: 1 business day, $19.99
- Orders over $100 get free standard shipping
- We ship to the US and the EU only
Answer the customer''s question concisely with the exact numbers from these rules.
If transfer tools are available and the question is about returns, refunds, or the return policy, you MUST transfer to the return policy specialist instead of answering yourself.',
      p_user_prompt_template   => 'Customer question: {prompt}
Triage notes: {handoff_context}',
      p_provider               => gc_main_provider,
      p_model                  => gc_main_model,
      p_status                 => 'active'
    );

    -- Customer details specialist: fake records baked into the system prompt
    delete from uc_ai_prompt_profiles
     where code = 'TEST_AGENT_CS_CUSTOMER';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                   => 'TEST_AGENT_CS_CUSTOMER',
      p_description            => 'Customer details specialist for handoff testing',
      p_system_prompt_template => 'You are the customer account specialist of an online shop. Customer records:
- Customer 1001: Alice Smith, premium member since 2021, open orders: 5001 (GLX-7000 Headset, shipped), 5002 (Aurora Desk Lamp, processing)
- Customer 1002: Bob Jones, standard member since 2023, no open orders
Answer the customer''s question concisely based only on these records.',
      p_user_prompt_template   => 'Customer question: {prompt}
Triage notes: {handoff_context}',
      p_provider               => gc_main_provider,
      p_model                  => gc_main_model,
      p_status                 => 'active'
    );
  end create_support_profiles;

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
      p_user_prompt_template  => 'Chat history: {prompt}. Your role: {role}.',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    -- party moderator
    delete from uc_ai_prompt_profiles 
     where code = 'party_moderator_profile';

    l_id := uc_ai_prompt_profiles_api.create_prompt_profile(
      p_code                  => 'party_moderator_profile',
      p_description           => 'Oversees party planning conversation, delegates who speaks next.',
      p_system_prompt_template => 'You are Moderator. Oversee the party planning conversation. Delegate who speaks next based on chat history.]
      
      If you think there is a solid plan ready, you can finalize the conversation.
      
      If the conversation is done please summarize the conversation for the user.',
      p_user_prompt_template  => '{prompt}',
      p_provider              => gc_main_provider,
      p_model                 => gc_main_model,
      p_status                => 'active'
    );

    -- Delete test messages first (FK to executions), then executions
    -- (FK constraint, includes child executions).
    delete from uc_ai_agent_messages
     where execution_id in (
       select e.id
         from uc_ai_agent_executions e
        start with e.agent_id in (
          select a.id from uc_ai_agents a where a.code like 'TEST_%'
        )
      connect by nocycle prior e.id = e.parent_execution_id
     );

    delete from uc_ai_agent_executions
     where id in (
       select e.id
         from uc_ai_agent_executions e
        start with e.agent_id in (
          select a.id from uc_ai_agents a where a.code like 'TEST_%'
        )
      connect by nocycle prior e.id = e.parent_execution_id
     );

  end create_profiles;

  procedure delete_agents_cascade(
    p_code_pattern in varchar2
  )
  as
  begin
    -- Messages first: they FK to both executions and sessions. Cover messages
    -- of the executions about to be removed and of the sessions about to be
    -- removed (root agent matches the pattern).
    delete from uc_ai_agent_messages
     where execution_id in (
       select e.id
         from uc_ai_agent_executions e
        start with e.agent_id in (
          select a.id from uc_ai_agents a where a.code like p_code_pattern
        )
      connect by nocycle prior e.id = e.parent_execution_id
     )
        or session_id in (
       select s.session_id from uc_ai_agent_sessions s
        where s.root_agent_id in (
          select a.id from uc_ai_agents a where a.code like p_code_pattern
        )
     );

    -- Single statement so the self-referencing parent_execution_id FK is
    -- checked after all hierarchy rows (parents and children) are gone.
    -- The connect by also catches child executions that belong to OTHER
    -- agents but were spawned by executions of the deleted ones.
    delete from uc_ai_agent_executions
     where id in (
       select e.id
         from uc_ai_agent_executions e
        start with e.agent_id in (
          select a.id from uc_ai_agents a where a.code like p_code_pattern
        )
      connect by nocycle prior e.id = e.parent_execution_id
     );

    delete from uc_ai_agent_sessions
     where root_agent_id in (
       select a.id from uc_ai_agents a where a.code like p_code_pattern
     );

    delete from uc_ai_agents where code like p_code_pattern;
  end delete_agents_cascade;

  procedure cleanup_test_data
  as
  begin
    -- Delete test agents (with their committed execution telemetry)
    delete_agents_cascade('TEST_%');

    -- Delete test profiles
    delete from uc_ai_prompt_profiles where code like 'TEST_AGENT_%';

    -- Delete test calculator tool
    delete from uc_ai_tools where code = gc_calc_tool_code;

    -- Delete test product tool
    delete from uc_ai_tools where code = gc_product_tool_code;

    -- Drop test calculator function
    begin
      execute immediate 'drop function test_demo_calculate';
    exception
      when others then null;
    end;

    -- Drop test product lookup function
    begin
      execute immediate 'drop function test_get_product_details';
    exception
      when others then null;
    end;
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

  procedure validate_execution_context(
    p_session_id in varchar2,
    p_test_name  in varchar2
  )
  as
    l_created_by  uc_ai_agent_executions.created_by%type;
    l_db_user     uc_ai_agent_executions.db_user%type;
    l_sid         uc_ai_agent_executions.sid%type;
    l_env_context uc_ai_agent_executions.env_context%type;
    l_has_session_user number;
  begin
    select created_by, db_user, sid, env_context
      into l_created_by, l_db_user, l_sid, l_env_context
      from uc_ai_agent_executions
     where session_id = p_session_id
       and parent_execution_id is null
     fetch first 1 row only;

    ut.expect(
      l_created_by,
      p_test_name || ': created_by should be the caller''s DB user'
    ).to_equal(user);

    ut.expect(
      l_db_user,
      p_test_name || ': db_user should be the caller''s DB user'
    ).to_equal(user);

    ut.expect(
      l_sid,
      p_test_name || ': sid should be captured'
    ).to_be_not_null();

    ut.expect(
      l_env_context is not null,
      p_test_name || ': env_context should be captured'
    ).to_be_true();

    select case when json_exists(l_env_context, '$.session_user') then 1 else 0 end
      into l_has_session_user
      from dual;

    ut.expect(
      l_has_session_user,
      p_test_name || ': env_context should contain session_user'
    ).to_equal(1);
  end validate_execution_context;

  procedure validate_session_persistence(
    p_session_id         in varchar2,
    p_root_agent_code    in varchar2,
    p_final_agent_code   in varchar2,
    p_expected_turns     in number,
    p_test_name          in varchar2,
    p_min_assistant_rows in number default 1
  )
  as
    l_root_agent_id  uc_ai_agents.id%type;
    l_final_agent_id uc_ai_agents.id%type;
    l_count          number;

    -- session header
    l_root_id        number;
    l_status         varchar2(50 char);
    l_turn_count     number;
    l_message_count  number;
    l_sess_in        number;
    l_sess_out       number;
    l_started        timestamp;
    l_last_activity  timestamp;

    -- reconciliation
    l_exec_sum_in    number;
    l_exec_sum_out   number;
    l_msg_rows       number;

    -- numeric scratch (min/max/distinct probes)
    l_min            number;
    l_max            number;
  begin
    select id into l_root_agent_id
      from uc_ai_agents
     where code = p_root_agent_code and status = 'active'
     fetch first 1 row only;

    select id into l_final_agent_id
      from uc_ai_agents
     where code = p_final_agent_code and status = 'active'
     fetch first 1 row only;

    -- ---------------------------------------------------------------- SESSION
    -- Exactly one session header row for the conversation.
    select count(*) into l_count
      from uc_ai_agent_sessions
     where session_id = p_session_id;
    ut.expect(l_count, p_test_name || ': one session header row').to_equal(1);

    select root_agent_id, status, turn_count, message_count,
           total_input_tokens, total_output_tokens, started_at, last_activity_at
      into l_root_id, l_status, l_turn_count, l_message_count,
           l_sess_in, l_sess_out, l_started, l_last_activity
      from uc_ai_agent_sessions
     where session_id = p_session_id;

    ut.expect(l_root_id, p_test_name || ': session root_agent_id is the entry agent').to_equal(l_root_agent_id);
    ut.expect(l_status, p_test_name || ': session status completed').to_equal(uc_ai_agents_api.c_exec_completed);
    ut.expect(l_turn_count, p_test_name || ': session turn_count').to_equal(p_expected_turns);
    ut.expect(l_started is not null, p_test_name || ': session started_at set').to_be_true();
    ut.expect(l_last_activity is not null, p_test_name || ': session last_activity_at set').to_be_true();
    ut.expect(l_last_activity >= l_started, p_test_name || ': last_activity_at >= started_at').to_be_true();

    -- ------------------------------------------------------------- EXECUTIONS
    -- One top-level execution per turn; each finished cleanly.
    select count(*) into l_count
      from uc_ai_agent_executions
     where session_id = p_session_id
       and parent_execution_id is null;
    ut.expect(l_count, p_test_name || ': one top-level execution per turn').to_equal(p_expected_turns);

    -- Top-level executions all carry a turn_index, matching the session count.
    select count(*) into l_count
      from uc_ai_agent_executions
     where session_id = p_session_id
       and parent_execution_id is null
       and turn_index is not null;
    ut.expect(l_count, p_test_name || ': every top-level execution has a turn_index').to_equal(p_expected_turns);

    -- turn_index numbering is contiguous 1..N with no gaps or duplicates.
    select count(distinct turn_index), min(turn_index), max(turn_index)
      into l_count, l_min, l_max
      from uc_ai_agent_executions
     where session_id = p_session_id
       and turn_index is not null;
    ut.expect(l_count, p_test_name || ': distinct turn_index count').to_equal(p_expected_turns);
    ut.expect(l_min, p_test_name || ': turn_index starts at 1').to_equal(1);
    ut.expect(l_max, p_test_name || ': turn_index ends at N').to_equal(p_expected_turns);

    select count(*) into l_count
      from uc_ai_agent_executions
     where session_id = p_session_id
       and turn_index is not null
       and turn_index not between 1 and p_expected_turns;
    ut.expect(l_count, p_test_name || ': turn_index values within 1..N').to_equal(0);

    -- Nested child executions never carry a turn_index (spec invariant).
    select count(*) into l_count
      from uc_ai_agent_executions
     where session_id = p_session_id
       and parent_execution_id is not null
       and turn_index is not null;
    ut.expect(l_count, p_test_name || ': child executions leave turn_index null').to_equal(0);

    -- Every execution in the session finished as completed with a timestamp.
    select count(*) into l_count
      from uc_ai_agent_executions
     where session_id = p_session_id
       and (status != uc_ai_agents_api.c_exec_completed or completed_at is null
            or started_at is null or completed_at < started_at);
    ut.expect(l_count, p_test_name || ': all executions completed with valid timestamps').to_equal(0);

    -- Every top-level execution stored its output_result JSON.
    select count(*) into l_count
      from uc_ai_agent_executions
     where session_id = p_session_id
       and parent_execution_id is null
       and output_result is null;
    ut.expect(l_count, p_test_name || ': every turn stored an output_result').to_equal(0);

    -- Every child hangs, over any number of levels, under a top-level execution
    -- of the SAME session. A chain can be deeper than one level: an agent
    -- reached as a tool starts a run under the run that called the tool, and
    -- that run can itself be a delegate of an orchestrator.
    select count(*) into l_count
      from uc_ai_agent_executions c
     where c.session_id = p_session_id
       and c.parent_execution_id is not null
       and not exists (
             select 1
               from uc_ai_agent_executions p
              where p.parent_execution_id is null
                and p.session_id = c.session_id
             start with p.id = c.parent_execution_id
            connect by nocycle prior p.parent_execution_id = p.id);
    ut.expect(l_count, p_test_name || ': every child hangs under a top-level parent in the session').to_equal(0);

    -- The handoff wrapper delegates all LLM work: its own token totals stay 0.
    select count(*) into l_count
      from uc_ai_agent_executions
     where session_id = p_session_id
       and parent_execution_id is null
       and (total_input_tokens != 0 or total_output_tokens != 0);
    ut.expect(l_count, p_test_name || ': wrapper executions spent no tokens themselves').to_equal(0);

    -- The agent that answered actually ran as a (child) execution.
    select count(*) into l_count
      from uc_ai_agent_executions
     where session_id = p_session_id
       and agent_id = l_final_agent_id
       and parent_execution_id is not null;
    ut.expect(l_count, p_test_name || ': the final agent ran as a child execution').to_be_greater_than(0);

    -- Session token totals reconcile with the SUM over executions, and the
    -- children actually consumed tokens.
    select nvl(sum(total_input_tokens), 0), nvl(sum(total_output_tokens), 0)
      into l_exec_sum_in, l_exec_sum_out
      from uc_ai_agent_executions
     where session_id = p_session_id;
    ut.expect(l_sess_in, p_test_name || ': session input tokens = sum over executions').to_equal(l_exec_sum_in);
    ut.expect(l_sess_out, p_test_name || ': session output tokens = sum over executions').to_equal(l_exec_sum_out);
    ut.expect(l_sess_in, p_test_name || ': children spent input tokens').to_be_greater_than(0);
    ut.expect(l_sess_out, p_test_name || ': children spent output tokens').to_be_greater_than(0);

    -- ---------------------------------------------------------------- MESSAGES
    -- Header message_count matches the actual number of persisted rows.
    select count(*) into l_msg_rows
      from uc_ai_agent_messages
     where session_id = p_session_id;
    ut.expect(l_message_count, p_test_name || ': session message_count = actual message rows').to_equal(l_msg_rows);
    ut.expect(l_msg_rows, p_test_name || ': conversation produced messages').to_be_greater_than(0);

    -- Every message links to a top-level execution of this session (messages are
    -- persisted per turn against the wrapper execution).
    select count(*) into l_count
      from uc_ai_agent_messages m
     where m.session_id = p_session_id
       and not exists (
             select 1 from uc_ai_agent_executions e
              where e.id = m.execution_id
                and e.session_id = p_session_id
                and e.parent_execution_id is null);
    ut.expect(l_count, p_test_name || ': every message links to a top-level execution of the session').to_equal(0);

    -- One distinct wrapper execution owns the messages of each turn.
    select count(distinct execution_id) into l_count
      from uc_ai_agent_messages
     where session_id = p_session_id;
    ut.expect(l_count, p_test_name || ': messages spread across one execution per turn').to_equal(p_expected_turns);

    -- seq is globally contiguous 1..N within the session (no gaps/duplicates).
    select count(distinct seq), min(seq), max(seq)
      into l_count, l_min, l_max
      from uc_ai_agent_messages
     where session_id = p_session_id;
    ut.expect(l_count, p_test_name || ': seq values are unique').to_equal(l_msg_rows);
    ut.expect(l_min, p_test_name || ': seq starts at 1').to_equal(1);
    ut.expect(l_max, p_test_name || ': seq ends at message count').to_equal(l_msg_rows);

    -- Every message has a creation timestamp.
    select count(*) into l_count
      from uc_ai_agent_messages
     where session_id = p_session_id
       and created_at is null;
    ut.expect(l_count, p_test_name || ': every message has created_at').to_equal(0);

    -- The turn's user prompt and an assistant answer are both recorded.
    select count(*) into l_count
      from uc_ai_agent_messages
     where session_id = p_session_id and role = 'user';
    ut.expect(l_count, p_test_name || ': at least one user message').to_be_greater_than(0);

    select count(*) into l_count
      from uc_ai_agent_messages
     where session_id = p_session_id and role = 'assistant';
    ut.expect(l_count, p_test_name || ': assistant messages recorded').to_be_greater_or_equal(p_min_assistant_rows);

    -- Attribution: agent-produced rows (assistant/tool_call/tool_result/
    -- reasoning) always name a producing agent; caller input (user/system)
    -- never does.
    select count(*) into l_count
      from uc_ai_agent_messages
     where session_id = p_session_id
       and role in ('assistant', 'tool_call', 'tool_result', 'reasoning')
       and agent_code is null;
    ut.expect(l_count, p_test_name || ': agent-produced messages carry an agent_code').to_equal(0);

    select count(*) into l_count
      from uc_ai_agent_messages
     where session_id = p_session_id
       and role in ('user', 'system')
       and agent_code is not null;
    ut.expect(l_count, p_test_name || ': caller input messages have no agent_code').to_equal(0);

    -- Every attributed agent_code belongs to an agent that ran in this session.
    select count(*) into l_count
      from uc_ai_agent_messages m
     where m.session_id = p_session_id
       and m.agent_code is not null
       and not exists (
             select 1
               from uc_ai_agent_executions e
               join uc_ai_agents a on a.id = e.agent_id
              where e.session_id = p_session_id
                and a.code = m.agent_code);
    ut.expect(l_count, p_test_name || ': every agent_code matches an execution agent in the session').to_equal(0);

    -- tool_call rows are well formed: a tool name is always recorded.
    select count(*) into l_count
      from uc_ai_agent_messages
     where session_id = p_session_id
       and role = 'tool_call'
       and tool_name is null;
    ut.expect(l_count, p_test_name || ': tool_call rows record a tool_name').to_equal(0);

    -- tool_result rows carry a name and the hard-coded success status.
    select count(*) into l_count
      from uc_ai_agent_messages
     where session_id = p_session_id
       and role = 'tool_result'
       and (tool_name is null or tool_status != 'success');
    ut.expect(l_count, p_test_name || ': tool_result rows record name and success status').to_equal(0);
  end validate_session_persistence;

end uc_ai_test_agent_utils;
/
