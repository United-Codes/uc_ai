create or replace package body test_uc_ai_utils as

  procedure providers_returns_eight
  as
    l_count       pls_integer;
    l_openai_name varchar2(64 char);
  begin
    select count(*) into l_count
      from table(uc_ai_utils.get_providers);
    ut.expect(l_count).to_equal(8);

    select provider_name into l_openai_name
      from table(uc_ai_utils.get_providers)
     where provider_id = uc_ai.c_provider_openai;
    ut.expect(l_openai_name).to_equal('OpenAI');
  end providers_returns_eight;


  procedure providers_ids_unique_nonnull
  as
    l_total    pls_integer;
    l_distinct pls_integer;
    l_nulls    pls_integer;
  begin
    select count(*), count(distinct provider_id),
           sum(case when provider_id is null or provider_name is null then 1 else 0 end)
      into l_total, l_distinct, l_nulls
      from table(uc_ai_utils.get_providers);

    ut.expect(l_distinct).to_equal(l_total);
    ut.expect(l_nulls).to_equal(0);
  end providers_ids_unique_nonnull;


  procedure models_all_sane
  as
    l_total      pls_integer;
    l_nulls      pls_integer;
    l_bad_types  pls_integer;
    l_embeddings pls_integer;
  begin
    select count(*),
           sum(case when provider is null or model_id is null then 1 else 0 end),
           sum(case when model_type not in ('chat', 'embedding') then 1 else 0 end),
           sum(case when model_type = 'embedding' then 1 else 0 end)
      into l_total, l_nulls, l_bad_types, l_embeddings
      from table(uc_ai_utils.get_models);

    ut.expect(l_total).to_be_greater_than(0);
    ut.expect(l_nulls).to_equal(0);
    ut.expect(l_bad_types).to_equal(0);
    ut.expect(l_embeddings).to_be_greater_than(0);
  end models_all_sane;


  procedure models_filter_anthropic
  as
    l_total  pls_integer;
    l_other  pls_integer;
    l_sonnet pls_integer;
  begin
    select count(*),
           sum(case when provider != uc_ai.c_provider_anthropic then 1 else 0 end),
           sum(case when model_id = uc_ai_anthropic.c_model_claude_4_5_sonnet then 1 else 0 end)
      into l_total, l_other, l_sonnet
      from table(uc_ai_utils.get_models(p_provider => uc_ai.c_provider_anthropic));

    ut.expect(l_total).to_be_greater_than(0);
    ut.expect(l_other).to_equal(0);
    ut.expect(l_sonnet).to_equal(1);
  end models_filter_anthropic;


  procedure models_filter_unknown_empty
  as
    l_count pls_integer;
  begin
    select count(*) into l_count
      from table(uc_ai_utils.get_models(p_provider => 'does_not_exist'));

    ut.expect(l_count).to_equal(0);
  end models_filter_unknown_empty;


  procedure models_filters_partition_total
  as
    l_unfiltered pls_integer;
    l_partition  pls_integer := 0;
    l_count      pls_integer;
  begin
    select count(*) into l_unfiltered
      from table(uc_ai_utils.get_models);

    <<per_provider>>
    for prov in (select provider_id from table(uc_ai_utils.get_providers)) loop
      select count(*) into l_count
        from table(uc_ai_utils.get_models(p_provider => prov.provider_id));
      l_partition := l_partition + l_count;
    end loop per_provider;

    -- every model row must belong to exactly one known provider filter
    ut.expect(l_partition).to_equal(l_unfiltered);
  end models_filters_partition_total;

end test_uc_ai_utils;
/
