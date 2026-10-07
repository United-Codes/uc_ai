create or replace package body test_uc_ai_decisions_live as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5040): the tests catch the raised error to skip on a missing credential
  -- @dblinter ignore(g-5080): the tests catch the expected exception to assert on its message; a backtrace adds nothing

  procedure reset_state
  as
  begin
    uc_ai.reset_globals;
    uc_ai_http.set_transport(null);
    uc_ai_openai.g_apex_web_credential := 'OPENAI';
  end reset_state;


  /*
   * True when the error comes from the environment and not from the code: the
   * web credential does not exist.
   */
  function is_environment_error(p_message in varchar2) return boolean
  as
  begin
    return lower(p_message) like '%credential%' and lower(p_message) like '%openai%';
  end is_environment_error;


  /*
   * uc_ai.decide against the API. Null, with a skip message, when the credential
   * is missing. Every other error is raised.
   */
  function decide_live(
    p_state     in clob
  , p_questions in json_object_t
  , p_files     in json_array_t default null
  , p_model     in varchar2 default null
  ) return json_object_t
  as
  begin
    return uc_ai.decide(
      p_state     => p_state
    , p_questions => p_questions
    , p_provider  => uc_ai.c_provider_openai
    , p_model     => p_model
    , p_files     => p_files
    );
  exception
    when others then
      if is_environment_error(sqlerrm) then
        sys.dbms_output.put_line('SKIPPED: the web credential OPENAI is not available here');
        return null;
      end if;
      raise;
  end decide_live;


  procedure triage_example
  as
    l_result  json_object_t;
    l_answers json_object_t;
  begin
    l_result := decide_live(
      'I was charged twice for my order. Please refund the extra charge.'
    , json_object_t.parse(
        '{"department":{"type":"choice","instructions":"Which team should handle this message?","criteria":{'
        || '"billing":"Payments, invoices, and refunds.","support":"Product usage and technical problems.","sales":"New purchases and pricing questions."}}'
        || ',"severity":{"type":"score","instructions":"How severe is the problem described?","criteria":['
        || '"Appearance only; no lost functionality.","Something is broken but the customer can continue.","The customer cannot continue or lost money."]}'
        || ',"wants_refund":{"type":"boolean","instructions":"Does the customer ask for money back?"'
        || ',"criteria":{"true":"The customer asks for a refund or a reimbursement.","false":"The customer does not ask for money back."}}}')
    );

    if l_result is null then
      return;
    end if;

    sys.dbms_output.put_line('Triage: ' || l_result.get_object('answers').to_string);
    l_answers := l_result.get_object('answers');

    ut.expect(l_answers.get_object('department').get_string('choice'), 'department').to_equal('billing');
    ut.expect(l_answers.get_object('department').get_object('probabilities').get_number('billing'), 'billing probability').to_be_greater_than(0.5);
    ut.expect(l_answers.get_object('severity').get_number('score'), 'severity').to_be_greater_or_equal(1);
    ut.expect(l_answers.get_object('severity').get_object('probabilities').get_size, 'one probability per level').to_equal(3);
    ut.expect(l_answers.get_object('wants_refund').get_number('probability'), 'wants_refund').to_be_greater_than(0.5);

    ut.expect(l_result.get_array('warnings').get_size, 'no warnings').to_equal(0);
    ut.expect(l_result.get_string('model'), 'model').to_be_like('gpt-6-luna%');
    ut.expect(l_result.get_object('usage').get_number('input_tokens'), 'input tokens').to_be_greater_than(0);
    ut.expect(l_result.get_object('provider_metadata').get_object('confidence').has('department'), 'confidence').to_be_true();
    ut.expect(l_result.get_object('answers').to_clob, 'no wire names in the answers').not_to_be_like('%predicate%');
  end triage_example;


  procedure image_question
  as
    l_result  json_object_t;
    l_files   json_array_t := json_array_t();
    l_answers json_object_t;
  begin
    l_files.append(uc_ai_message_api.create_file_content('image/png', uc_ai_test_utils.get_apple_png, 'apple.png'));

    l_result := decide_live(
      'The attached picture is the product photo of a listing.'
    , json_object_t.parse(
        '{"shows_fruit":{"type":"boolean","instructions":"The picture shows a fruit."}'
        || ',"object":{"type":"choice","instructions":"What is the main object in the picture?","criteria":{'
        || '"apple":"An apple","car":"A car","house":"A house"}}}')
    , l_files
    );

    if l_result is null then
      return;
    end if;

    sys.dbms_output.put_line('Image: ' || l_result.get_object('answers').to_string);
    l_answers := l_result.get_object('answers');

    ut.expect(l_answers.get_object('shows_fruit').get_number('probability'), 'shows_fruit').to_be_greater_than(0.5);
    ut.expect(l_answers.get_object('object').get_string('choice'), 'object').to_equal('apple');
    ut.expect(l_result.get_array('warnings').get_size, 'no warnings').to_equal(0);
  end image_question;


  procedure bad_model
  as
    l_code    number := 0;
    l_message varchar2(4000 char);
    l_result  json_object_t;
  begin
    begin
      l_result := uc_ai.decide(
        p_state     => 'Hello'
      , p_questions => json_object_t.parse('{"p":{"type":"boolean","instructions":"The text is a greeting."}}')
      , p_provider  => uc_ai.c_provider_openai
      , p_model     => 'gpt-6-nope'
      );
    exception
      when others then
        l_code    := sqlcode;
        l_message := sqlerrm;
    end;

    if is_environment_error(l_message) then
      sys.dbms_output.put_line('SKIPPED: the web credential OPENAI is not available here');
      return;
    end if;

    ut.expect(l_code, 'error code').to_equal(uc_ai_error.c_err_provider_response);
    ut.expect(l_message, 'provider message').to_be_like('%gpt-6-nope%does not exist%');
  end bad_model;

end test_uc_ai_decisions_live;
/
