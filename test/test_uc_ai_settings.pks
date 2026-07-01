create or replace package test_uc_ai_settings as

  --%suite(uc_ai_settings: snapshot config globals into a threadable record)

  --%test(build_from_globals captures every config global)
  procedure build_captures_globals;

  --%test(new_run_state is zero-initialised)
  procedure new_run_state_zeroed;

end test_uc_ai_settings;
/
