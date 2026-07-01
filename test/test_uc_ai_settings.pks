create or replace package test_uc_ai_settings as

  --%suite(uc_ai_settings: snapshot config globals into a threadable record)

  --%test(build_from_globals captures every config global)
  procedure build_captures_globals;

  --%test(new_run_state is zero-initialised)
  procedure new_run_state_zeroed;

  --%test(build_from_config maps root and provider-nested keys into the record)
  procedure config_maps_keys;

  --%test(build_from_config leaves omitted keys at framework defaults)
  procedure config_uses_defaults;

  --%test(build_from_config does not read or mutate globals)
  procedure config_ignores_globals;

  --%test(build_from_config raises on an unknown root key)
  --%throws(-20503)
  procedure config_rejects_unknown_key;

  --%test(build_from_config raises on an unknown provider)
  --%throws(-20306)
  procedure config_rejects_unknown_provider;

end test_uc_ai_settings;
/
