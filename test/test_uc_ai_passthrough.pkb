create or replace package body test_uc_ai_passthrough as

  procedure reset_globals
  as
  begin
    uc_ai.reset_globals;
  end reset_globals;


  procedure extra_body_merges_new_keys
  as
    l_obj      json_object_t := json_object_t();
    l_settings uc_ai_settings.t_settings;
  begin
    l_obj.put('model', 'claude-x');
    uc_ai.g_extra_body := json_object_t('{"top_p":0.9,"stop_sequences":["END"]}');
    l_settings := uc_ai_settings.build_from_globals;

    uc_ai_settings.apply_extra_body(l_obj, l_settings);

    ut.expect(l_obj.get_number('top_p')).to_equal(0.9);
    ut.expect(l_obj.get_array('stop_sequences').get_string(0)).to_equal('END');
    -- unrelated existing key untouched
    ut.expect(l_obj.get_string('model')).to_equal('claude-x');
  end extra_body_merges_new_keys;


  procedure extra_body_overrides_key
  as
    l_obj      json_object_t := json_object_t();
    l_settings uc_ai_settings.t_settings;
  begin
    -- temperature is a normal (non-reserved) key -> extra_body wins
    l_obj.put('temperature', 1);
    uc_ai.g_extra_body := json_object_t('{"temperature":0.2}');
    l_settings := uc_ai_settings.build_from_globals;

    uc_ai_settings.apply_extra_body(l_obj, l_settings);

    ut.expect(l_obj.get_number('temperature')).to_equal(0.2);
  end extra_body_overrides_key;


  procedure extra_body_protects_core
  as
    l_obj      json_object_t := json_object_t();
    l_settings uc_ai_settings.t_settings;
  begin
    l_obj.put('model', 'real-model');
    l_obj.put('messages', 'real-messages');
    l_obj.put('tools', 'real-tools');
    uc_ai.g_extra_body := json_object_t(
      '{"model":"HACK","messages":"HACK","tools":"HACK","input":"HACK",'
      || '"instructions":"HACK","system":"HACK","top_p":0.5}'
    );
    l_settings := uc_ai_settings.build_from_globals;

    uc_ai_settings.apply_extra_body(l_obj, l_settings);

    -- reserved keys preserved
    ut.expect(l_obj.get_string('model')).to_equal('real-model');
    ut.expect(l_obj.get_string('messages')).to_equal('real-messages');
    ut.expect(l_obj.get_string('tools')).to_equal('real-tools');
    -- reserved keys not injected by the escape hatch
    ut.expect(l_obj.has('input')).to_be_false();
    ut.expect(l_obj.has('instructions')).to_be_false();
    ut.expect(l_obj.has('system')).to_be_false();
    -- non-reserved key still merged
    ut.expect(l_obj.get_number('top_p')).to_equal(0.5);
  end extra_body_protects_core;


  procedure extra_body_null_noop
  as
    l_obj      json_object_t := json_object_t();
    l_settings uc_ai_settings.t_settings;
  begin
    l_obj.put('model', 'm');
    -- g_extra_body left null
    l_settings := uc_ai_settings.build_from_globals;

    uc_ai_settings.apply_extra_body(l_obj, l_settings);

    ut.expect(l_obj.get_keys().count).to_equal(1);
    ut.expect(l_obj.get_string('model')).to_equal('m');
  end extra_body_null_noop;


  procedure globals_snapshot
  as
    l_settings uc_ai_settings.t_settings;
  begin
    uc_ai.g_extra_body := json_object_t('{"top_p":0.7}');
    uc_ai.g_provider_tools := json_array_t('[{"type":"web_search_20250305","name":"web_search"}]');

    l_settings := uc_ai_settings.build_from_globals;

    ut.expect(l_settings.extra_body.get_number('top_p')).to_equal(0.7);
    ut.expect(l_settings.provider_tools.get_size).to_equal(1);
    ut.expect(
      treat(l_settings.provider_tools.get(0) as json_object_t).get_string('name')
    ).to_equal('web_search');
  end globals_snapshot;


  procedure config_reads_keys
  as
    l_config   json_object_t;
    l_settings uc_ai_settings.t_settings;
  begin
    l_config := json_object_t(
      '{"g_extra_body":{"service_tier":"flex"},'
      || '"g_provider_tools":[{"type":"web_search_preview"}]}'
    );

    l_settings := uc_ai_settings.build_from_config(l_config, uc_ai.c_provider_openai);

    ut.expect(l_settings.extra_body.get_string('service_tier')).to_equal('flex');
    ut.expect(l_settings.provider_tools.get_size).to_equal(1);
    ut.expect(
      treat(l_settings.provider_tools.get(0) as json_object_t).get_string('type')
    ).to_equal('web_search_preview');
  end config_reads_keys;


  procedure provider_tools_verbatim
  as
    l_provider_tools json_array_t := json_array_t('[{"type":"web_search_20250305","name":"web_search"}]');
    l_arr            json_array_t;
    l_entry          json_object_t;
  begin
    -- OpenAI normally wraps function tools in {type:function, function:{...}};
    -- provider tools must be appended raw, with no wrapping.
    l_arr := uc_ai_tools_api.get_tools_array(
      p_provider       => uc_ai.c_provider_openai
    , p_enable_tools   => false
    , p_provider_tools => l_provider_tools
    );

    ut.expect(l_arr.get_size).to_equal(1);
    l_entry := treat(l_arr.get(0) as json_object_t);
    ut.expect(l_entry.get_string('type')).to_equal('web_search_20250305');
    ut.expect(l_entry.get_string('name')).to_equal('web_search');
    ut.expect(l_entry.has('function')).to_be_false();
  end provider_tools_verbatim;


  procedure provider_tools_when_disabled
  as
    l_provider_tools json_array_t := json_array_t('[{"type":"web_search_20250305","name":"web_search"}]');
    l_arr            json_array_t;
  begin
    -- local function tools disabled, but provider tools still sent
    l_arr := uc_ai_tools_api.get_tools_array(
      p_provider       => uc_ai.c_provider_anthropic
    , p_enable_tools   => false
    , p_provider_tools => l_provider_tools
    );

    ut.expect(l_arr.get_size).to_equal(1);
    ut.expect(
      treat(l_arr.get(0) as json_object_t).get_string('type')
    ).to_equal('web_search_20250305');
  end provider_tools_when_disabled;

end test_uc_ai_passthrough;
/
