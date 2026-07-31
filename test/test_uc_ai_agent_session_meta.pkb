create or replace package body test_uc_ai_agent_session_meta as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-5040): asserting on the raised error is the point of these tests

  -- One header per purpose so a test never depends on another test's row.
  gc_sess_a       constant varchar2(255 char) := 'TEST_SESSMETA_A';
  gc_sess_list    constant varchar2(255 char) := 'TEST_SESSMETA_LIST';
  -- Deliberately never inserted: stands for a session whose first execution has
  -- not started yet, which is when a front end can already know the session id.
  gc_sess_missing constant varchar2(255 char) := 'TEST_SESSMETA_MISSING';

  gc_owner        constant varchar2(255 char) := 'TEST_SESSMETA_OWNER';
  gc_other        constant varchar2(255 char) := 'TEST_SESSMETA_OTHER';
  gc_list_owner   constant varchar2(255 char) := 'TEST_SESSMETA_LISTUSER';


  procedure delete_test_rows
  as
  begin
    delete from uc_ai_agent_sessions where session_id like 'TEST_SESSMETA%';
    commit;
  end delete_test_rows;


  procedure reset_headers
  as
  begin
    delete_test_rows;

    -- root_agent_id stays null: these setters never read the agent, so the tests
    -- need no agent or profile fixtures at all.
    insert into uc_ai_agent_sessions (session_id, status, created_by, last_activity_at)
    values (gc_sess_a, uc_ai_agents_api.c_exec_completed, gc_owner, systimestamp);

    insert into uc_ai_agent_sessions (session_id, status, created_by, last_activity_at)
    values (gc_sess_list, uc_ai_agents_api.c_exec_completed, gc_list_owner, systimestamp);

    -- The setters run in autonomous transactions and cannot see uncommitted rows.
    commit;
  end reset_headers;


  procedure teardown
  as
  begin
    delete_test_rows;
  end teardown;


  -- Local readers keep each test to its assertions.
  function title_of(
    p_session_id in varchar2
  ) return varchar2
  as
    l_title uc_ai_agent_sessions.title%type;
  begin
    select s.title into l_title
      from uc_ai_agent_sessions s
     where s.session_id = p_session_id;

    return l_title;
  end title_of;


  function header_count(
    p_session_id in varchar2
  ) return number
  as
    l_count number;
  begin
    select count(*) into l_count
      from uc_ai_agent_sessions s
     where s.session_id = p_session_id;

    return l_count;
  end header_count;


  procedure feedback_of(
    p_session_id in varchar2,
    p_rating    out uc_ai_agent_sessions.feedback_rating%type,
    p_comment   out uc_ai_agent_sessions.feedback_comment%type,
    p_at        out uc_ai_agent_sessions.feedback_at%type
  )
  as
  begin
    select s.feedback_rating, s.feedback_comment, s.feedback_at
      into p_rating, p_comment, p_at
      from uc_ai_agent_sessions s
     where s.session_id = p_session_id;
  end feedback_of;


  function last_activity_of(
    p_session_id in varchar2
  ) return timestamp
  as
    l_at uc_ai_agent_sessions.last_activity_at%type;
  begin
    select s.last_activity_at into l_at
      from uc_ai_agent_sessions s
     where s.session_id = p_session_id;

    return l_at;
  end last_activity_of;


  -- set_session_title ---------------------------------------------------------

  procedure title_set_and_trimmed
  as
  begin
    uc_ai_agents_api.set_session_title(gc_sess_a, '  Invoice questions  ');

    ut.expect(title_of(gc_sess_a), 'title stored without surrounding blanks')
      .to_equal('Invoice questions');
  end title_set_and_trimmed;


  procedure title_overwrites
  as
  begin
    uc_ai_agents_api.set_session_title(gc_sess_a, 'First name');
    uc_ai_agents_api.set_session_title(gc_sess_a, 'Renamed');

    ut.expect(title_of(gc_sess_a), 'second call renames rather than being ignored')
      .to_equal('Renamed');
  end title_overwrites;


  procedure title_truncated
  as
  begin
    uc_ai_agents_api.set_session_title(gc_sess_a, lpad('x', 350, 'x'));

    ut.expect(length(title_of(gc_sess_a)), 'title cut to the 200 char column')
      .to_equal(200);
  end title_truncated;


  procedure title_null_clears
  as
  begin
    uc_ai_agents_api.set_session_title(gc_sess_a, 'Named');
    uc_ai_agents_api.set_session_title(gc_sess_a, null);

    ut.expect(title_of(gc_sess_a), 'null title clears the name').to_be_null();
  end title_null_clears;


  procedure title_blank_clears
  as
  begin
    uc_ai_agents_api.set_session_title(gc_sess_a, 'Named');
    uc_ai_agents_api.set_session_title(gc_sess_a, '     ');

    ut.expect(title_of(gc_sess_a), 'whitespace-only title clears the name').to_be_null();
  end title_blank_clears;


  procedure title_missing_header_noop
  as
  begin
    uc_ai_agents_api.set_session_title(gc_sess_missing, 'Ghost conversation');

    ut.expect(header_count(gc_sess_missing), 'setter never creates a header row')
      .to_equal(0);
  end title_missing_header_noop;


  procedure title_null_session_noop
  as
  begin
    uc_ai_agents_api.set_session_title(null, 'No session');

    -- Reaching here without an exception is the assertion; nothing may have moved.
    ut.expect(title_of(gc_sess_a), 'a null session id touches no row').to_be_null();
  end title_null_session_noop;


  procedure title_created_by_blocks
  as
  begin
    uc_ai_agents_api.set_session_title(gc_sess_a, 'Mine', gc_owner);
    uc_ai_agents_api.set_session_title(gc_sess_a, 'Stolen', gc_other);

    ut.expect(title_of(gc_sess_a), 'another user cannot rename the session')
      .to_equal('Mine');
  end title_created_by_blocks;


  procedure title_created_by_allows
  as
  begin
    uc_ai_agents_api.set_session_title(gc_sess_a, 'Mine', gc_owner);

    ut.expect(title_of(gc_sess_a), 'the opening user can rename the session')
      .to_equal('Mine');
  end title_created_by_allows;


  procedure title_survives_rollback
  as
  begin
    uc_ai_agents_api.set_session_title(gc_sess_a, 'Committed independently');
    rollback;

    ut.expect(title_of(gc_sess_a), 'autonomous commit outlives the caller rollback')
      .to_equal('Committed independently');
  end title_survives_rollback;


  procedure title_keeps_last_activity
  as
    l_before timestamp;
  begin
    l_before := last_activity_of(gc_sess_a);
    uc_ai_agents_api.set_session_title(gc_sess_a, 'Renaming is not activity');

    -- list_sessions orders by last_activity_at, so a rename must not jump the
    -- conversation to the top of the front end's list.
    ut.expect(last_activity_of(gc_sess_a), 'rename leaves last_activity_at alone')
      .to_equal(l_before);
  end title_keeps_last_activity;


  procedure title_locked_header_raises
  as
    l_sqlcode number;
    l_sqlerrm varchar2(4000 char);
  begin
    -- The caller takes the row lock and does not commit. The setter's autonomous
    -- transaction cannot wait for a lock held by its own suspended caller.
    update uc_ai_agent_sessions s
       set s.status = uc_ai_agents_api.c_exec_completed
     where s.session_id = gc_sess_a;

    begin
      uc_ai_agents_api.set_session_title(gc_sess_a, 'Never written');
      ut.fail('set_session_title should have raised for a caller-locked header');
    exception
      -- @dblinter ignore(g-5080): the assertion is on sqlcode/sqlerrm; a backtrace would add nothing
      when others then
        l_sqlcode := sqlcode;
        l_sqlerrm := sqlerrm;
    end;

    rollback;  -- release the caller's lock

    -- A clear config error (-20503), not a raw ORA-00060 deadlock
    ut.expect(l_sqlcode, 'raises the config error, not ORA-00060').to_equal(-20503);
    ut.expect(l_sqlerrm, 'error names the uncommitted caller change')
      .to_be_like('%uncommitted change%');
  end title_locked_header_raises;


  -- set_session_feedback ------------------------------------------------------

  procedure fb_up_recorded
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
  begin
    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'up', 'Exactly what I needed');
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);

    ut.expect(l_rating, 'up rating stored').to_equal('up');
    ut.expect(l_comment, 'comment stored').to_equal('Exactly what I needed');
    ut.expect(l_at is not null, 'feedback_at stamped').to_be_true();
  end fb_up_recorded;


  procedure fb_down_recorded
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
  begin
    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'down', 'Wrong invoice');
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);

    ut.expect(l_rating, 'down rating stored').to_equal('down');
    ut.expect(l_comment, 'comment stored').to_equal('Wrong invoice');
    ut.expect(l_at is not null, 'feedback_at stamped').to_be_true();
  end fb_down_recorded;


  procedure fb_rating_normalized
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
  begin
    uc_ai_agents_api.set_session_feedback(gc_sess_a, '  UP  ');
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);
    ut.expect(l_rating, 'mixed case and blanks normalized to up').to_equal('up');

    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'Down');
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);
    ut.expect(l_rating, 'mixed case normalized to down').to_equal('down');
  end fb_rating_normalized;


  procedure fb_unknown_rating_nulled
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
  begin
    -- A newer front end sending a rating this version predates must land on null,
    -- never on the check constraint.
    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'sideways', 'Not sure');
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);

    ut.expect(l_rating, 'unrecognized rating becomes null').to_be_null();
    ut.expect(l_comment, 'comment goes with the unrecognized rating').to_be_null();
    ut.expect(l_at, 'no timestamp without a rating').to_be_null();
  end fb_unknown_rating_nulled;


  procedure fb_overlong_rating_no_error
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
  begin
    -- Wider than feedback_rating: must normalize away rather than raise ORA-06502.
    uc_ai_agents_api.set_session_feedback(gc_sess_a, lpad('z', 60, 'z'));
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);

    ut.expect(l_rating, 'over-long rating becomes null').to_be_null();
  end fb_overlong_rating_no_error;


  procedure fb_null_withdraws
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
  begin
    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'down', 'Bad answer');
    uc_ai_agents_api.set_session_feedback(gc_sess_a, null);
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);

    -- All three clear together: "not rated" must never decay into "rated, comment
    -- lost" or leave a comment attached to no verdict.
    ut.expect(l_rating, 'rating withdrawn').to_be_null();
    ut.expect(l_comment, 'comment withdrawn with the rating').to_be_null();
    ut.expect(l_at, 'timestamp withdrawn with the rating').to_be_null();
  end fb_null_withdraws;


  procedure fb_change_of_mind
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
    l_first   uc_ai_agent_sessions.feedback_at%type;
  begin
    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'up', 'Looked right');
    feedback_of(gc_sess_a, l_rating, l_comment, l_first);

    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'down', 'Checked it, wrong');
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);

    ut.expect(l_rating, 'later rating wins').to_equal('down');
    ut.expect(l_comment, 'comment replaced along with the rating').to_equal('Checked it, wrong');
    ut.expect(l_at >= l_first, 'timestamp refreshed on the new verdict').to_be_true();
  end fb_change_of_mind;


  procedure fb_comment_truncated
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
  begin
    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'down', lpad('c', 2500, 'c'));
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);

    ut.expect(length(l_comment), 'comment cut to the 2000 char column').to_equal(2000);
    ut.expect(l_rating, 'rating still recorded alongside').to_equal('down');
  end fb_comment_truncated;


  procedure fb_comment_trimmed
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
  begin
    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'up', '   Thanks   ');
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);

    ut.expect(l_comment, 'comment stored without surrounding blanks').to_equal('Thanks');
  end fb_comment_trimmed;


  procedure fb_missing_header_noop
  as
  begin
    uc_ai_agents_api.set_session_feedback(gc_sess_missing, 'up', 'Ghost');

    ut.expect(header_count(gc_sess_missing), 'setter never creates a header row')
      .to_equal(0);
  end fb_missing_header_noop;


  procedure fb_null_session_noop
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
  begin
    uc_ai_agents_api.set_session_feedback(null, 'up', 'No session');
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);

    -- Reaching here without an exception is the assertion; nothing may have moved.
    ut.expect(l_rating, 'a null session id touches no row').to_be_null();
  end fb_null_session_noop;


  procedure fb_created_by_blocks
  as
    l_rating  uc_ai_agent_sessions.feedback_rating%type;
    l_comment uc_ai_agent_sessions.feedback_comment%type;
    l_at      uc_ai_agent_sessions.feedback_at%type;
  begin
    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'up', 'Mine', gc_owner);
    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'down', 'Not mine', gc_other);
    feedback_of(gc_sess_a, l_rating, l_comment, l_at);

    ut.expect(l_rating, 'another user cannot rate the session').to_equal('up');
    ut.expect(l_comment, 'another user cannot replace the comment').to_equal('Mine');
  end fb_created_by_blocks;


  procedure fb_keeps_last_activity
  as
    l_before timestamp;
  begin
    l_before := last_activity_of(gc_sess_a);
    uc_ai_agents_api.set_session_feedback(gc_sess_a, 'up', 'Rating is not activity');

    ut.expect(last_activity_of(gc_sess_a), 'rating leaves last_activity_at alone')
      .to_equal(l_before);
  end fb_keeps_last_activity;


  procedure fb_locked_header_raises
  as
    l_sqlcode number;
    l_sqlerrm varchar2(4000 char);
  begin
    update uc_ai_agent_sessions s
       set s.status = uc_ai_agents_api.c_exec_completed
     where s.session_id = gc_sess_a;

    begin
      uc_ai_agents_api.set_session_feedback(gc_sess_a, 'up', 'Never written');
      ut.fail('set_session_feedback should have raised for a caller-locked header');
    exception
      -- @dblinter ignore(g-5080): the assertion is on sqlcode/sqlerrm; a backtrace would add nothing
      when others then
        l_sqlcode := sqlcode;
        l_sqlerrm := sqlerrm;
    end;

    rollback;  -- release the caller's lock

    ut.expect(l_sqlcode, 'raises the config error, not ORA-00060').to_equal(-20503);
    ut.expect(l_sqlerrm, 'error names the uncommitted caller change')
      .to_be_like('%uncommitted change%');
  end fb_locked_header_raises;


  -- projection ----------------------------------------------------------------

  procedure list_sessions_projects_meta
  as
    l_sessions_cur sys_refcursor;
    -- Fetched positionally, so this also pins the column order of the cursor a
    -- front end binds to.
    l_session_id   uc_ai_agent_sessions.session_id%type;
    l_root_id      uc_ai_agent_sessions.root_agent_id%type;
    l_title        uc_ai_agent_sessions.title%type;
    l_rating       uc_ai_agent_sessions.feedback_rating%type;
    l_comment      uc_ai_agent_sessions.feedback_comment%type;
    l_feedback_at  uc_ai_agent_sessions.feedback_at%type;
    l_agent_code   uc_ai_agents.code%type;
    l_agent_ver    uc_ai_agents.version%type;
    l_agent_type   uc_ai_agents.agent_type%type;
    l_status       uc_ai_agent_sessions.status%type;
    l_turns        uc_ai_agent_sessions.turn_count%type;
    l_messages     uc_ai_agent_sessions.message_count%type;
    l_in_tokens    uc_ai_agent_sessions.total_input_tokens%type;
    l_out_tokens   uc_ai_agent_sessions.total_output_tokens%type;
    l_started      uc_ai_agent_sessions.started_at%type;
    l_activity     uc_ai_agent_sessions.last_activity_at%type;
    l_created_by   uc_ai_agent_sessions.created_by%type;
  begin
    uc_ai_agents_api.set_session_title(gc_sess_list, 'Listed conversation');
    uc_ai_agents_api.set_session_feedback(gc_sess_list, 'up', 'Helpful');

    -- gc_list_owner opened exactly one session, so the first row is that session.
    l_sessions_cur := uc_ai_agents_api.list_sessions(p_created_by => gc_list_owner);
    -- @dblinter ignore(g-3140): the cursor projects a join, so no table rowtype anchors it; fetching positionally is what pins the column order a front end binds to
    fetch l_sessions_cur into
      l_session_id, l_root_id, l_title, l_rating, l_comment, l_feedback_at,
      l_agent_code, l_agent_ver, l_agent_type, l_status, l_turns, l_messages,
      l_in_tokens, l_out_tokens, l_started, l_activity, l_created_by;
    close l_sessions_cur;

    ut.expect(l_session_id, 'the listed session is the one we set up').to_equal(gc_sess_list);
    ut.expect(l_title, 'list_sessions projects the title').to_equal('Listed conversation');
    ut.expect(l_rating, 'list_sessions projects the rating').to_equal('up');
    ut.expect(l_comment, 'list_sessions projects the comment').to_equal('Helpful');
    ut.expect(l_feedback_at is not null, 'list_sessions projects feedback_at').to_be_true();
  end list_sessions_projects_meta;


  procedure constraint_guards_direct_dml
  as
    l_sqlcode number;
  begin
    -- The API normalizes unknown ratings away; the constraint is the backstop for
    -- anything that writes the column directly.
    begin
      update uc_ai_agent_sessions s
         set s.feedback_rating = 'meh'
       where s.session_id = gc_sess_a;
      ut.fail('the check constraint should have rejected an unknown rating');
    exception
      when others then
        l_sqlcode := sqlcode;
    end;

    rollback;

    ut.expect(l_sqlcode, 'check constraint violated (ORA-02290)').to_equal(-2290);
  end constraint_guards_direct_dml;

end test_uc_ai_agent_session_meta;
/
