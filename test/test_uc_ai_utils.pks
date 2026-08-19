create or replace package test_uc_ai_utils as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(uc_ai_utils pipelined LOV functions)
  --%suitepath(uc_ai)

  -- LLM-free unit tests for the provider/model enumeration helpers.
  -- The body of uc_ai_utils is generated (scripts/generate_uc_ai_utils_body.sh),
  -- so model assertions stay loose instead of pinning exact counts.

  --%test(get_providers returns all eight providers)
  procedure providers_returns_eight;

  --%test(Provider ids are unique and names are set)
  procedure providers_ids_unique_nonnull;

  --%test(get_models returns sane rows for all providers)
  procedure models_all_sane;

  --%test(get_models filters by provider)
  procedure models_filter_anthropic;

  --%test(get_models returns no rows for an unknown provider)
  procedure models_filter_unknown_empty;

  --%test(Per-provider filtered counts add up to the unfiltered count)
  procedure models_filters_partition_total;

end test_uc_ai_utils;
/
