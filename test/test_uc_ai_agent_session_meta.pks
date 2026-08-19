create or replace package test_uc_ai_agent_session_meta as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Session title and feedback setters (LLM-free))
  --%suitepath(uc_ai.agents)
  --%rollback(manual)

  -- LLM-free unit tests for uc_ai_agents_api.set_session_title and
  -- set_session_feedback: the two conversation-header setters a front end (the
  -- UC AI chat plugin) drives. Session headers are inserted directly instead of
  -- being produced by an agent run, so no provider is called; the setters commit
  -- in autonomous transactions, so every fixture must be committed to be visible.

  --%afterall
  procedure teardown;

  --%beforeeach
  procedure reset_headers;

  -- set_session_title ---------------------------------------------------------

  --%test(Title is stored, trimmed of surrounding whitespace)
  procedure title_set_and_trimmed;

  --%test(Setting a title again overwrites it, so this doubles as rename)
  procedure title_overwrites;

  --%test(An over-long title is truncated to the column width, not rejected)
  procedure title_truncated;

  --%test(A null title clears the title back to unnamed)
  procedure title_null_clears;

  --%test(A blank title clears the title back to unnamed)
  procedure title_blank_clears;

  --%test(A session with no header yet is a silent no-op, not an insert)
  procedure title_missing_header_noop;

  --%test(A null session id is a silent no-op)
  procedure title_null_session_noop;

  --%test(p_created_by that does not match the opening user does not write)
  procedure title_created_by_blocks;

  --%test(p_created_by that matches the opening user writes)
  procedure title_created_by_allows;

  --%test(The write survives a rollback of the calling transaction)
  procedure title_survives_rollback;

  --%test(Renaming does not touch last_activity_at, so list order is stable)
  procedure title_keeps_last_activity;

  --%test(A caller holding the header row locked gets a clear error, not ORA-00060)
  procedure title_locked_header_raises;

  -- set_session_feedback ------------------------------------------------------

  --%test(An up rating is stored with its comment and a timestamp)
  procedure fb_up_recorded;

  --%test(A down rating is stored with its comment and a timestamp)
  procedure fb_down_recorded;

  --%test(Rating case and whitespace are normalized)
  procedure fb_rating_normalized;

  --%test(An unrecognized rating is normalized to null, never a constraint error)
  procedure fb_unknown_rating_nulled;

  --%test(A rating wider than the column does not raise)
  procedure fb_overlong_rating_no_error;

  --%test(A null rating withdraws the feedback: rating, comment and time clear together)
  procedure fb_null_withdraws;

  --%test(Changing the rating refreshes the comment and timestamp)
  procedure fb_change_of_mind;

  --%test(An over-long comment is truncated to the column width)
  procedure fb_comment_truncated;

  --%test(Comment is trimmed of surrounding whitespace)
  procedure fb_comment_trimmed;

  --%test(A session with no header yet is a silent no-op, not an insert)
  procedure fb_missing_header_noop;

  --%test(A null session id is a silent no-op)
  procedure fb_null_session_noop;

  --%test(p_created_by that does not match the opening user does not write)
  procedure fb_created_by_blocks;

  --%test(Feedback does not touch last_activity_at, so list order is stable)
  procedure fb_keeps_last_activity;

  --%test(A caller holding the header row locked gets a clear error, not ORA-00060)
  procedure fb_locked_header_raises;

  -- projection ----------------------------------------------------------------

  --%test(list_sessions returns the title and all three feedback columns)
  procedure list_sessions_projects_meta;

  --%test(The check constraint still rejects a rating written around the API)
  procedure constraint_guards_direct_dml;

end test_uc_ai_agent_session_meta;
/
