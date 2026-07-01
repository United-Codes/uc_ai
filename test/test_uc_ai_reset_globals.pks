create or replace package test_uc_ai_reset_globals as

  --%suite(reset_globals returns all package state to defaults)

  --%test(Resets uc_ai core globals)
  procedure resets_uc_ai_core;

  --%test(Resets all shared Responses API globals)
  procedure resets_responses_api;

  --%test(Resets all provider package globals)
  procedure resets_providers;

end test_uc_ai_reset_globals;
/
