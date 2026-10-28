create or replace package body test_uc_ai_decisions_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5040): the error tests catch the raised error to assert on its code and message
  -- @dblinter ignore(g-7210): one suite for the whole decisions wire surface; a split would copy the shared builders and try_decide
  -- @dblinter ignore(g-4395): 255 options and 10 levels are the provider limits the tests build
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on its message; a backtrace adds nothing

  -- Named on every call so no request asks uc_ai_get_key for a key.
  c_credential constant varchar2(30 char) := 'WIRE_DECISIONS_CREDENTIAL';

  c_url    constant varchar2(100 char) := 'https://api.openai.com/v1/decisions';
  c_prefix constant varchar2(100 char) := 'openai/decisions/';

  c_ts_url    constant varchar2(100 char) := 'https://api.typesafe.ai/v1/systemone';
  c_ts_prefix constant varchar2(100 char) := 'typesafe/decisions/';

  c_or_url constant varchar2(100 char) := 'https://openrouter.ai/api/alpha/decisions';

  c_or_prefix constant varchar2(100 char) := 'openrouter/decisions/';

  c_triage_state constant varchar2(200 char) := 'I was charged twice for my order. Please refund the extra charge.';

  -- one question of each type, with the ids of the simple hand written responses
  c_q_pred   constant varchar2(500 char) := '{"p":{"type":"boolean","instructions":"Is it?"}}';
  c_q_choice constant varchar2(500 char) := '{"c":{"type":"choice","instructions":"Pick one.","criteria":{"a":"A","b":"B","c":"C"}}}';
  c_q_score  constant varchar2(500 char) := '{"s":{"type":"score","instructions":"Rate it.","criteria":["low","mid","high"]}}';


  -- ---- helpers ---------------------------------------------------------------

  procedure enqueue(p_sample in varchar2)
  as
  begin
    test_uc_ai_wire.enqueue_sample(c_prefix || p_sample);
  end enqueue;


  /*
   * The questions of the recorded triage request in the neutral shape.
   */
  function triage_questions return json_object_t
  as
  begin
    return json_object_t.parse(
      '{"department":{"type":"choice","instructions":"Which team should handle this message?","criteria":{'
      || '"billing":"Payments, invoices, and refunds.","support":"Product usage and technical problems.","sales":"New purchases and pricing questions."}}'
      || ',"severity":{"type":"score","instructions":"How severe is the problem described?","criteria":['
      || '"Appearance only; no lost functionality.","Something is broken but the customer can continue.","The customer cannot continue or lost money."]}'
      || ',"wants_refund":{"type":"boolean","instructions":"The customer asks for money back."}}'
    );
  end triage_questions;


  function decide_triage(p_options in json_object_t default null) return json_object_t
  as
  begin
    return uc_ai.decide(
      p_state     => c_triage_state
    , p_questions => triage_questions
    , p_provider  => uc_ai.c_provider_openai
    , p_options   => p_options
    );
  end decide_triage;


  /*
   * Runs uc_ai.decide and hands back the error a test expects instead of raising
   * it. po_code is 0 when the call did not raise.
   */
  procedure try_decide(
    p_state     in clob
  , p_questions in json_object_t
  , p_files     in json_array_t default null
  , p_options   in json_object_t default null
  , po_code     out number
  , po_message  out varchar2
  )
  as
    l_result json_object_t;
  begin
    po_code := 0;
    l_result := uc_ai.decide(
      p_state     => p_state
    , p_questions => p_questions
    , p_provider  => uc_ai.c_provider_openai
    , p_files     => p_files
    , p_options   => p_options
    );
  exception
    when others then
      po_code    := sqlcode;
      po_message := sqlerrm;
  end try_decide;


  /*
   * A decision with one simple question set against a queued response body.
   */
  procedure try_response(
    p_questions in varchar2
  , p_response  in clob
  , po_code     out number
  , po_message  out varchar2
  , p_status    in pls_integer default 200
  )
  as
  begin
    uc_ai_test_http_mock.enqueue(p_response, p_status);
    try_decide('state', json_object_t.parse(p_questions), null, null, po_code, po_message);
  end try_response;


  function response_of(p_answers in varchar2) return clob
  as
  begin
    return '{"model":"gpt-6-luna","answers":[' || p_answers
        || '],"usage":{"input_tokens":10,"output_tokens":0,"total_tokens":10}}';
  end response_of;


  /*
   * The decision against a hand written response; the result.
   */
  function decide_with(
    p_questions in varchar2
  , p_answers   in varchar2
  ) return json_object_t
  as
  begin
    uc_ai_test_http_mock.enqueue(response_of(p_answers));
    return uc_ai.decide('state', json_object_t.parse(p_questions), uc_ai.c_provider_openai);
  end decide_with;


  procedure expect_format_error(
    p_questions in varchar2
  , p_response  in clob
  , p_like      in varchar2
  , p_label     in varchar2
  )
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    try_response(p_questions, p_response, l_code, l_message);
    ut.expect(l_code, p_label || ': code').to_equal(uc_ai_error.c_err_format_processing);
    ut.expect(l_message, p_label || ': message').to_be_like(p_like);
  end expect_format_error;


  /*
   * The question named p_name in the questions array of request p_index.
   */
  function wire_question(
    p_index in pls_integer
  , p_name  in varchar2
  ) return json_object_t
  as
    l_questions json_array_t := uc_ai_test_http_mock.request_json(p_index).get_array('questions');
    l_question  json_object_t;
  begin
    <<question_loop>>
    for i in 0 .. l_questions.get_size - 1 loop
      l_question := treat(l_questions.get(i) as json_object_t);
      if l_question.get_string('name') = p_name then
        return l_question;
      end if;
    end loop question_loop;

    raise_application_error(-20993, 'no question named ' || p_name || ' in request ' || p_index);
  end wire_question;


  /*
   * The key at a 1-based position; the number of keys.
   */
  function key_at(p_obj in json_object_t, p_pos in pls_integer) return varchar2
  as
    l_keys json_key_list := p_obj.get_keys;
  begin
    return l_keys(p_pos);
  end key_at;


  function key_count(p_obj in json_object_t) return pls_integer
  as
    l_keys json_key_list := p_obj.get_keys;
  begin
    return l_keys.count;
  end key_count;


  function warnings_of(p_result in json_object_t) return json_array_t
  as
  begin
    return p_result.get_array('warnings');
  end warnings_of;


  /*
   * The apple PNG as a file object, as a user builds it.
   */
  function png_file return json_object_t
  as
  begin
    return uc_ai_message_api.create_file_content('image/png', uc_ai_test_utils.get_apple_png, 'apple.png');
  end png_file;


  function files_of(p_file in json_object_t) return json_array_t
  as
    l_files json_array_t := json_array_t();
  begin
    l_files.append(p_file);
    return l_files;
  end files_of;


  function repeat_text(p_char in varchar2, p_length in pls_integer) return clob
  as
    l_text clob;
    l_left pls_integer := p_length;
  begin
    sys.dbms_lob.createtemporary(l_text, true);
    <<chunk_loop>>
    while l_left > 0 loop
      sys.dbms_lob.writeappend(l_text, least(l_left, 4000), rpad(p_char, least(l_left, 4000), p_char));
      l_left := l_left - least(l_left, 4000);
    end loop chunk_loop;
    return l_text;
  end repeat_text;


  -- ---- fixtures --------------------------------------------------------------

  procedure register_mock
  as
  begin
    uc_ai_http.set_transport('uc_ai_test_http_mock');
  end register_mock;


  procedure unregister_mock
  as
  begin
    uc_ai_http.set_transport(null);
    -- reset_state leaves the test credential in the global; do not leak it into later suites
    uc_ai.reset_globals;
  end unregister_mock;


  procedure reset_state
  as
  begin
    uc_ai.reset_globals;
    uc_ai_test_http_mock.reset;
    uc_ai.g_apex_web_credential := c_credential;
  end reset_state;


  -- ---- request shape ---------------------------------------------------------

  procedure url_headers_and_default_model
  as
    l_result json_object_t;
  begin
    enqueue('triage_response');

    l_result := decide_triage;

    test_uc_ai_wire.expect_url(1, c_url);
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('model'), 'default model').to_equal('gpt-6-luna');
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Content-Type'), 'Content-Type').to_equal('application/json');
    ut.expect(uc_ai_test_http_mock.request(1).credential, 'credential name').to_equal(c_credential);
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Authorization'), 'no key header when a credential is named').to_be_null();
    test_uc_ai_wire.expect_all_consumed(1);
  end url_headers_and_default_model;


  procedure base_url_replaces_host
  as
    l_result json_object_t;
  begin
    enqueue('triage_response');
    enqueue('triage_response');

    uc_ai.g_base_url := 'https://proxy.example.test/openai/v1';
    l_result := decide_triage;

    uc_ai.g_base_url := 'https://proxy.example.test/openai/v1/';
    l_result := decide_triage;

    test_uc_ai_wire.expect_url(1, 'https://proxy.example.test/openai/v1/decisions');
    test_uc_ai_wire.expect_url(2, 'https://proxy.example.test/openai/v1/decisions');
    test_uc_ai_wire.expect_all_consumed(2);
  end base_url_replaces_host;


  procedure question_array_shapes
  as
    l_result   json_object_t;
    l_body     json_object_t;
    l_question json_object_t;
    l_choices  json_array_t;
    l_levels   json_array_t;
  begin
    enqueue('triage_response');

    l_result := decide_triage;

    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_body.get_array('questions').get_size, 'question count').to_equal(3);
    ut.expect(l_body.get_string('input'), 'input').to_equal(c_triage_state);

    -- boolean -> predicate: type, name and instructions only
    l_question := wire_question(1, 'wants_refund');
    ut.expect(l_question.get_string('type'), 'predicate type').to_equal('predicate');
    ut.expect(l_question.get_string('instructions'), 'predicate instructions').to_equal('The customer asks for money back.');
    ut.expect(key_count(l_question), 'a predicate has no other key').to_equal(3);

    -- choice: criteria keys become choices with value and description
    l_question := wire_question(1, 'department');
    ut.expect(l_question.get_string('type'), 'choice type').to_equal('choice');
    ut.expect(l_question.get_string('instructions'), 'choice instructions').to_equal('Which team should handle this message?');
    ut.expect(l_question.has('levels'), 'choice has no levels').to_be_false();
    l_choices := l_question.get_array('choices');
    ut.expect(l_choices.get_size, 'choice count').to_equal(3);
    ut.expect(treat(l_choices.get(0) as json_object_t).get_string('value'), 'choice 1 value').to_equal('billing');
    ut.expect(treat(l_choices.get(0) as json_object_t).get_string('description'), 'choice 1 description').to_equal('Payments, invoices, and refunds.');
    ut.expect(treat(l_choices.get(2) as json_object_t).get_string('value'), 'choice 3 value').to_equal('sales');

    -- score: criteria array becomes levels, labelled by the zero-based index
    l_question := wire_question(1, 'severity');
    ut.expect(l_question.get_string('type'), 'score type').to_equal('score');
    ut.expect(l_question.has('choices'), 'score has no choices').to_be_false();
    l_levels := l_question.get_array('levels');
    ut.expect(l_levels.get_size, 'level count').to_equal(3);
    ut.expect(treat(l_levels.get(0) as json_object_t).get_string('label'), 'level 1 label').to_equal('0');
    ut.expect(treat(l_levels.get(2) as json_object_t).get_string('label'), 'level 3 label').to_equal('2');
    ut.expect(treat(l_levels.get(2) as json_object_t).get_string('description'), 'level 3 description').to_equal('The customer cannot continue or lost money.');

    test_uc_ai_wire.expect_all_consumed(1);
  end question_array_shapes;


  procedure question_order_follows_keys
  as
    l_result    json_object_t;
    l_questions json_array_t;
  begin
    -- not in alphabetical order
    uc_ai_test_http_mock.enqueue(response_of(
      '{"type":"predicate","name":"zeta","probability":0.5}'
      || ',{"type":"predicate","name":"alpha","probability":0.5}'
      || ',{"type":"predicate","name":"mid","probability":0.5}'));

    l_result := uc_ai.decide(
      'state'
    , json_object_t.parse(
        '{"zeta":{"type":"boolean","instructions":"1"},"alpha":{"type":"boolean","instructions":"2"},"mid":{"type":"boolean","instructions":"3"}}')
    , uc_ai.c_provider_openai);

    l_questions := uc_ai_test_http_mock.request_json(1).get_array('questions');
    ut.expect(treat(l_questions.get(0) as json_object_t).get_string('name'), 'first').to_equal('zeta');
    ut.expect(treat(l_questions.get(1) as json_object_t).get_string('name'), 'second').to_equal('alpha');
    ut.expect(treat(l_questions.get(2) as json_object_t).get_string('name'), 'third').to_equal('mid');
    ut.expect(key_at(l_result.get_object('answers'), 1), 'answers keep the order').to_equal('zeta');
  end question_order_follows_keys;


  procedure optional_descriptions_omitted
  as
    l_result  json_object_t;
    l_choices json_array_t;
    l_levels  json_array_t;
  begin
    enqueue('variants_response');

    l_result := uc_ai.decide(
      'state'
    , json_object_t.parse(
        '{"area":{"type":"choice","instructions":"a","criteria":{"ui":null,"backend":"","docs":"Documentation"}}'
        || ',"urgent":{"type":"score","instructions":"b","criteria":[null,"Yes"]}'
        || ',"is_bug":{"type":"boolean","instructions":"c"}}')
    , uc_ai.c_provider_openai);

    l_choices := wire_question(1, 'area').get_array('choices');
    ut.expect(treat(l_choices.get(0) as json_object_t).has('description'), 'null description').to_be_false();
    ut.expect(treat(l_choices.get(1) as json_object_t).has('description'), 'empty description').to_be_false();
    ut.expect(treat(l_choices.get(2) as json_object_t).get_string('description'), 'given description').to_equal('Documentation');

    l_levels := wire_question(1, 'urgent').get_array('levels');
    ut.expect(treat(l_levels.get(0) as json_object_t).has('description'), 'null level description').to_be_false();
    ut.expect(treat(l_levels.get(1) as json_object_t).get_string('description'), 'level description').to_equal('Yes');

    -- a level that is only white space gets no description either
    enqueue('score_and_predicate_response');
    l_result := uc_ai.decide(
      'state'
    , json_object_t.parse(
        '{"selfharm":{"type":"boolean","instructions":"a"}'
        || ',"risk":{"type":"score","instructions":"b","criteria":["  ","","Immediate"]}}')
    , uc_ai.c_provider_openai);
    l_levels := wire_question(2, 'risk').get_array('levels');
    ut.expect(treat(l_levels.get(0) as json_object_t).has('description'), 'blank level description').to_be_false();
    ut.expect(treat(l_levels.get(1) as json_object_t).has('description'), 'empty level description').to_be_false();
    ut.expect(treat(l_levels.get(2) as json_object_t).get_string('description'), 'third level description').to_equal('Immediate');
  end optional_descriptions_omitted;


  procedure predicate_criteria_folded
  as
    l_result json_object_t;

    -- the triage questions with another wants_refund question, so that the
    -- recorded triage response still fits
    function with_refund(p_question in varchar2) return json_object_t
    as
      l_questions json_object_t := triage_questions;
    begin
      l_questions.put('wants_refund', json_object_t.parse(p_question));
      return l_questions;
    end with_refund;
  begin
    enqueue('triage_response');
    enqueue('triage_response');
    enqueue('triage_response');

    l_result := uc_ai.decide(
      'state'
    , with_refund('{"type":"boolean","instructions":"Is the customer asking for money back?"'
        || ',"criteria":{"true":"They want a refund.","false":"They ask a question."}}')
    , uc_ai.c_provider_openai);

    ut.expect(wire_question(1, 'wants_refund').get_string('instructions'), 'both criteria').to_equal(
      'Is the customer asking for money back?' || chr(10) || chr(10)
      || 'Criteria for true:' || chr(10) || 'They want a refund.' || chr(10) || chr(10)
      || 'Criteria for false:' || chr(10) || 'They ask a question.');
    ut.expect(key_count(wire_question(1, 'wants_refund')), 'the criteria are not a key of the predicate').to_equal(3);

    -- only one criterion given, the other empty
    l_result := uc_ai.decide(
      'state'
    , with_refund('{"type":"boolean","instructions":"Q?","criteria":{"false":"Only this.","true":""}}')
    , uc_ai.c_provider_openai);
    ut.expect(wire_question(2, 'wants_refund').get_string('instructions'), 'one criterion').to_equal(
      'Q?' || chr(10) || chr(10) || 'Criteria for false:' || chr(10) || 'Only this.');

    -- no criteria: the instructions are sent as they are
    l_result := uc_ai.decide(
      'state'
    , with_refund('{"type":"boolean","instructions":"Q?","criteria":{}}')
    , uc_ai.c_provider_openai);
    ut.expect(wire_question(3, 'wants_refund').get_string('instructions'), 'no criteria').to_equal('Q?');
  end predicate_criteria_folded;


  procedure text_state_is_plain_string
  as
    l_result json_object_t;
  begin
    enqueue('triage_response');

    l_result := decide_triage;

    ut.expect(uc_ai_test_http_mock.request_json(1).get('input').is_string, 'input is a string').to_be_true();
  end text_state_is_plain_string;


  procedure long_texts_reach_the_request
  as
    l_result  json_object_t;
    l_state   clob := repeat_text('s', 60000);
    l_instr   clob := repeat_text('i', 40000);
    l_desc    clob := repeat_text('d', 40000);
    l_q       json_object_t := json_object_t();
    l_question json_object_t;
    l_criteria json_object_t := json_object_t();
    l_body    json_object_t;
  begin

    l_criteria.put('a', l_desc);
    l_criteria.put('b', 'B');
    l_question := json_object_t();
    l_question.put('type', 'choice');
    l_question.put('instructions', l_instr);
    l_question.put('criteria', l_criteria);
    l_q.put('c', l_question);

    uc_ai_test_http_mock.enqueue(response_of('{"type":"choice","name":"c","choice":"a","probabilities":[{"value":"a","probability":0.9},{"value":"b","probability":0.1}],"confidence":0.9}'));
    l_result := uc_ai.decide(l_state, l_q, uc_ai.c_provider_openai);

    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(sys.dbms_lob.getlength(l_body.get_clob('input')), 'state length').to_equal(60000);
    ut.expect(sys.dbms_lob.getlength(wire_question(1, 'c').get_clob('instructions')), 'instructions length').to_equal(40000);
    ut.expect(
      sys.dbms_lob.getlength(treat(wire_question(1, 'c').get_array('choices').get(0) as json_object_t).get_clob('description'))
    , 'description length').to_equal(40000);
  end long_texts_reach_the_request;


  procedure image_becomes_message_array
  as
    l_result  json_object_t;
    l_input   json_array_t;
    l_content json_array_t;
    l_file    json_object_t := png_file;
    l_url     clob;
    c_head    constant varchar2(100 char) := 'data:image/png;base64,';
  begin
    enqueue('image_response');

    l_result := uc_ai.decide(
      'The attached scan is the customer''s request.'
    , json_object_t.parse(
        '{"topic":{"type":"choice","instructions":"What does the document say?","criteria":{"refund":"The word REFUND appears","invoice":"The word INVOICE appears","other":null}}'
        || ',"has_number_42":{"type":"boolean","instructions":"The document contains the number 42."}}')
    , uc_ai.c_provider_openai
    , p_files => files_of(l_file));

    ut.expect(uc_ai_test_http_mock.request_json(1).get('input').is_array, 'input is an array').to_be_true();
    l_input := uc_ai_test_http_mock.request_json(1).get_array('input');
    ut.expect(l_input.get_size, 'one user message').to_equal(1);
    ut.expect(treat(l_input.get(0) as json_object_t).get_string('role'), 'role').to_equal('user');

    l_content := treat(l_input.get(0) as json_object_t).get_array('content');
    ut.expect(l_content.get_size, 'text and image part').to_equal(2);
    ut.expect(treat(l_content.get(0) as json_object_t).get_string('type'), 'part 1 type').to_equal('input_text');
    ut.expect(treat(l_content.get(0) as json_object_t).get_string('text'), 'part 1 text').to_equal('The attached scan is the customer''s request.');
    ut.expect(treat(l_content.get(1) as json_object_t).get_string('type'), 'part 2 type').to_equal('input_image');

    -- image_url is a plain string with the data URL, as in the recorded request
    ut.expect(treat(l_content.get(1) as json_object_t).get('image_url').is_string, 'image_url is a string').to_be_true();
    l_url := treat(l_content.get(1) as json_object_t).get_clob('image_url');
    ut.expect(sys.dbms_lob.substr(l_url, length(c_head), 1), 'data URL head').to_equal(c_head);
    ut.expect(
      sys.dbms_lob.compare(l_url, c_head || l_file.get_clob('data'))
    , 'the data URL carries the base64 of the file').to_equal(0);

    -- the recorded request was built the same way
    ut.expect(
      treat(treat(uc_ai_test_samples.get_json(c_prefix || 'image_request').get_array('input').get(0) as json_object_t)
              .get_array('content').get(1) as json_object_t).get_string('type')
    , 'recorded request uses the same part type').to_equal('input_image');
    test_uc_ai_wire.expect_all_consumed(1);
  end image_becomes_message_array;


  procedure image_only_has_no_text_part
  as
    l_result  json_object_t;
    l_content json_array_t;
  begin
    enqueue('image_only_response');

    l_result := uc_ai.decide(
      null
    , json_object_t.parse('{"topic":{"type":"choice","instructions":"What?","criteria":{"refund":"r","invoice":"i","other":"o"}},"has_number_42":{"type":"boolean","instructions":"42?"}}')
    , uc_ai.c_provider_openai
    , p_files => files_of(png_file));

    l_content := treat(uc_ai_test_http_mock.request_json(1).get_array('input').get(0) as json_object_t).get_array('content');
    ut.expect(l_content.get_size, 'only the image').to_equal(1);
    ut.expect(treat(l_content.get(0) as json_object_t).get_string('type'), 'part type').to_equal('input_image');
  end image_only_has_no_text_part;


  procedure several_images_and_media_types
  as
    l_result  json_object_t;
    l_files   json_array_t := json_array_t();
    l_content json_array_t;
    l_b64     clob;
  begin
    enqueue('two_images_response');

    -- base64 with line breaks, as a caller with newlines on can produce
    l_b64 := apex_web_service.blob2clobbase64(uc_ai_test_utils.get_apple_png, 'Y', 'Y');
    ut.expect(instr(l_b64, chr(10)), 'the test data has line breaks').to_be_greater_than(0);

    l_files.append(uc_ai_message_api.create_file_content(' Image/JPG; charset=binary ', l_b64, 'a.jpg'));
    l_files.append(uc_ai_message_api.create_file_content('image/webp', uc_ai_test_utils.get_apple_webp, 'b.webp'));

    l_result := uc_ai.decide('Two images.', json_object_t.parse(c_q_pred), uc_ai.c_provider_openai, p_files => l_files);

    l_content := treat(uc_ai_test_http_mock.request_json(1).get_array('input').get(0) as json_object_t).get_array('content');
    ut.expect(l_content.get_size, 'text and two images').to_equal(3);
    ut.expect(sys.dbms_lob.substr(treat(l_content.get(1) as json_object_t).get_clob('image_url'), 23, 1), 'jpeg alias and parameters').to_equal('data:image/jpeg;base64,');
    ut.expect(sys.dbms_lob.substr(treat(l_content.get(2) as json_object_t).get_clob('image_url'), 23, 1), 'webp').to_equal('data:image/webp;base64,');
    ut.expect(instr(treat(l_content.get(1) as json_object_t).get_clob('image_url'), chr(10)), 'no line breaks in the data URL').to_equal(0);
    ut.expect(instr(treat(l_content.get(1) as json_object_t).get_clob('image_url'), chr(13)), 'no carriage returns in the data URL').to_equal(0);
  end several_images_and_media_types;


  procedure safety_identifier_and_extra_body
  as
    l_result json_object_t;
    l_body   json_object_t;
  begin
    enqueue('triage_response');

    l_result := decide_triage(json_object_t.parse(
      '{"safety_identifier":"user-4711","extra_body":{"future_key":true,"model":"evil","input":"evil","questions":[]}}'));

    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_body.get_string('safety_identifier'), 'safety_identifier').to_equal('user-4711');
    ut.expect(l_body.get_boolean('future_key'), 'extra_body key').to_be_true();
    ut.expect(l_body.get_string('model'), 'model wins').to_equal('gpt-6-luna');
    ut.expect(l_body.get_string('input'), 'input wins').to_equal(c_triage_state);
    ut.expect(l_body.get_array('questions').get_size, 'questions win').to_equal(3);
    ut.expect(l_body.has('extra_body'), 'no extra_body key in the request').to_be_false();
    ut.expect(warnings_of(l_result).get_size, 'both options are known').to_equal(0);
  end safety_identifier_and_extra_body;


  procedure unknown_option_warns
  as
    l_result json_object_t;
  begin
    enqueue('triage_response');

    l_result := decide_triage(json_object_t.parse('{"temperature":0,"safety_identifier":"u"}'));

    ut.expect(uc_ai_test_http_mock.request_json(1).has('temperature'), 'unknown option is not sent').to_be_false();
    ut.expect(warnings_of(l_result).get_size, 'one warning').to_equal(1);
    ut.expect(warnings_of(l_result).get_string(0), 'warning text').to_be_like('%temperature%not supported%');
  end unknown_option_warns;


  procedure unknown_question_key_warns
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(response_of('{"type":"predicate","name":"p","probability":0.5}'));

    l_result := uc_ai.decide(
      'state'
    , json_object_t.parse('{"p":{"type":"boolean","instructions":"Is it?","critera":{"true":"typo"}}}')
    , uc_ai.c_provider_openai);

    ut.expect(warnings_of(l_result).get_size, 'one warning').to_equal(1);
    ut.expect(warnings_of(l_result).get_string(0), 'warning text').to_be_like('%"p"%critera%');
    ut.expect(wire_question(1, 'p').has('critera'), 'the key is not sent').to_be_false();
  end unknown_question_key_warns;


  procedure edge_ids_and_option_names
  as
    l_result   json_object_t;
    l_id       varchar2(64 char) := 'a' || rpad('b', 63, 'b');
    l_options  json_object_t := json_object_t();
    l_question json_object_t := json_object_t();
    l_questions json_object_t := json_object_t();
  begin
    -- 255 options: cat_1 .. cat_254 and invoice, as in the recorded response
    <<option_loop>>
    for i in 1 .. 254 loop
      l_options.put('cat_' || i, case when i = 1 then 'The first one' end);
    end loop option_loop;
    l_options.put('invoice', 'The invoice');
    l_question.put('type', 'choice');
    l_question.put('instructions', 'Which category?');
    l_question.put('criteria', l_options);
    l_questions.put('c', l_question);

    enqueue('choices_255_response');
    l_result := uc_ai.decide('state', l_questions, uc_ai.c_provider_openai);
    ut.expect(l_result.get_object('answers').get_object('c').get_string('choice'), '255 options: choice').to_equal('invoice');
    ut.expect(l_result.get_object('answers').get_object('c').get_object('probabilities').get_size, '255 options: probabilities').to_equal(255);
    ut.expect(warnings_of(l_result).get_size, '255 options: no warnings').to_equal(0);
    ut.expect(wire_question(1, 'c').get_array('choices').get_size, '255 options sent').to_equal(255);

    -- the longest id, and an option name with a dot, a bracket and a space
    uc_ai_test_http_mock.enqueue(response_of(
      '{"type":"choice","name":"' || l_id || '","choice":"a.b[0] c","probabilities":[{"value":"a.b[0] c","probability":0.7},{"value":"x","probability":0.3}],"confidence":0.7}'));
    l_result := uc_ai.decide(
      'state'
    , json_object_t.parse('{"' || l_id || '":{"type":"choice","instructions":"i","criteria":{"a.b[0] c":"d","x":"y"}}}')
    , uc_ai.c_provider_openai);
    ut.expect(l_result.get_object('answers').get_object(l_id).get_string('choice'), 'odd option name').to_equal('a.b[0] c');
    ut.expect(l_result.get_object('answers').get_object(l_id).get_object('probabilities').get_number('a.b[0] c'), 'odd option probability').to_equal(0.7);
  end edge_ids_and_option_names;


  procedure ten_levels_work
  as
    l_result json_object_t;
    l_levels json_array_t := json_array_t();
    l_q      json_object_t := json_object_t();
    l_item   json_object_t := json_object_t();
  begin
    <<level_loop>>
    for i in 0 .. 9 loop
      l_levels.append('L' || i);
    end loop level_loop;
    l_item.put('type', 'score');
    l_item.put('instructions', 'Rate the severity.');
    l_item.put('criteria', l_levels);
    l_q.put('s', l_item);

    enqueue('levels_10_response');
    l_result := uc_ai.decide('The site is down for all customers.', l_q, uc_ai.c_provider_openai);

    ut.expect(l_result.get_object('answers').get_object('s').get_number('score'), 'score').to_equal(4.39);
    ut.expect(l_result.get_object('answers').get_object('s').get_object('probabilities').get_size, 'ten probabilities').to_equal(10);
    ut.expect(warnings_of(l_result).get_size, 'the recorded score is the weighted mean').to_equal(0);
    ut.expect(wire_question(1, 's').get_array('levels').get_size, 'ten levels sent').to_equal(10);
  end ten_levels_work;


  -- ---- response mapping --------------------------------------------------------

  procedure triage_result_is_neutral
  as
    l_result  json_object_t;
    l_answers json_object_t;
  begin
    enqueue('triage_response');

    l_result := decide_triage;
    l_answers := l_result.get_object('answers');

    ut.expect(l_answers.get_size, 'three answers').to_equal(3);

    ut.expect(l_answers.get_object('department').get_string('type'), 'department type').to_equal('choice');
    ut.expect(l_answers.get_object('department').get_string('choice'), 'department choice').to_equal('billing');

    ut.expect(l_answers.get_object('severity').get_string('type'), 'severity type').to_equal('score');
    ut.expect(l_answers.get_object('severity').get_number('score'), 'severity score').to_equal(1.97);

    ut.expect(l_answers.get_object('wants_refund').get_string('type'), 'wants_refund type').to_equal('boolean');
    ut.expect(l_answers.get_object('wants_refund').get_number('probability'), 'wants_refund probability').to_equal(1);

    ut.expect(warnings_of(l_result).get_size, 'no warnings on a real response').to_equal(0);
  end triage_result_is_neutral;


  procedure predicate_name_never_in_result
  as
    l_result json_object_t;
  begin
    enqueue('triage_response');

    l_result := decide_triage;

    -- raw is the provider response as returned and keeps the wire name; nothing else may
    ut.expect(l_result.get_object('answers').to_clob, 'answers').not_to_be_like('%predicate%');
    ut.expect(l_result.get_object('usage').to_clob, 'usage').not_to_be_like('%predicate%');
    ut.expect(l_result.get_object('provider_metadata').to_clob, 'provider_metadata').not_to_be_like('%predicate%');
    ut.expect(l_result.get_array('warnings').to_clob, 'warnings').not_to_be_like('%predicate%');
    ut.expect(l_result.get_string('model'), 'model').not_to_be_like('%predicate%');
  end predicate_name_never_in_result;


  procedure choice_probabilities_object
  as
    l_result json_object_t;
    l_probs  json_object_t;
  begin

    l_result := decide_with(c_q_choice,
      '{"type":"choice","name":"c","choice":"b","probabilities":[{"value":"a","probability":0.1},{"value":"b","probability":0.75},{"value":"c","probability":0.15}],"confidence":0.8}');

    l_probs := l_result.get_object('answers').get_object('c').get_object('probabilities');
    ut.expect(l_probs.get_size, 'one entry per option').to_equal(3);
    ut.expect(l_probs.get_number('a'), 'a').to_equal(0.1);
    ut.expect(l_probs.get_number('b'), 'b').to_equal(0.75);
    ut.expect(l_probs.get_number('c'), 'c').to_equal(0.15);
    ut.expect(l_result.get_object('answers').get_object('c').get_string('choice'), 'choice').to_equal('b');
  end choice_probabilities_object;


  procedure score_probabilities_keyed_by_index
  as
    l_result json_object_t;
    l_probs  json_object_t;
  begin
    l_result := decide_with(c_q_score,
      '{"type":"score","name":"s","score":1.2,"probabilities":[{"value":0,"label":"0","probability":0.1},{"value":1,"label":"1","probability":0.6},{"value":2,"label":"2","probability":0.3}],"confidence":0.7}');

    l_probs := l_result.get_object('answers').get_object('s').get_object('probabilities');
    ut.expect(key_at(l_probs, 1), 'first key').to_equal('0');
    ut.expect(key_at(l_probs, 2), 'second key').to_equal('1');
    ut.expect(key_at(l_probs, 3), 'third key').to_equal('2');
    ut.expect(l_probs.get_number('1'), 'level 1').to_equal(0.6);
    ut.expect(l_probs.has('label'), 'the label is dropped').to_be_false();
    ut.expect(l_result.get_object('answers').get_object('s').get_number('score'), 'score').to_equal(1.2);
    ut.expect(warnings_of(l_result).get_size, '0*0.1 + 1*0.6 + 2*0.3 = 1.2, so no warning').to_equal(0);
  end score_probabilities_keyed_by_index;


  procedure confidence_in_provider_metadata
  as
    l_result     json_object_t;
    l_confidence json_object_t;
  begin
    enqueue('triage_response');

    l_result := decide_triage;

    l_confidence := l_result.get_object('provider_metadata').get_object('confidence');
    ut.expect(l_confidence.get_number('department'), 'department').to_equal(1);
    ut.expect(l_confidence.get_number('severity'), 'severity').to_equal(0.96);
    ut.expect(l_confidence.has('wants_refund'), 'a boolean answer has no confidence').to_be_false();
    ut.expect(l_result.get_object('answers').get_object('department').has('confidence'), 'confidence is not part of the answer').to_be_false();
  end confidence_in_provider_metadata;


  procedure usage_is_mapped
  as
    l_result json_object_t;
    l_usage  json_object_t;
  begin
    enqueue('triage_response');

    l_result := decide_triage;

    l_usage := l_result.get_object('usage');
    ut.expect(l_usage.get_number('input_tokens'), 'input_tokens').to_equal(429);
    ut.expect(l_usage.get_number('output_tokens'), 'output_tokens').to_equal(0);
    ut.expect(l_usage.get_number('total_tokens'), 'total_tokens').to_equal(429);
    ut.expect(
      l_result.get_object('provider_metadata').get_object('usage').get_object('input_tokens_details').get_number('cached_tokens')
    , 'the provider usage object is kept').to_equal(0);

    -- a response without usage gives an empty usage object
    l_result := decide_with(c_q_pred, '{"type":"predicate","name":"p","probability":0.5}');
    ut.expect(l_result.get_object('usage').get_number('input_tokens'), 'input_tokens of a short usage').to_equal(10);

    uc_ai_test_http_mock.enqueue('{"model":"gpt-6-luna","answers":[{"type":"predicate","name":"p","probability":0.5}]}');
    l_result := uc_ai.decide('state', json_object_t.parse(c_q_pred), uc_ai.c_provider_openai);
    ut.expect(l_result.get_object('usage').get_size, 'no usage reported, no usage keys').to_equal(0);
    ut.expect(l_result.get_object('provider_metadata').has('usage'), 'no usage in provider_metadata').to_be_false();
  end usage_is_mapped;


  procedure model_and_raw
  as
    l_result json_object_t;
  begin
    enqueue('triage_response');

    l_result := decide_triage;

    ut.expect(l_result.get_string('model'), 'model').to_equal('gpt-6-luna');
    ut.expect(l_result.get_object('raw'), 'raw equals the provider response').to_equal(uc_ai_test_samples.get_json(c_prefix || 'triage_response'));

    -- the model of the response wins over the requested one
    uc_ai_test_http_mock.enqueue('{"model":"gpt-6-luna-2026-10-01","answers":[{"type":"predicate","name":"p","probability":0.5}]}');
    l_result := uc_ai.decide('state', json_object_t.parse(c_q_pred), uc_ai.c_provider_openai, 'gpt-6-luna');
    ut.expect(l_result.get_string('model'), 'reported model').to_equal('gpt-6-luna-2026-10-01');
    ut.expect(uc_ai_test_http_mock.request_json(2).get_string('model'), 'requested model').to_equal('gpt-6-luna');
  end model_and_raw;


  procedure recorded_samples_map
  as
    l_result json_object_t;
  begin
    -- image_response: choice with a null description and a predicate
    enqueue('image_response');
    l_result := uc_ai.decide(
      'The attached scan is the customer''s request.'
    , json_object_t.parse(
        '{"topic":{"type":"choice","instructions":"i","criteria":{"refund":"r","invoice":"i","other":null}}'
        || ',"has_number_42":{"type":"boolean","instructions":"b"}}')
    , uc_ai.c_provider_openai
    , p_files => files_of(png_file));
    ut.expect(l_result.get_object('answers').get_object('topic').get_string('choice'), 'image: choice').to_equal('refund');
    ut.expect(warnings_of(l_result).get_size, 'image: warnings').to_equal(0);

    -- variants_response: two levels
    enqueue('variants_response');
    l_result := uc_ai.decide(
      'The login page shows a typo in the footer.'
    , json_object_t.parse(
        '{"area":{"type":"choice","instructions":"a","criteria":{"ui":null,"backend":null,"docs":null}}'
        || ',"urgent":{"type":"score","instructions":"b","criteria":["No","Yes"]}'
        || ',"is_bug":{"type":"boolean","instructions":"c"}}')
    , uc_ai.c_provider_openai);
    ut.expect(l_result.get_object('answers').get_object('urgent').get_number('score'), 'variants: score').to_equal(0);
    ut.expect(warnings_of(l_result).get_size, 'variants: warnings').to_equal(0);

    -- score_and_predicate_response: the predicate comes first
    enqueue('score_and_predicate_response');
    l_result := uc_ai.decide(
      'text'
    , json_object_t.parse(
        '{"selfharm":{"type":"boolean","instructions":"a"}'
        || ',"risk":{"type":"score","instructions":"b","criteria":["None","Soon","Immediate"]}}')
    , uc_ai.c_provider_openai);
    ut.expect(l_result.get_object('answers').get_object('risk').get_number('score'), 'score_and_predicate: score').to_equal(2);
    ut.expect(l_result.get_object('answers').get_object('selfharm').get_number('probability'), 'score_and_predicate: probability').to_equal(1);
    ut.expect(warnings_of(l_result).get_size, 'score_and_predicate: warnings').to_equal(0);

    -- two_images_response and message_array_text_response: one predicate each
    enqueue('two_images_response');
    l_result := uc_ai.decide('t', json_object_t.parse('{"p":{"type":"boolean","instructions":"b"}}'), uc_ai.c_provider_openai);
    ut.expect(l_result.get_object('answers').get_object('p').get_number('probability'), 'two_images: probability').to_equal(1);

    enqueue('message_array_text_response');
    l_result := uc_ai.decide('t', json_object_t.parse('{"refund":{"type":"boolean","instructions":"b"}}'), uc_ai.c_provider_openai);
    ut.expect(l_result.get_object('answers').get_object('refund').get_number('probability'), 'message_array_text: probability').to_equal(1);

    test_uc_ai_wire.expect_all_consumed(5);
  end recorded_samples_map;


  procedure missing_probabilities_are_fine
  as
    l_result json_object_t;
  begin
    l_result := decide_with(c_q_choice, '{"type":"choice","name":"c","choice":"a"}');
    ut.expect(l_result.get_object('answers').get_object('c').get_string('choice'), 'choice').to_equal('a');
    ut.expect(l_result.get_object('answers').get_object('c').has('probabilities'), 'no probabilities').to_be_false();
    ut.expect(warnings_of(l_result).get_size, 'no warning').to_equal(0);

    l_result := decide_with(c_q_score, '{"type":"score","name":"s","score":2}');
    ut.expect(l_result.get_object('answers').get_object('s').get_number('score'), 'score').to_equal(2);
    ut.expect(l_result.get_object('answers').get_object('s').has('probabilities'), 'no score probabilities').to_be_false();
    ut.expect(warnings_of(l_result).get_size, 'no warning for the score').to_equal(0);
  end missing_probabilities_are_fine;


  -- ---- refusal -------------------------------------------------------------------

  /*
   * The recorded refusal: "gay" is refused, the sibling "religion" is answered.
   */
  function refusal_questions return json_object_t
  as
  begin
    return json_object_t.parse(
      '{"gay":{"type":"boolean","instructions":"The author is gay."}'
      || ',"religion":{"type":"choice","instructions":"What is the author''s religion?","criteria":{"christian":null,"muslim":null,"jewish":null,"none":null}}}');
  end refusal_questions;


  procedure refusal_keeps_sibling_answer
  as
    l_result  json_object_t;
    l_answers json_object_t;
  begin
    enqueue('refusal_response');

    l_result := uc_ai.decide(
      'I love cooking pasta with my partner on Sundays and we just adopted a dog.'
    , refusal_questions
    , uc_ai.c_provider_openai);

    l_answers := l_result.get_object('answers');
    ut.expect(l_answers.get_size, 'both questions have an answer').to_equal(2);

    -- the refused question has the type and nothing else
    ut.expect(l_answers.get_object('gay').get_string('type'), 'refused type').to_equal('refused');
    ut.expect(key_count(l_answers.get_object('gay')), 'a refused answer has only a type').to_equal(1);

    -- the sibling is a normal choice answer
    ut.expect(l_answers.get_object('religion').get_string('type'), 'sibling type').to_equal('choice');
    ut.expect(l_answers.get_object('religion').get_string('choice'), 'sibling choice').to_equal('none');
    ut.expect(l_answers.get_object('religion').get_object('probabilities').get_number('none'), 'sibling probability').to_equal(0.97);

    ut.expect(warnings_of(l_result).get_size, 'a refusal gives no warning').to_equal(0);
    test_uc_ai_wire.expect_all_consumed(1);
  end refusal_keeps_sibling_answer;


  procedure refusal_among_valid_answers
  as
    l_result json_object_t;
  begin
    enqueue('refusal_illposed_response');

    l_result := uc_ai.decide(
      'The site is down for all customers.'
    , json_object_t.parse(
        '{"lottery":{"type":"boolean","instructions":"Will the next Euromillions draw contain the number 7?"}'
        || ',"nonsense":{"type":"choice","instructions":"Pick the colour of the number seven''s smell.","criteria":{"red":null,"blue":null}}}')
    , uc_ai.c_provider_openai);

    ut.expect(l_result.get_object('answers').get_object('lottery').get_string('type'), 'answered type').to_equal('boolean');
    ut.expect(l_result.get_object('answers').get_object('lottery').get_number('probability'), 'answered probability').to_equal(0.47);
    ut.expect(l_result.get_object('answers').get_object('nonsense').get_string('type'), 'refused type').to_equal('refused');
    ut.expect(l_result.get_object('answers').get_object('nonsense').has('choice'), 'a refused answer has no choice').to_be_false();
    ut.expect(warnings_of(l_result).get_size, 'no warning').to_equal(0);
    ut.expect(l_result.get_object('usage').get_number('input_tokens'), 'usage is still mapped').to_equal(277);
  end refusal_among_valid_answers;


  procedure all_questions_refused
  as
    l_result json_object_t;
  begin
    -- the recorded response: the only question is refused
    enqueue('refusal_empty_instructions_response');
    l_result := uc_ai.decide('The site is down.', json_object_t.parse('{"e":{"type":"boolean","instructions":"Is it?"}}'), uc_ai.c_provider_openai);
    ut.expect(l_result.get_object('answers').get_object('e').get_string('type'), 'recorded: refused').to_equal('refused');
    ut.expect(warnings_of(l_result).get_size, 'recorded: no warning').to_equal(0);
    ut.expect(l_result.get_object('usage').get_number('input_tokens'), 'recorded: usage').to_equal(153);

    -- three questions, three refusals
    l_result := decide_with(
      '{"a":{"type":"boolean","instructions":"x"},"b":{"type":"choice","instructions":"y","criteria":{"u":null,"v":null}},"c":{"type":"score","instructions":"z","criteria":["l","h"]}}'
    , '{"type":"refusal","name":"a"},{"type":"refusal","name":"b"},{"type":"refusal","name":"c"}');
    ut.expect(l_result.get_object('answers').get_size, 'three answers').to_equal(3);
    ut.expect(l_result.get_object('answers').get_object('a').get_string('type'), 'a').to_equal('refused');
    ut.expect(l_result.get_object('answers').get_object('b').get_string('type'), 'b').to_equal('refused');
    ut.expect(l_result.get_object('answers').get_object('c').get_string('type'), 'c').to_equal('refused');
    ut.expect(l_result.get_object('provider_metadata').has('confidence'), 'no confidence at all').to_be_false();
  end all_questions_refused;


  procedure mixed_refusal_mapping
  as
    l_result  json_object_t;
    l_answers json_object_t;
  begin
    -- the refusal is in the middle; the answers come back in question order
    l_result := decide_with(
      '{"flag":{"type":"boolean","instructions":"x"},"skip":{"type":"choice","instructions":"y","criteria":{"u":null,"v":null}}'
      || ',"sev":{"type":"score","instructions":"z","criteria":["low","mid","high"]}'
      || ',"pick":{"type":"choice","instructions":"w","criteria":{"a":null,"b":null}}}'
    , '{"type":"predicate","name":"flag","probability":0.8}'
      || ',{"type":"refusal","name":"skip"}'
      || ',{"type":"score","name":"sev","score":1.2,"probabilities":[{"value":0,"label":"0","probability":0.1},{"value":1,"label":"1","probability":0.6},{"value":2,"label":"2","probability":0.3}],"confidence":0.7}'
      || ',{"type":"choice","name":"pick","choice":"b","probabilities":[{"value":"a","probability":0.25},{"value":"b","probability":0.75}],"confidence":0.55}');

    l_answers := l_result.get_object('answers');
    ut.expect(l_answers.get_size, 'four answers').to_equal(4);
    ut.expect(key_at(l_answers, 1), 'first id').to_equal('flag');
    ut.expect(key_at(l_answers, 2), 'second id').to_equal('skip');
    ut.expect(key_at(l_answers, 4), 'last id').to_equal('pick');

    ut.expect(l_answers.get_object('flag').get_number('probability'), 'boolean').to_equal(0.8);
    ut.expect(l_answers.get_object('skip').get_string('type'), 'refused').to_equal('refused');
    ut.expect(l_answers.get_object('sev').get_number('score'), 'score').to_equal(1.2);
    ut.expect(l_answers.get_object('sev').get_object('probabilities').get_number('1'), 'score probability').to_equal(0.6);
    ut.expect(l_answers.get_object('pick').get_string('choice'), 'choice').to_equal('b');
    ut.expect(l_answers.get_object('pick').get_object('probabilities').get_number('b'), 'choice probability').to_equal(0.75);

    -- confidence for the answered questions only
    ut.expect(l_result.get_object('provider_metadata').get_object('confidence').get_number('sev'), 'sev confidence').to_equal(0.7);
    ut.expect(l_result.get_object('provider_metadata').get_object('confidence').get_number('pick'), 'pick confidence').to_equal(0.55);
    ut.expect(key_count(l_result.get_object('provider_metadata').get_object('confidence')), 'no confidence for the refused question').to_equal(2);

    -- the distribution checks still run for the answered questions
    ut.expect(warnings_of(l_result).get_size, 'no warning').to_equal(0);
    l_result := decide_with(
      '{"skip":{"type":"boolean","instructions":"y"},"pick":{"type":"choice","instructions":"w","criteria":{"a":null,"b":null}}}'
    , '{"type":"refusal","name":"skip"},{"type":"choice","name":"pick","choice":"a","probabilities":[{"value":"a","probability":0.25},{"value":"b","probability":0.25}]}');
    ut.expect(warnings_of(l_result).get_size, 'a sum that is not 1 still warns next to a refusal').to_equal(1);
  end mixed_refusal_mapping;


  procedure refusal_still_counts_as_answer
  as
    c_two constant varchar2(500 char) :=
      '{"p":{"type":"boolean","instructions":"a"},"q":{"type":"boolean","instructions":"b"}}';
  begin
    -- a refusal for a question that does not exist
    expect_format_error(
      c_q_pred
    , response_of('{"type":"predicate","name":"p","probability":0.5},{"type":"refusal","name":"other"}')
    , '%unknown question "other"%'
    , 'refusal for an unknown question');

    -- two entries for one question, one of them a refusal
    expect_format_error(
      c_q_pred
    , response_of('{"type":"refusal","name":"p"},{"type":"predicate","name":"p","probability":0.5}')
    , '%"p" twice%'
    , 'refusal and answer for one question');
    expect_format_error(
      c_q_pred
    , response_of('{"type":"refusal","name":"p"},{"type":"refusal","name":"p"}')
    , '%"p" twice%'
    , 'two refusals for one question');

    -- a question with neither an answer nor a refusal
    expect_format_error(
      c_two
    , response_of('{"type":"refusal","name":"p"}')
    , '%no answer for the question "q"%'
    , 'refusal for p, nothing for q');
  end refusal_still_counts_as_answer;


  procedure refusal_without_name
  as
  begin
    -- name null, as recorded
    expect_format_error(c_q_pred, uc_ai_test_samples.get(c_prefix || 'refusal_no_name_response'), '%answer 0 has no name%', 'recorded, name null');
    -- no name key at all
    expect_format_error(c_q_pred, response_of('{"type":"refusal"}'), '%answer 0 has no name%', 'no name key');
    -- a nameless refusal next to a normal answer: the count does not match
    expect_format_error(
      c_q_pred
    , response_of('{"type":"predicate","name":"p","probability":0.5},{"type":"refusal","name":null}')
    , '%answer 1 has no name%'
    , 'nameless refusal next to an answer');
  end refusal_without_name;


  procedure refusal_raw_is_kept
  as
    l_result json_object_t;
    l_raw    json_array_t;
  begin
    enqueue('refusal_response');

    l_result := uc_ai.decide('text', refusal_questions, uc_ai.c_provider_openai);

    ut.expect(l_result.get_object('raw'), 'raw equals the provider response').to_equal(uc_ai_test_samples.get_json(c_prefix || 'refusal_response'));
    l_raw := l_result.get_object('raw').get_array('answers');
    ut.expect(treat(l_raw.get(0) as json_object_t).get_string('type'), 'the wire type stays in raw').to_equal('refusal');
  end refusal_raw_is_kept;


  -- ---- provider errors -----------------------------------------------------------------

  procedure error_unknown_model
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get(c_prefix || 'error_unknown_model_response'), 404);

    try_decide('x', json_object_t.parse(c_q_pred), null, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(uc_ai_error.c_err_provider_response);
    -- the provider message on its own, not the raw body
    ut.expect(l_message, 'provider message').to_be_like('%provider OpenAI: HTTP 404: The model `gpt-6-nope` does not exist or you do not have access to it.');
  end error_unknown_model;


  procedure error_400_with_param
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get(c_prefix || 'error_one_level_response'), 400);

    try_decide('x', json_object_t.parse(c_q_pred), null, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_message, 'provider message and param').to_be_like('%provider OpenAI: HTTP 400: Invalid ''questions[0].levels'': array too short.%minimum length 2%(param questions[0].levels)');
  end error_400_with_param;


  procedure error_429
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue(
      '{"error":{"message":"Rate limit reached for requests","type":"rate_limit_exceeded","param":null,"code":null}}'
    , 429);

    try_decide('x', json_object_t.parse(c_q_pred), null, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_message, 'provider message').to_be_like('%provider OpenAI: HTTP 429: Rate limit reached for requests');
  end error_429;


  procedure error_502_html
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue('<html><body>Bad gateway</body></html>', 502);

    try_decide('x', json_object_t.parse(c_q_pred), null, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_message, 'status').to_be_like('%502%');
  end error_502_html;


  procedure error_body_on_200
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue('{"error":{"message":"The server had an error","type":"server_error","param":null,"code":null}}');

    try_decide('x', json_object_t.parse(c_q_pred), null, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_message, 'provider message').to_be_like('%The server had an error%');
  end error_body_on_200;


  -- ---- answers that do not match the questions ------------------------------------------

  procedure answer_missing
  as
    c_two constant varchar2(500 char) :=
      '{"p":{"type":"boolean","instructions":"a"},"q":{"type":"boolean","instructions":"b"}}';
  begin
    expect_format_error(c_two, response_of('{"type":"predicate","name":"p","probability":0.5}'), '%no answer for the question "q"%', 'missing');
    expect_format_error(c_two, response_of(null), '%no answer for the question "p"%', 'no answers at all');
  end answer_missing;


  procedure answer_extra
  as
  begin
    expect_format_error(
      c_q_pred
    , response_of('{"type":"predicate","name":"p","probability":0.5},{"type":"predicate","name":"other","probability":0.5}')
    , '%unknown question "other"%'
    , 'extra');
  end answer_extra;


  procedure answer_duplicate
  as
  begin
    expect_format_error(
      c_q_pred
    , response_of('{"type":"predicate","name":"p","probability":0.5},{"type":"predicate","name":"p","probability":0.6}')
    , '%"p" twice%'
    , 'duplicate');
  end answer_duplicate;


  procedure answer_wrong_type
  as
  begin
    expect_format_error(
      c_q_score
    , response_of('{"type":"predicate","name":"s","probability":0.5}')
    , '%"s" has the type predicate but the question is a score%'
    , 'predicate for a score');
    expect_format_error(
      c_q_pred
    , response_of('{"type":"choice","name":"p","choice":"a","probabilities":[],"confidence":1}')
    , '%"p" has the type choice but the question is a boolean%'
    , 'choice for a boolean');
    -- a neutral type name is not a wire type
    expect_format_error(
      c_q_pred
    , response_of('{"type":"boolean","name":"p","probability":0.5}')
    , '%has the type boolean but the question is a boolean%'
    , 'boolean on the wire');
  end answer_wrong_type;


  procedure choice_not_an_option
  as
  begin
    expect_format_error(
      c_q_choice
    , response_of('{"type":"choice","name":"c","choice":"zzz","probabilities":[{"value":"a","probability":1}],"confidence":1}')
    , '%choice is not one of the options%'
    , 'unknown choice');
    expect_format_error(
      c_q_choice
    , response_of('{"type":"choice","name":"c","probabilities":[{"value":"a","probability":1}],"confidence":1}')
    , '%choice is not one of the options%'
    , 'no choice');
    -- case matters
    expect_format_error(
      c_q_choice
    , response_of('{"type":"choice","name":"c","choice":"A"}')
    , '%choice is not one of the options%'
    , 'wrong case');
  end choice_not_an_option;


  procedure score_out_of_range
  as
  begin
    expect_format_error(c_q_score, response_of('{"type":"score","name":"s","score":3}'), '%score 3 is outside 0 to 2%', 'above');
    expect_format_error(c_q_score, response_of('{"type":"score","name":"s","score":-0.5}'), '%score -0.5 is outside 0 to 2%', 'below');
    expect_format_error(c_q_score, response_of('{"type":"score","name":"s"}'), '%no number in "score"%', 'missing');
    expect_format_error(c_q_score, response_of('{"type":"score","name":"s","score":"1"}'), '%no number in "score"%', 'string');
  end score_out_of_range;


  procedure probability_out_of_range
  as
  begin
    expect_format_error(c_q_pred, response_of('{"type":"predicate","name":"p","probability":1.5}'), '%outside 0 to 1%', 'predicate above');
    expect_format_error(c_q_pred, response_of('{"type":"predicate","name":"p","probability":-0.1}'), '%outside 0 to 1%', 'predicate below');
    expect_format_error(c_q_pred, response_of('{"type":"predicate","name":"p"}'), '%no number in "probability"%', 'predicate missing');
    expect_format_error(
      c_q_choice
    , response_of('{"type":"choice","name":"c","choice":"a","probabilities":[{"value":"a","probability":1.2},{"value":"b","probability":0}]}')
    , '%outside 0 to 1%'
    , 'choice entry');
    expect_format_error(
      c_q_score
    , response_of('{"type":"score","name":"s","score":1,"probabilities":[{"value":0,"probability":-0.2},{"value":1,"probability":1.2}]}')
    , '%outside 0 to 1%'
    , 'score entry');
  end probability_out_of_range;


  procedure probability_unknown_entry
  as
  begin
    expect_format_error(
      c_q_choice
    , response_of('{"type":"choice","name":"c","choice":"a","probabilities":[{"value":"a","probability":0.5},{"value":"zzz","probability":0.5}]}')
    , '%entry 1 is not one of the options%'
    , 'unknown option');
    expect_format_error(
      c_q_choice
    , response_of('{"type":"choice","name":"c","choice":"a","probabilities":[{"value":"a","probability":0.5},{"value":"a","probability":0.5}]}')
    , '%lists "a" twice%'
    , 'repeated option');
    expect_format_error(
      c_q_score
    , response_of('{"type":"score","name":"s","score":1,"probabilities":[{"value":0,"probability":0.5},{"value":3,"probability":0.5}]}')
    , '%level 3, outside 0 to 2%'
    , 'level out of range');
    expect_format_error(
      c_q_score
    , response_of('{"type":"score","name":"s","score":1,"probabilities":[{"value":0.5,"probability":1}]}')
    , '%outside 0 to 2%'
    , 'fractional level');
    expect_format_error(
      c_q_choice
    , response_of('{"type":"choice","name":"c","choice":"a","probabilities":{"a":1}}')
    , '%probabilities is not an array%'
    , 'object instead of array');
  end probability_unknown_entry;


  procedure answers_bad_shape
  as
  begin
    expect_format_error(c_q_pred, '{"model":"gpt-6-luna"}', '%no answers array%', 'no answers');
    expect_format_error(c_q_pred, '{"model":"gpt-6-luna","answers":{"p":1}}', '%no answers array%', 'answers is an object');
    expect_format_error(c_q_pred, '{"model":"gpt-6-luna","answers":[42]}', '%answer 0 is not an object%', 'answer is a number');
    expect_format_error(c_q_pred, response_of('{"type":"predicate","probability":0.5}'), '%answer 0 has no name%', 'no name');
  end answers_bad_shape;


  -- ---- distribution checks ---------------------------------------------------------------

  procedure sum_not_one_warns
  as
    l_result json_object_t;
  begin
    -- 0.5 + 0.3 + 0.1 = 0.9
    l_result := decide_with(c_q_choice,
      '{"type":"choice","name":"c","choice":"a","probabilities":[{"value":"a","probability":0.5},{"value":"b","probability":0.3},{"value":"c","probability":0.1}],"confidence":0.5}');
    ut.expect(warnings_of(l_result).get_size, 'choice: one warning').to_equal(1);
    ut.expect(warnings_of(l_result).get_string(0), 'choice: text').to_be_like('%"c"%sum to 0.9%');
    ut.expect(l_result.get_object('answers').get_object('c').get_string('choice'), 'the answer is still returned').to_equal('a');

    -- a deviation of 0.02 over two entries is more than two roundings
    l_result := decide_with(
      '{"c":{"type":"choice","instructions":"i","criteria":{"a":null,"b":null}}}'
    , '{"type":"choice","name":"c","choice":"a","probabilities":[{"value":"a","probability":0.5},{"value":"b","probability":0.52}]}');
    ut.expect(warnings_of(l_result).get_size, 'two entries off by 0.02: one warning').to_equal(1);

    -- the score distribution is checked as well
    l_result := decide_with(c_q_score,
      '{"type":"score","name":"s","score":0,"probabilities":[{"value":0,"probability":0.5},{"value":1,"probability":0},{"value":2,"probability":0}]}');
    ut.expect(warnings_of(l_result).get_size, 'score: one warning').to_equal(1);
    ut.expect(warnings_of(l_result).get_string(0), 'score: text').to_be_like('%"s"%sum to 0.5%');
  end sum_not_one_warns;


  procedure sum_rounding_tolerated
  as
    l_result json_object_t;
  begin
    -- three values rounded to 2 decimals: 0.34 + 0.33 + 0.32 = 0.99
    l_result := decide_with(c_q_choice,
      '{"type":"choice","name":"c","choice":"a","probabilities":[{"value":"a","probability":0.34},{"value":"b","probability":0.33},{"value":"c","probability":0.32}]}');
    ut.expect(warnings_of(l_result).get_size, 'sum 0.99 over three entries').to_equal(0);

    -- two entries: 0.5 + 0.51 = 1.01 is exactly two half units
    l_result := decide_with(
      '{"c":{"type":"choice","instructions":"i","criteria":{"a":null,"b":null}}}'
    , '{"type":"choice","name":"c","choice":"a","probabilities":[{"value":"a","probability":0.5},{"value":"b","probability":0.51}]}');
    ut.expect(warnings_of(l_result).get_size, 'sum 1.01 over two entries').to_equal(0);
  end sum_rounding_tolerated;


  procedure mean_mismatch_warns
  as
    l_result json_object_t;
  begin
    -- the mean of 0.2, 0.3, 0.5 over the levels 0, 1, 2 is 1.3; the answer says 0
    l_result := decide_with(c_q_score,
      '{"type":"score","name":"s","score":0,"probabilities":[{"value":0,"probability":0.2},{"value":1,"probability":0.3},{"value":2,"probability":0.5}],"confidence":0.4}');

    ut.expect(warnings_of(l_result).get_size, 'one warning').to_equal(1);
    ut.expect(warnings_of(l_result).get_string(0), 'text').to_be_like('%"s"%score 0 differs%mean 1.3%');
    ut.expect(l_result.get_object('answers').get_object('s').get_number('score'), 'the reported score is kept').to_equal(0);
  end mean_mismatch_warns;


  procedure mean_rounding_tolerated
  as
    l_result json_object_t;
  begin
    -- the mean is 1.3; 1.32 is within the rounding of the three probabilities and the score
    l_result := decide_with(c_q_score,
      '{"type":"score","name":"s","score":1.32,"probabilities":[{"value":0,"probability":0.2},{"value":1,"probability":0.3},{"value":2,"probability":0.5}]}');
    ut.expect(warnings_of(l_result).get_size, 'score 1.32 for the mean 1.3').to_equal(0);

    -- 1.35 is not
    l_result := decide_with(c_q_score,
      '{"type":"score","name":"s","score":1.35,"probabilities":[{"value":0,"probability":0.2},{"value":1,"probability":0.3},{"value":2,"probability":0.5}]}');
    ut.expect(warnings_of(l_result).get_size, 'score 1.35 for the mean 1.3').to_equal(1);
  end mean_rounding_tolerated;


  -- ---- logging -----------------------------------------------------------------------------------

  procedure body_is_not_logged
  as
    c_state_marker constant varchar2(60 char) := 'UC_AI_DECIDE_STATE_MARKER_0123456789';
    l_image_marker varchar2(60 char);
    l_file         json_object_t := png_file;
    l_last_id      number;
    l_result       json_object_t;
    l_count        pls_integer;
    l_calls        pls_integer;

    function marker_rows(p_last_id in number, p_marker in varchar2) return pls_integer
    as
      l_rows pls_integer;
    begin
      select count(*)
        into l_rows
        from logger_logs
       where id > p_last_id
         and (instr(text, p_marker) > 0 or sys.dbms_lob.instr(extra, p_marker) > 0);
      return l_rows;
    end marker_rows;
  begin
    select nvl(max(id), 0) into l_last_id from logger_logs;

    l_image_marker := sys.dbms_lob.substr(l_file.get_clob('data'), 60, 1);
    enqueue('image_response');

    -- control: the query does find a marker when something logs it
    uc_ai_logger.log('control row', 'test_uc_ai_decisions_wire.body_is_not_logged', c_state_marker);
    ut.expect(marker_rows(l_last_id, c_state_marker), 'control row is found').to_equal(1);

    l_result := uc_ai.decide(
      c_state_marker
    , json_object_t.parse(
        '{"topic":{"type":"choice","instructions":"i","criteria":{"refund":"r","invoice":"i","other":null}}'
        || ',"has_number_42":{"type":"boolean","instructions":"b"}}')
    , uc_ai.c_provider_openai
    , p_files => files_of(l_file));

    ut.expect(instr(uc_ai_test_http_mock.request(1).body, c_state_marker), 'the request does hold the state').to_be_greater_than(0);
    ut.expect(instr(uc_ai_test_http_mock.request(1).body, l_image_marker), 'the request does hold the image').to_be_greater_than(0);

    ut.expect(marker_rows(l_last_id, c_state_marker), 'no log row holds the state').to_equal(1);
    ut.expect(marker_rows(l_last_id, l_image_marker), 'no log row holds the image').to_equal(0);

    -- the call is logged: provider, model, counts and size
    select count(*)
      into l_calls
      from logger_logs
     where id > l_last_id
       and text like 'Calling OpenAI Decisions at ' || c_url || '%'
       and text like '%Web Credential: ' || c_credential
       and extra like 'model=gpt-6-luna, questions=2, files=1, request size=%';
    ut.expect(l_calls, 'the call is logged with counts').to_equal(1);

    select count(*)
      into l_count
      from logger_logs
     where id > l_last_id
       and (sys.dbms_lob.instr(extra, '"input_image"') > 0
         or sys.dbms_lob.instr(extra, '"questions"') > 0
         or sys.dbms_lob.instr(extra, '"model":"gpt-6-luna"') > 0
         or sys.dbms_lob.instr(extra, 'Authorization') > 0
         or sys.dbms_lob.instr(extra, 'Bearer') > 0);
    ut.expect(l_count, 'no log row holds a request body or a header').to_equal(0);
  end body_is_not_logged;

  -- ---- TypeSafe jev -----------------------------------------------------------------------------

  procedure ts_enqueue(p_sample in varchar2, p_status in pls_integer default 200)
  as
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get(c_ts_prefix || p_sample), p_status);
  end ts_enqueue;


  /*
   * The questions of the recorded TypeSafe triage request in the neutral shape.
   */
  function ts_triage_questions return json_object_t
  as
  begin
    return json_object_t.parse(
      '{"department":{"type":"choice","instructions":"Which team should handle this message?","criteria":{'
      || '"billing":"Payments, invoices, and refunds.","support":"Product usage and technical problems.","sales":"New purchases and pricing questions."}}'
      || ',"severity":{"type":"score","instructions":"How severe is the problem described?","criteria":['
      || '"Appearance only; no lost functionality.","Something is broken but the customer can continue.","The customer cannot continue or lost money."]}'
      || ',"wants_refund":{"type":"boolean","instructions":"Does the customer ask for money back?","criteria":{'
      || '"true":"The customer asks for a refund or a reimbursement.","false":"The customer does not ask for money back."}}}'
    );
  end ts_triage_questions;


  function ts_decide(
    p_state     in clob
  , p_questions in json_object_t
  , p_options   in json_object_t default null
  ) return json_object_t
  as
  begin
    return uc_ai.decide(
      p_state     => p_state
    , p_questions => p_questions
    , p_provider  => uc_ai.c_provider_typesafe
    , p_options   => p_options
    );
  end ts_decide;


  procedure ts_try(
    p_state     in clob
  , p_questions in json_object_t
  , po_code     out number
  , po_message  out varchar2
  )
  as
    l_result json_object_t;
  begin
    po_code := 0;
    l_result := ts_decide(p_state, p_questions);
  exception
    when others then
      po_code    := sqlcode;
      po_message := sqlerrm;
  end ts_try;


  function ts_response_of(p_answers in varchar2) return clob
  as
  begin
    return '{"model":"jev-1.13.0","answers":{' || p_answers
        || '},"usage":{"input_tokens":10,"output_tokens":5}}';
  end ts_response_of;


  procedure ts_try_response(
    p_questions in varchar2
  , p_response  in clob
  , po_code     out number
  , po_message  out varchar2
  , p_status    in pls_integer default 200
  )
  as
  begin
    uc_ai_test_http_mock.enqueue(p_response, p_status);
    ts_try('state', json_object_t.parse(p_questions), po_code, po_message);
  end ts_try_response;


  function ts_decide_with(
    p_questions in varchar2
  , p_answers   in varchar2
  ) return json_object_t
  as
  begin
    uc_ai_test_http_mock.enqueue(ts_response_of(p_answers));
    return ts_decide('state', json_object_t.parse(p_questions));
  end ts_decide_with;


  procedure ts_expect_format_error(
    p_questions in varchar2
  , p_response  in clob
  , p_like      in varchar2
  , p_label     in varchar2
  )
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    ts_try_response(p_questions, p_response, l_code, l_message);
    ut.expect(l_code, p_label || ': code').to_equal(uc_ai_error.c_err_format_processing);
    ut.expect(l_message, p_label || ': message').to_be_like(p_like);
  end ts_expect_format_error;


  procedure ts_expect_provider_error(
    p_response in clob
  , p_status   in pls_integer
  , p_like     in varchar2
  , p_label    in varchar2
  )
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    ts_try_response(c_q_pred, p_response, l_code, l_message, p_status);
    ut.expect(l_code, p_label || ': code').to_equal(uc_ai_error.c_err_provider_response);
    ut.expect(l_message, p_label || ': message').to_be_like(p_like);
  end ts_expect_provider_error;


  function ts_wire_question(p_index in pls_integer, p_id in varchar2) return json_object_t
  as
  begin
    return uc_ai_test_http_mock.request_json(p_index).get_object('questions').get_object(p_id);
  end ts_wire_question;


  -- ---- request shape ---------------------------------------------------------

  procedure ts_url_headers_and_default_model
  as
    l_result json_object_t;
  begin
    ts_enqueue('triage_response');

    l_result := ts_decide(c_triage_state, ts_triage_questions);

    test_uc_ai_wire.expect_url(1, c_ts_url);
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('model'), 'default model').to_equal('jev-latest');
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Content-Type'), 'Content-Type').to_equal('application/json');
    ut.expect(uc_ai_test_http_mock.request(1).credential, 'credential name').to_equal(c_credential);
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Authorization'), 'no key header when a credential is named').to_be_null();
    test_uc_ai_wire.expect_all_consumed(1);
  end ts_url_headers_and_default_model;


  procedure ts_base_url_replaces_host
  as
    l_result json_object_t;
  begin
    ts_enqueue('triage_response');
    ts_enqueue('triage_response');

    uc_ai.g_base_url := 'https://proxy.example.test/typesafe/v1';
    l_result := ts_decide(c_triage_state, ts_triage_questions);

    uc_ai.g_base_url := 'https://proxy.example.test/typesafe/v1/';
    l_result := ts_decide(c_triage_state, ts_triage_questions);

    test_uc_ai_wire.expect_url(1, 'https://proxy.example.test/typesafe/v1/systemone');
    test_uc_ai_wire.expect_url(2, 'https://proxy.example.test/typesafe/v1/systemone');
    test_uc_ai_wire.expect_all_consumed(2);
  end ts_base_url_replaces_host;


  procedure ts_request_matches_recorded
  as
    l_result json_object_t;
  begin
    ts_enqueue('triage_response');
    ts_enqueue('score_empty_levels_response');

    l_result := ts_decide(c_triage_state, ts_triage_questions);
    test_uc_ai_wire.expect_request(1, c_ts_prefix || 'triage_request');

    -- a null and an empty description both go out as an empty string
    l_result := ts_decide(
      'The site is down for all customers.'
    , json_object_t.parse('{"s":{"type":"score","instructions":"Rate the severity.","criteria":[null,"",null]}}'));
    test_uc_ai_wire.expect_request(2, c_ts_prefix || 'score_empty_levels_request');

    test_uc_ai_wire.expect_all_consumed(2);
  end ts_request_matches_recorded;


  procedure ts_noul_criteria
  as
    l_result json_object_t;
    l_q      json_object_t;
  begin
    l_result := ts_decide_with(
      '{"plain":{"type":"boolean","instructions":"I"}'
      || ',"both":{"type":"boolean","instructions":"I","criteria":{"true":"T","false":"F"}}'
      || ',"true_only":{"type":"boolean","instructions":"I","criteria":{"true":"T"}}'
      || ',"blank":{"type":"boolean","instructions":"I","criteria":{"true":"","false":null}}}'
    , '"plain":{"type":"noul","noul":0.5},"both":{"type":"noul","noul":0.5},"true_only":{"type":"noul","noul":0.5},"blank":{"type":"noul","noul":0.5}');

    l_q := ts_wire_question(1, 'plain');
    ut.expect(l_q.get_string('type'), 'plain: type').to_equal('noul');
    ut.expect(l_q.get_string('instructions'), 'plain: instructions').to_equal('I');
    ut.expect(key_count(l_q), 'plain: type and instructions only').to_equal(2);

    l_q := ts_wire_question(1, 'both');
    ut.expect(l_q.get_object('criteria').get_string('true'), 'both: true').to_equal('T');
    ut.expect(l_q.get_object('criteria').get_string('false'), 'both: false').to_equal('F');

    l_q := ts_wire_question(1, 'true_only');
    ut.expect(key_count(l_q.get_object('criteria')), 'true_only: one key').to_equal(1);
    ut.expect(l_q.get_object('criteria').has('true'), 'true_only: true').to_be_true();

    l_q := ts_wire_question(1, 'blank');
    ut.expect(l_q.has('criteria'), 'blank texts: no criteria key').to_be_false();
    ut.expect(key_count(l_q), 'blank: type and instructions only').to_equal(2);
  end ts_noul_criteria;


  procedure ts_blank_descriptions
  as
    l_result json_object_t;
    l_choice json_object_t;
    l_levels json_array_t;
  begin
    l_result := ts_decide_with(
      '{"c":{"type":"choice","instructions":"I","criteria":{"x":"X","y":null,"z":""}}'
      || ',"s":{"type":"score","instructions":"I","criteria":["L0",null,"","L3"]}}'
    , '"c":{"type":"choice","choice":"x","probabilities":{"x":1,"y":0,"z":0}}'
      || ',"s":{"type":"score","score":3,"probabilities":{"0":0,"1":0,"2":0,"3":1}}');

    l_choice := ts_wire_question(1, 'c').get_object('criteria');
    ut.expect(l_choice.get_string('x'), 'described option').to_equal('X');
    ut.expect(l_choice.get('y').is_null, 'null description stays null').to_be_true();
    ut.expect(l_choice.get('z').is_null, 'empty description becomes null').to_be_true();
    ut.expect(key_count(l_choice), 'all options are sent').to_equal(3);

    -- jev rejects a null level (HTTP 422): a level without a description is an empty string
    l_levels := ts_wire_question(1, 's').get_array('criteria');
    ut.expect(l_levels.get_size, 'level count').to_equal(4);
    ut.expect(l_levels.get_string(0), 'level 0').to_equal('L0');
    ut.expect(l_levels.get(1).is_string, 'null level is a string').to_be_true();
    ut.expect(l_levels.get(2).is_string, 'empty level is a string').to_be_true();
    ut.expect(l_levels.get(3).is_string, 'level 3').to_be_true();
    ut.expect(instr(uc_ai_test_http_mock.request(1).body, '["L0","","","L3"]'), 'request text').to_be_greater_than(0);
  end ts_blank_descriptions;


  procedure ts_question_order_follows_keys
  as
    l_result json_object_t;
    l_q      json_object_t;
  begin
    ts_enqueue('order_response');

    l_result := ts_decide(
      'The site is down for all customers.'
    , json_object_t.parse(
        '{"z_last":{"type":"boolean","instructions":"Is this an outage?"}'
        || ',"a_first":{"type":"boolean","instructions":"Is this a feature request?"}'
        || ',"m_mid":{"type":"boolean","instructions":"Is this about billing?"}}'));

    l_q := uc_ai_test_http_mock.request_json(1).get_object('questions');
    ut.expect(key_at(l_q, 1), 'wire question 1').to_equal('z_last');
    ut.expect(key_at(l_q, 2), 'wire question 2').to_equal('a_first');
    ut.expect(key_at(l_q, 3), 'wire question 3').to_equal('m_mid');
    ut.expect(key_at(l_result.get_object('answers'), 1), 'answer 1').to_equal('z_last');
    ut.expect(l_result.get_object('answers').get_object('z_last').get_number('probability'), 'z_last').to_equal(0.96);
    ut.expect(l_result.get_object('answers').get_object('a_first').get_number('probability'), 'a_first').to_equal(0.02);
  end ts_question_order_follows_keys;


  procedure ts_state_and_long_texts
  as
    l_result json_object_t;
    l_state  clob := repeat_text('s', 40000);
    l_instr  clob := repeat_text('i', 40000);
    l_questions json_object_t := json_object_t();
    l_question  json_object_t := json_object_t();
  begin
    l_question.put('type', 'boolean');
    l_question.put('instructions', l_instr);
    l_questions.put('p', l_question);

    uc_ai_test_http_mock.enqueue(ts_response_of('"p":{"type":"noul","noul":0.5}'));
    l_result := ts_decide(l_state, l_questions);

    ut.expect(uc_ai_test_http_mock.request_json(1).get('state').is_string, 'the state is a string').to_be_true();
    ut.expect(sys.dbms_lob.getlength(uc_ai_test_http_mock.request_json(1).get_clob('state')), 'state length').to_equal(40000);
    ut.expect(sys.dbms_lob.getlength(ts_wire_question(1, 'p').get_clob('instructions')), 'instructions length').to_equal(40000);
  end ts_state_and_long_texts;


  procedure ts_images_become_assets
  as
    l_files  json_array_t := json_array_t();
    l_result json_object_t;
    l_body   json_object_t;
    l_assets json_object_t;
    l_keys   json_key_list;
    l_state  clob;
    l_asset  json_object_t;
  begin
    ts_enqueue('triage_response');

    l_files.append(uc_ai_message_api.create_file_content('image/png', 'AAAA' || chr(10) || 'BBBB', 'a.png'));
    l_files.append(uc_ai_message_api.create_file_content('image/jpg', 'CCCC', 'b.jpg'));

    l_result := uc_ai.decide(
      p_state     => c_triage_state
    , p_questions => ts_triage_questions
    , p_provider  => uc_ai.c_provider_typesafe
    , p_files     => l_files
    , p_options   => json_object_t.parse('{"extra_body":{"assets":{"evil":{"format":"png","data_base64":"x"}}}}')
    );

    ut.expect(uc_ai_test_http_mock.request_header(1, 'TypeSafe-Danger-Zone-Images'), 'images header').to_equal('true');
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Content-Type'), 'Content-Type').to_equal('application/json');

    l_body   := uc_ai_test_http_mock.request_json(1);
    l_assets := l_body.get_object('assets');
    l_keys   := l_assets.get_keys;
    l_state  := l_body.get_clob('state');

    ut.expect(l_keys.count, 'two assets, extra_body assets replaced').to_equal(2);
    ut.expect(l_state, 'state text stays first').to_be_like(c_triage_state || '%');

    <<asset_loop>>
    for i in 1 .. l_keys.count loop
      ut.expect(instr(l_state, l_keys(i)), 'asset ' || i || ' is referenced in the state').to_be_greater_than(0);
      ut.expect(l_assets.get_object(l_keys(i)).get_string('type'), 'asset ' || i || ' type').to_equal('image');
    end loop asset_loop;

    l_asset := l_assets.get_object(l_keys(1));
    ut.expect(l_asset.get_string('format'), 'png format').to_equal('png');
    ut.expect(l_asset.get_string('data_base64'), 'base64 is one line').to_equal('AAAABBBB');
    ut.expect(l_assets.get_object(l_keys(2)).get_string('format'), 'image/jpg becomes jpeg').to_equal('jpeg');
    ut.expect(l_assets.get_object(l_keys(2)).get_string('data_base64'), 'second data').to_equal('CCCC');
  end ts_images_become_assets;


  procedure ts_no_files_no_assets
  as
    l_result json_object_t;
  begin
    ts_enqueue('triage_response');

    l_result := ts_decide(c_triage_state, ts_triage_questions);

    ut.expect(uc_ai_test_http_mock.request_json(1).has('assets'), 'no assets').to_be_false();
    ut.expect(uc_ai_test_http_mock.request_header(1, 'TypeSafe-Danger-Zone-Images'), 'no images header').to_be_null();
  end ts_no_files_no_assets;


  procedure ts_extra_body_and_options
  as
    l_result   json_object_t;
    l_body     json_object_t;
    l_warnings json_array_t;
    l_found    pls_integer := 0;
  begin
    ts_enqueue('triage_response');

    l_result := ts_decide(
      c_triage_state
    , ts_triage_questions
    , json_object_t.parse(
        '{"safety_identifier":"user-4711","temperature":0,"extra_body":{"future_key":true,"model":"evil","state":"evil","questions":[]}}'));

    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_body.get_boolean('future_key'), 'extra_body key').to_be_true();
    ut.expect(l_body.get_string('model'), 'model wins').to_equal('jev-latest');
    ut.expect(l_body.get_string('state'), 'state wins').to_equal(c_triage_state);
    ut.expect(key_count(l_body.get_object('questions')), 'questions win').to_equal(3);
    ut.expect(l_body.has('extra_body'), 'no extra_body key in the request').to_be_false();
    ut.expect(l_body.has('safety_identifier'), 'safety_identifier is OpenAI only').to_be_false();
    ut.expect(l_body.has('temperature'), 'unknown option is not sent').to_be_false();

    l_warnings := warnings_of(l_result);
    ut.expect(l_warnings.get_size, 'two warnings').to_equal(2);
    <<warning_loop>>
    for i in 0 .. l_warnings.get_size - 1 loop
      if l_warnings.get_string(i) like '%safety_identifier%not supported for provider typesafe%'
         or l_warnings.get_string(i) like '%temperature%not supported for provider typesafe%'
      then
        l_found := l_found + 1;
      end if;
    end loop warning_loop;
    ut.expect(l_found, 'both warnings name the option and the provider').to_equal(2);
  end ts_extra_body_and_options;


  procedure ts_limits_are_sent
  as
    l_result   json_object_t;
    l_options  json_object_t := json_object_t();
    l_levels   json_array_t := json_array_t();
    l_question json_object_t := json_object_t();
    l_questions json_object_t := json_object_t();
  begin
    <<option_loop>>
    for i in 0 .. 254 loop
      l_options.put('cat_' || i, case when i = 0 then 'Invoices' end);
    end loop option_loop;
    l_question.put('type', 'choice');
    l_question.put('instructions', 'Pick the best matching category.');
    l_question.put('criteria', l_options);
    l_questions.put('c', l_question);

    ts_enqueue('choices_255_response');
    l_result := ts_decide('Please send me the invoice for order 42.', l_questions);

    ut.expect(key_count(ts_wire_question(1, 'c').get_object('criteria')), '255 options sent').to_equal(255);
    ut.expect(l_result.get_object('answers').get_object('c').get_string('choice'), '255: choice').to_equal('cat_0');
    ut.expect(key_count(l_result.get_object('answers').get_object('c').get_object('probabilities')), '255 probabilities').to_equal(255);
    ut.expect(warnings_of(l_result).get_size, '255: no warning').to_equal(0);

    <<level_loop>>
    for i in 0 .. 9 loop
      l_levels.append('L' || i);
    end loop level_loop;
    l_question := json_object_t();
    l_question.put('type', 'score');
    l_question.put('instructions', 'Rate the severity.');
    l_question.put('criteria', l_levels);
    l_questions := json_object_t();
    l_questions.put('s', l_question);

    ts_enqueue('levels_10_response');
    l_result := ts_decide('The site is down for all customers.', l_questions);

    ut.expect(ts_wire_question(2, 's').get_array('criteria').get_size, '10 levels sent').to_equal(10);
    -- the recorded score 7.71 is the mean of the unrounded probabilities; the rounded ones give 7.70
    ut.expect(l_result.get_object('answers').get_object('s').get_number('score'), '10 levels: score').to_equal(7.71);
    ut.expect(warnings_of(l_result).get_size, '10 levels: no warning').to_equal(0);
  end ts_limits_are_sent;


  -- ---- response mapping --------------------------------------------------------

  procedure ts_triage_result_is_neutral
  as
    l_result  json_object_t;
    l_answers json_object_t;
    l_probs   json_object_t;
  begin
    ts_enqueue('triage_response');

    l_result  := ts_decide(c_triage_state, ts_triage_questions);
    l_answers := l_result.get_object('answers');

    ut.expect(key_count(l_answers), 'three answers').to_equal(3);

    ut.expect(l_answers.get_object('department').get_string('type'), 'department type').to_equal('choice');
    ut.expect(l_answers.get_object('department').get_string('choice'), 'department').to_equal('billing');
    l_probs := l_answers.get_object('department').get_object('probabilities');
    ut.expect(key_count(l_probs), 'one probability per option').to_equal(3);
    ut.expect(l_probs.get_number('billing'), 'billing').to_equal(1);
    ut.expect(l_probs.get_number('support'), 'support').to_equal(0);
    ut.expect(l_probs.get_number('sales'), 'sales').to_equal(0);

    ut.expect(l_answers.get_object('severity').get_string('type'), 'severity type').to_equal('score');
    ut.expect(l_answers.get_object('severity').get_number('score'), 'severity').to_equal(1.96);
    l_probs := l_answers.get_object('severity').get_object('probabilities');
    ut.expect(l_probs.get_number('0'), 'level 0').to_equal(0);
    ut.expect(l_probs.get_number('1'), 'level 1').to_equal(0.03);
    ut.expect(l_probs.get_number('2'), 'level 2').to_equal(0.97);
    ut.expect(l_answers.get_object('severity').has('legend'), 'legend is not part of the neutral answer').to_be_false();

    ut.expect(l_answers.get_object('wants_refund').get_string('type'), 'wants_refund type').to_equal('boolean');
    ut.expect(l_answers.get_object('wants_refund').get_number('probability'), 'wants_refund').to_equal(0.99);
    ut.expect(key_count(l_answers.get_object('wants_refund')), 'boolean: type and probability only').to_equal(2);

    ut.expect(warnings_of(l_result).get_size, 'no warnings').to_equal(0);
    ut.expect(l_result.get_string('model'), 'model').to_equal('jev-1.13.0');
  end ts_triage_result_is_neutral;


  procedure ts_noul_maps_to_boolean
  as
    l_result json_object_t;
  begin
    l_result := ts_decide_with(c_q_pred, '"p":{"type":"noul","noul":0.42}');
    ut.expect(l_result.get_object('answers').get_object('p').get_string('type'), 'type').to_equal('boolean');
    ut.expect(l_result.get_object('answers').get_object('p').get_number('probability'), 'probability').to_equal(0.42);
    ut.expect(l_result.get_object('answers').to_clob, 'the wire name never appears').not_to_be_like('%noul%');

    -- the ends of the range
    l_result := ts_decide_with(c_q_pred, '"p":{"type":"noul","noul":0}');
    ut.expect(l_result.get_object('answers').get_object('p').get_number('probability'), '0').to_equal(0);
    l_result := ts_decide_with(c_q_pred, '"p":{"type":"noul","noul":1}');
    ut.expect(l_result.get_object('answers').get_object('p').get_number('probability'), '1').to_equal(1);
  end ts_noul_maps_to_boolean;


  procedure ts_confidence_in_provider_metadata
  as
    l_result     json_object_t;
    l_confidence json_object_t;
  begin
    ts_enqueue('triage_response');

    l_result     := ts_decide(c_triage_state, ts_triage_questions);
    l_confidence := l_result.get_object('provider_metadata').get_object('confidence');

    ut.expect(key_count(l_confidence), 'choice and score only').to_equal(2);
    ut.expect(l_confidence.get_number('department'), 'department').to_equal(1);
    ut.expect(l_confidence.get_number('severity'), 'severity').to_equal(0.95);
    ut.expect(l_confidence.has('wants_refund'), 'a noul has no confidence').to_be_false();
    ut.expect(l_result.get_object('answers').get_object('department').has('confidence'), 'confidence is not in the answer').to_be_false();
  end ts_confidence_in_provider_metadata;


  procedure ts_usage_is_mapped
  as
    l_result json_object_t;
  begin
    ts_enqueue('triage_response');

    l_result := ts_decide(c_triage_state, ts_triage_questions);

    ut.expect(l_result.get_object('usage').get_number('input_tokens'), 'input_tokens').to_equal(458);
    ut.expect(l_result.get_object('usage').get_number('output_tokens'), 'output_tokens').to_equal(71);
    ut.expect(l_result.get_object('usage').has('total_tokens'), 'jev reports no total').to_be_false();
    ut.expect(l_result.get_object('provider_metadata').get_object('usage').get_number('input_tokens'), 'provider usage kept').to_equal(458);
  end ts_usage_is_mapped;


  procedure ts_model_and_raw
  as
    l_result json_object_t;
  begin
    ts_enqueue('triage_response');
    l_result := ts_decide(c_triage_state, ts_triage_questions);
    ut.expect(l_result.get_string('model'), 'the resolved version, not the alias').to_equal('jev-1.13.0');
    ut.expect(l_result.get_object('raw').get_string('model'), 'raw model').to_equal('jev-1.13.0');
    ut.expect(l_result.get_object('raw').get_object('answers').get_object('wants_refund').get_string('type'), 'raw keeps the wire type').to_equal('noul');
    ut.expect(l_result.get_object('raw').get_object('answers').get_object('severity').has('legend'), 'raw keeps the legend').to_be_true();

    -- no model and no usage in the response
    uc_ai_test_http_mock.enqueue('{"answers":{"p":{"type":"noul","noul":0.5}}}');
    l_result := ts_decide('state', json_object_t.parse(c_q_pred));
    ut.expect(l_result.get_string('model'), 'the requested model').to_equal('jev-latest');
    ut.expect(key_count(l_result.get_object('usage')), 'no usage keys').to_equal(0);
    ut.expect(l_result.get_object('provider_metadata').has('usage'), 'no provider usage').to_be_false();

    -- an explicit model is sent and used as the fallback
    uc_ai_test_http_mock.enqueue('{"answers":{"p":{"type":"noul","noul":0.5}}}');
    l_result := uc_ai.decide('state', json_object_t.parse(c_q_pred), uc_ai.c_provider_typesafe, p_model => 'jev-1.13.0');
    ut.expect(uc_ai_test_http_mock.request_json(3).get_string('model'), 'explicit model sent').to_equal('jev-1.13.0');
    ut.expect(l_result.get_string('model'), 'explicit model fallback').to_equal('jev-1.13.0');
  end ts_model_and_raw;


  procedure ts_recorded_samples_map
  as
    l_result json_object_t;
    l_answers json_object_t;
  begin
    -- variants: null and empty descriptions, 2 levels, noul with and without criteria
    ts_enqueue('variants_response');
    l_result := ts_decide(
      'The login page shows a typo in the footer.'
    , json_object_t.parse(
        '{"area_null_desc":{"type":"choice","instructions":"a","criteria":{"ui":null,"backend":null,"docs":null}}'
        || ',"area_empty_desc":{"type":"choice","instructions":"a","criteria":{"ui":"","backend":"","docs":""}}'
        || ',"urgent_two":{"type":"score","instructions":"b","criteria":["No","Yes"]}'
        || ',"noul_plain":{"type":"boolean","instructions":"c"}'
        || ',"noul_criteria":{"type":"boolean","instructions":"c","criteria":{"true":"t","false":"f"}}'
        || ',"noul_criteria_true_only":{"type":"boolean","instructions":"c","criteria":{"true":"t"}}'
        || ',"noul_instr_object":{"type":"boolean","instructions":"c"}}'));
    ut.expect(l_result.get_object('answers').get_object('urgent_two').get_number('score'), 'variants: score').to_equal(0);
    ut.expect(l_result.get_object('answers').get_object('noul_plain').get_number('probability'), 'variants: noul').to_equal(0.94);
    ut.expect(warnings_of(l_result).get_size, 'variants: warnings').to_equal(0);

    -- order: the answers come back in the order of the request
    ts_enqueue('order_response');
    l_result := ts_decide(
      'x'
    , json_object_t.parse(
        '{"z_last":{"type":"boolean","instructions":"a"},"a_first":{"type":"boolean","instructions":"b"},"m_mid":{"type":"boolean","instructions":"c"}}'));
    ut.expect(l_result.get_object('answers').get_object('m_mid').get_number('probability'), 'order: m_mid').to_equal(0.06);

    -- illposed: jev answers a nonsense question (low confidence) and does not refuse
    ts_enqueue('illposed_response');
    l_result := ts_decide(
      'The site is down for all customers.'
    , json_object_t.parse(
        '{"smell":{"type":"choice","instructions":"a","criteria":{"red":"red","blue":"blue"}}'
        || ',"lottery":{"type":"boolean","instructions":"b"},"good":{"type":"boolean","instructions":"c"}}'));
    l_answers := l_result.get_object('answers');
    ut.expect(l_answers.get_object('smell').get_string('choice'), 'illposed: choice').to_equal('red');
    ut.expect(l_answers.get_object('lottery').get_number('probability'), 'illposed: lottery').to_equal(0.37);
    ut.expect(l_answers.to_clob, 'illposed: no refusal').not_to_be_like('%refused%');
    ut.expect(l_result.get_object('provider_metadata').get_object('confidence').get_number('smell'), 'illposed: low confidence is reported').to_equal(0.2);
    ut.expect(warnings_of(l_result).get_size, 'illposed: warnings').to_equal(0);

    -- jev accepts one option and one level; the neutral check wants two, the answer maps
    ts_enqueue('one_option_response');
    l_result := ts_decide('x', json_object_t.parse('{"c":{"type":"choice","instructions":"a","criteria":{"only":"x","other":"y"}}}'));
    ut.expect(l_result.get_object('answers').get_object('c').get_string('choice'), 'one_option: choice').to_equal('only');
    ut.expect(warnings_of(l_result).get_size, 'one_option: warnings').to_equal(0);

    ts_enqueue('one_level_response');
    l_result := ts_decide('x', json_object_t.parse('{"s":{"type":"score","instructions":"a","criteria":["Only","Other"]}}'));
    ut.expect(l_result.get_object('answers').get_object('s').get_number('score'), 'one_level: score').to_equal(0);
    ut.expect(warnings_of(l_result).get_size, 'one_level: warnings').to_equal(0);

    -- an empty state, a state object and a state array were answered
    ts_enqueue('empty_state_response');
    l_result := ts_decide('x', json_object_t.parse('{"n":{"type":"boolean","instructions":"a"}}'));
    ut.expect(l_result.get_object('answers').get_object('n').get_number('probability'), 'empty_state: probability').to_equal(0.35);

    ts_enqueue('state_object_response');
    l_result := ts_decide('x', json_object_t.parse('{"refund":{"type":"boolean","instructions":"a"}}'));
    ut.expect(l_result.get_object('answers').get_object('refund').get_number('probability'), 'state_object: probability').to_equal(0.76);

    ts_enqueue('state_array_response');
    l_result := ts_decide('x', json_object_t.parse('{"refund":{"type":"boolean","instructions":"a"}}'));
    ut.expect(l_result.get_object('answers').get_object('refund').get_number('probability'), 'state_array: probability').to_equal(0.99);

    test_uc_ai_wire.expect_all_consumed(8);
  end ts_recorded_samples_map;


  procedure ts_missing_optional_parts
  as
    l_result json_object_t;
  begin
    l_result := ts_decide_with(c_q_choice, '"c":{"type":"choice","choice":"a"}');
    ut.expect(l_result.get_object('answers').get_object('c').get_string('choice'), 'choice').to_equal('a');
    ut.expect(l_result.get_object('answers').get_object('c').has('probabilities'), 'choice: no probabilities').to_be_false();
    ut.expect(l_result.get_object('provider_metadata').has('confidence'), 'no confidence').to_be_false();
    ut.expect(warnings_of(l_result).get_size, 'choice: no warning').to_equal(0);

    l_result := ts_decide_with(c_q_score, '"s":{"type":"score","score":1}');
    ut.expect(l_result.get_object('answers').get_object('s').get_number('score'), 'score').to_equal(1);
    ut.expect(l_result.get_object('answers').get_object('s').has('probabilities'), 'score: no probabilities').to_be_false();
    ut.expect(warnings_of(l_result).get_size, 'score: no warning').to_equal(0);
  end ts_missing_optional_parts;


  -- ---- provider errors ---------------------------------------------------------

  procedure ts_error_unknown_model
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    ts_enqueue('error_unknown_model_response', 400);

    ts_try('x', json_object_t.parse(c_q_pred), l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(uc_ai_error.c_err_provider_response);
    -- the vendor message on its own, not the raw body
    ut.expect(l_message, 'vendor message').to_be_like('%provider TypeSafe: HTTP 400: Unknown model: jev-nope');

    -- the generic message of an object detail
    ts_enqueue('error_unknown_type_response', 400);
    ts_try('x', json_object_t.parse(c_q_pred), l_code, l_message);
    ut.expect(l_message, 'generic message').to_be_like('%provider TypeSafe: HTTP 400: Invalid request.');
  end ts_error_unknown_model;


  procedure ts_error_detail_string
  as
  begin
    ts_expect_provider_error(
      uc_ai_test_samples.get(c_ts_prefix || 'error_choices_256_response'), 400
    , '%provider TypeSafe: HTTP 400: Too many choices. Must have at most 255 choices.', '256 choices');
    ts_expect_provider_error(
      uc_ai_test_samples.get(c_ts_prefix || 'error_empty_instructions_response'), 400
    , '%provider TypeSafe: HTTP 400: Noul question must have criteria or instructions: e', 'noul without instructions');
  end ts_error_detail_string;


  procedure ts_error_422_validation_list
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    ts_expect_provider_error(
      uc_ai_test_samples.get(c_ts_prefix || 'error_missing_state_response'), 422
    , '%provider TypeSafe: HTTP 422: Field required (param state)', 'missing state');
    ts_expect_provider_error(
      uc_ai_test_samples.get(c_ts_prefix || 'error_choice_array_criteria_response'), 422
    , '%provider TypeSafe: HTTP 422: Input should be a valid dictionary (param questions.c.choice.criteria)', 'wrong criteria type');
    ts_expect_provider_error(
      uc_ai_test_samples.get(c_ts_prefix || 'error_empty_questions_response'), 422
    , '%HTTP 422: Dictionary should have at least 1 item after validation, not 0 (param questions)', 'empty questions');

    -- the echo of the request in input ("Is it an outage?") is never part of the message
    ts_try_response(c_q_pred, uc_ai_test_samples.get(c_ts_prefix || 'error_missing_state_response'), l_code, l_message, 422);
    ut.expect(uc_ai_test_samples.get(c_ts_prefix || 'error_missing_state_response'), 'the recorded error does echo the input').to_be_like('%Is it an outage?%');
    ut.expect(l_message, 'the echo is not in the message').not_to_be_like('%Is it an outage%');
  end ts_error_422_validation_list;


  procedure ts_error_422_many_items
  as
    l_code    number;
    l_message varchar2(4000 char);
    l_items   pls_integer;
  begin
    l_items := uc_ai_test_samples.get_json(c_ts_prefix || 'error_null_level_response').get_array('detail').get_size;
    ut.expect(l_items, 'the recorded error has more than 3 items').to_be_greater_than(3);

    ts_enqueue('error_null_level_response', 422);
    ts_try('x', json_object_t.parse(c_q_pred), l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(uc_ai_error.c_err_provider_response);
    ut.expect(l_message, 'first item').to_be_like('%HTTP 422: Input should be a valid string (param questions.urgent_null_levels.score.criteria.0.str);%');
    ut.expect(l_message, 'cut after 3 items').to_be_like('%; and ' || (l_items - 3) || ' more');
    ut.expect(length(l_message) - length(replace(l_message, '(param ')), 'three items shown').to_equal(3 * length('(param '));
  end ts_error_422_many_items;


  procedure ts_error_status_codes
  as
  begin
    -- the bodies of 429, 529 and 401 were not recorded (see the proposal); these are the documented statuses
    ts_expect_provider_error('{"detail":"Rate limit exceeded"}', 429, '%provider TypeSafe: HTTP 429: Rate limit exceeded', '429');
    ts_expect_provider_error('{"detail":{"error_type":"overloaded","message":"TypeSafe is overloaded"}}', 529, '%HTTP 529: TypeSafe is overloaded', '529');
    ts_expect_provider_error('{"detail":"Invalid API key"}', 401, '%HTTP 401: Invalid API key', '401');
    -- a JSON body of an unknown shape and an HTML page are reported with the status
    ts_expect_provider_error('{"message":"Unauthorized"}', 401, '%401%Unauthorized%', '401 other shape');
    ts_expect_provider_error('<html><body>Bad gateway</body></html>', 502, '%502%', '502 html');
  end ts_error_status_codes;


  procedure ts_error_body_on_200
  as
  begin
    ts_expect_provider_error('{"error":{"message":"The server had an error"}}', 200, '%The server had an error%', 'error on 200');
  end ts_error_body_on_200;


  -- ---- answers that do not match the questions -----------------------------------------

  procedure ts_answer_missing_or_extra
  as
    c_two constant varchar2(500 char) :=
      '{"p":{"type":"boolean","instructions":"a"},"q":{"type":"boolean","instructions":"b"}}';
  begin
    ts_expect_format_error(c_two, ts_response_of('"p":{"type":"noul","noul":0.5}'), '%no answer for the question "q"%', 'missing');
    ts_expect_format_error(c_two, ts_response_of(null), '%no answer for the question "p"%', 'no answers at all');
    ts_expect_format_error(
      c_q_pred
    , ts_response_of('"p":{"type":"noul","noul":0.5},"other":{"type":"noul","noul":0.5}')
    , '%unknown question "other"%'
    , 'extra');
  end ts_answer_missing_or_extra;


  procedure ts_answer_wrong_type
  as
  begin
    ts_expect_format_error(c_q_pred, ts_response_of('"p":{"type":"choice","choice":"a"}'), '%type choice but the question is a boolean%', 'choice for boolean');
    ts_expect_format_error(c_q_choice, ts_response_of('"c":{"type":"noul","noul":0.5}'), '%type noul but the question is a choice%', 'noul for choice');
    ts_expect_format_error(c_q_score, ts_response_of('"s":{"type":"choice","choice":"a"}'), '%type choice but the question is a score%', 'choice for score');
    -- the neutral names are not jev types
    ts_expect_format_error(c_q_pred, ts_response_of('"p":{"type":"boolean","probability":0.5}'), '%type boolean but the question is a boolean%', 'neutral name');
    ts_expect_format_error(c_q_pred, ts_response_of('"p":{"noul":0.5}'), '%type null%', 'no type');
  end ts_answer_wrong_type;


  procedure ts_choice_not_an_option
  as
  begin
    ts_expect_format_error(c_q_choice, ts_response_of('"c":{"type":"choice","choice":"z"}'), '%"c"%choice is not one of the options%', 'unknown option');
    ts_expect_format_error(c_q_choice, ts_response_of('"c":{"type":"choice"}'), '%choice is not one of the options%', 'no choice');
    ts_expect_format_error(c_q_choice, ts_response_of('"c":{"type":"choice","choice":null}'), '%choice is not one of the options%', 'null choice');
  end ts_choice_not_an_option;


  procedure ts_score_out_of_range
  as
  begin
    ts_expect_format_error(c_q_score, ts_response_of('"s":{"type":"score","score":2.5}'), '%score 2.5 is outside 0 to 2%', 'above');
    ts_expect_format_error(c_q_score, ts_response_of('"s":{"type":"score","score":-0.1}'), '%score -0.1 is outside 0 to 2%', 'below');
    ts_expect_format_error(c_q_score, ts_response_of('"s":{"type":"score"}'), '%no number in "score"%', 'no score');
    ts_expect_format_error(c_q_score, ts_response_of('"s":{"type":"score","score":"1"}'), '%no number in "score"%', 'score as text');
  end ts_score_out_of_range;


  procedure ts_probability_out_of_range
  as
  begin
    ts_expect_format_error(c_q_pred, ts_response_of('"p":{"type":"noul","noul":1.5}'), '%"noul" is 1.5, outside 0 to 1%', 'noul above');
    ts_expect_format_error(c_q_pred, ts_response_of('"p":{"type":"noul","noul":-0.1}'), '%outside 0 to 1%', 'noul below');
    ts_expect_format_error(c_q_pred, ts_response_of('"p":{"type":"noul"}'), '%no number in "noul"%', 'no noul');
    ts_expect_format_error(c_q_pred, ts_response_of('"p":{"type":"noul","noul":null}'), '%no number in "noul"%', 'null noul');
    ts_expect_format_error(
      c_q_choice
    , ts_response_of('"c":{"type":"choice","choice":"a","probabilities":{"a":1.2,"b":0,"c":0}}')
    , '%outside 0 to 1%', 'choice probability');
    ts_expect_format_error(
      c_q_score
    , ts_response_of('"s":{"type":"score","score":0,"probabilities":{"0":-0.5,"1":0.5,"2":1}}')
    , '%outside 0 to 1%', 'score probability');
  end ts_probability_out_of_range;


  procedure ts_probability_unknown_key
  as
    l_key varchar2(10 char);
  begin
    ts_expect_format_error(
      c_q_choice
    , ts_response_of('"c":{"type":"choice","choice":"a","probabilities":{"a":0.5,"d":0.5}}')
    , '%"d"%not one of the options%', 'unknown option');

    -- three levels: 0, 1 and 2 only; no sign, no leading zero, no fraction, no text
    <<key_loop>>
    for i in 1 .. 5 loop
      l_key := case i when 1 then '3' when 2 then 'x' when 3 then '-1' when 4 then '01' else '1.5' end;
      ts_expect_format_error(
        c_q_score
      , ts_response_of('"s":{"type":"score","score":0,"probabilities":{"0":0.5,"' || l_key || '":0.5}}')
      , '%level "' || l_key || '"%outside 0 to 2%', 'level ' || l_key);
    end loop key_loop;

    ts_expect_format_error(
      c_q_choice
    , ts_response_of('"c":{"type":"choice","choice":"a","probabilities":[0.5,0.5]}')
    , '%probabilities is not an object%', 'probabilities array');
  end ts_probability_unknown_key;


  procedure ts_answers_bad_shape
  as
  begin
    ts_expect_format_error(c_q_pred, '{"model":"jev-1.13.0","answers":[]}', '%no answers object%', 'answers is an array');
    ts_expect_format_error(c_q_pred, '{"model":"jev-1.13.0"}', '%no answers object%', 'no answers');
    ts_expect_format_error(c_q_pred, '{"model":"jev-1.13.0","answers":{"p":42}}', '%"p" is not an object%', 'answer is a number');
    ts_expect_format_error(c_q_pred, '{"model":"jev-1.13.0","answers":{"p":null}}', '%"p" is not an object%', 'answer is null');
  end ts_answers_bad_shape;


  -- ---- distribution checks ---------------------------------------------------------------

  procedure ts_sum_not_one_warns
  as
    l_result json_object_t;
  begin
    -- 0.5 + 0.3 + 0.1 = 0.9
    l_result := ts_decide_with(c_q_choice, '"c":{"type":"choice","choice":"a","probabilities":{"a":0.5,"b":0.3,"c":0.1},"confidence":0.5}');
    ut.expect(warnings_of(l_result).get_size, 'choice: one warning').to_equal(1);
    ut.expect(warnings_of(l_result).get_string(0), 'choice: text').to_be_like('%"c"%sum to 0.9%');
    ut.expect(l_result.get_object('answers').get_object('c').get_string('choice'), 'the answer is still returned').to_equal('a');

    -- a sum off by the 2-decimal rounding over three entries (0.34 + 0.33 + 0.32) is fine
    l_result := ts_decide_with(c_q_choice, '"c":{"type":"choice","choice":"a","probabilities":{"a":0.34,"b":0.33,"c":0.32}}');
    ut.expect(warnings_of(l_result).get_size, 'sum 0.99 over three entries').to_equal(0);

    -- the score distribution is checked as well
    l_result := ts_decide_with(c_q_score, '"s":{"type":"score","score":0,"probabilities":{"0":0.5,"1":0,"2":0}}');
    ut.expect(warnings_of(l_result).get_size, 'score: one warning').to_equal(1);
    ut.expect(warnings_of(l_result).get_string(0), 'score: text').to_be_like('%"s"%sum to 0.5%');
  end ts_sum_not_one_warns;


  procedure ts_mean_rounding_tolerated
  as
    l_result json_object_t;
  begin
    -- the recorded case: jev rounds the mean of the unrounded probabilities (1.96), the rounded ones give 1.97
    l_result := ts_decide_with(c_q_score, '"s":{"type":"score","score":1.96,"probabilities":{"0":0,"1":0.03,"2":0.97}}');
    ut.expect(warnings_of(l_result).get_size, 'score 1.96 for the mean 1.97').to_equal(0);

    -- two levels: the allowed deviation is 0.01
    l_result := ts_decide_with(
      '{"s":{"type":"score","instructions":"i","criteria":["a","b"]}}'
    , '"s":{"type":"score","score":0.5,"probabilities":{"0":0.5,"1":0.5}}');
    ut.expect(warnings_of(l_result).get_size, 'two levels exact').to_equal(0);
    l_result := ts_decide_with(
      '{"s":{"type":"score","instructions":"i","criteria":["a","b"]}}'
    , '"s":{"type":"score","score":0.52,"probabilities":{"0":0.5,"1":0.5}}');
    ut.expect(warnings_of(l_result).get_size, 'two levels 0.52 for 0.5').to_equal(1);
  end ts_mean_rounding_tolerated;


  procedure ts_mean_mismatch_warns
  as
    l_result json_object_t;
  begin
    -- the mean of 0.2, 0.3, 0.5 over the levels 0, 1, 2 is 1.3; the answer says 0
    l_result := ts_decide_with(c_q_score, '"s":{"type":"score","score":0,"probabilities":{"0":0.2,"1":0.3,"2":0.5},"confidence":0.4}');

    ut.expect(warnings_of(l_result).get_size, 'one warning').to_equal(1);
    ut.expect(warnings_of(l_result).get_string(0), 'text').to_be_like('%"s"%score 0 differs%mean 1.3%');
    ut.expect(l_result.get_object('answers').get_object('s').get_number('score'), 'the reported score is kept').to_equal(0);
  end ts_mean_mismatch_warns;


  -- ---- credential and logging --------------------------------------------------------------

  procedure ts_credential_resolution
  as
    l_result json_object_t;
  begin
    -- the common web credential
    ts_enqueue('triage_response');
    l_result := ts_decide(c_triage_state, ts_triage_questions);
    ut.expect(uc_ai_test_http_mock.request(1).credential, 'common credential').to_equal(c_credential);

    -- the TypeSafe credential alone
    uc_ai.g_apex_web_credential := null;
    uc_ai_typesafe.g_apex_web_credential := 'TS_WIRE_CREDENTIAL';
    ts_enqueue('triage_response');
    l_result := ts_decide(c_triage_state, ts_triage_questions);
    ut.expect(uc_ai_test_http_mock.request(2).credential, 'TypeSafe credential').to_equal('TS_WIRE_CREDENTIAL');
    ut.expect(uc_ai_test_http_mock.request_header(2, 'Authorization'), 'no key header with a TypeSafe credential').to_be_null();

    -- both: the common one wins, as for the other providers
    uc_ai.g_apex_web_credential := c_credential;
    ts_enqueue('triage_response');
    l_result := ts_decide(c_triage_state, ts_triage_questions);
    ut.expect(uc_ai_test_http_mock.request(3).credential, 'both set').to_equal(c_credential);

    -- reset_globals clears the TypeSafe credential
    uc_ai.reset_globals;
    ut.expect(uc_ai_typesafe.g_apex_web_credential, 'reset_globals').to_be_null();
  end ts_credential_resolution;


  /*
   * The one test that reads uc_ai_get_key for TypeSafe, because the header is only
   * built when no credential is named. The key is never printed: a failure shows
   * true or false. Without a typesafe branch in the schema's uc_ai_get_key the
   * lookup fails and the call must fail with that error before any request.
   */
  procedure ts_key_from_get_key
  as
    l_result  json_object_t;
    l_key     varchar2(4000 char);
    l_has_key boolean := false;
    l_code    number;
    l_message varchar2(4000 char);
  begin
    begin
      l_key     := uc_ai_get_key(uc_ai.c_provider_typesafe);
      l_has_key := l_key is not null;
    exception
      when others then
        l_has_key := false;
    end;
    l_key := null;

    uc_ai.g_apex_web_credential := null;
    uc_ai_typesafe.g_apex_web_credential := null;

    if l_has_key then
      ts_enqueue('triage_response');
      l_result := ts_decide(c_triage_state, ts_triage_questions);

      ut.expect(uc_ai_test_http_mock.request(1).credential, 'no credential named').to_be_null();
      ut.expect(uc_ai_test_http_mock.request_header(1, 'Authorization') like 'Bearer %', 'Authorization is a Bearer header').to_be_true();
    else
      ts_enqueue('triage_response');
      ts_try(c_triage_state, ts_triage_questions, l_code, l_message);

      ut.expect(l_code, 'no key: code').to_equal(-20001);
      ut.expect(l_message, 'no key: message names the provider').to_be_like('%typesafe%');
      ut.expect(uc_ai_test_http_mock.request_count, 'no key: no request sent').to_equal(0);
    end if;
  end ts_key_from_get_key;


  procedure ts_body_is_not_logged
  as
    c_state_marker constant varchar2(60 char) := 'UC_AI_TS_STATE_MARKER_0123456789';
    l_last_id      number;
    l_result       json_object_t;
    l_count        pls_integer;
    l_calls        pls_integer;

    function marker_rows(p_last_id in number, p_marker in varchar2) return pls_integer
    as
      l_rows pls_integer;
    begin
      select count(*)
        into l_rows
        from logger_logs
       where id > p_last_id
         and (instr(text, p_marker) > 0 or sys.dbms_lob.instr(extra, p_marker) > 0);
      return l_rows;
    end marker_rows;
  begin
    select nvl(max(id), 0) into l_last_id from logger_logs;
    ts_enqueue('triage_response');

    -- control: the query does find a marker when something logs it
    uc_ai_logger.log('control row', 'test_uc_ai_decisions_wire.ts_body_is_not_logged', c_state_marker);
    ut.expect(marker_rows(l_last_id, c_state_marker), 'control row is found').to_equal(1);

    l_result := ts_decide(c_state_marker, ts_triage_questions);

    ut.expect(instr(uc_ai_test_http_mock.request(1).body, c_state_marker), 'the request does hold the state').to_be_greater_than(0);
    ut.expect(marker_rows(l_last_id, c_state_marker), 'no log row holds the state').to_equal(1);

    -- the call is logged: provider, model, count and size
    select count(*)
      into l_calls
      from logger_logs
     where id > l_last_id
       and text like 'Calling TypeSafe at ' || c_ts_url || '%'
       and text like '%Web Credential: ' || c_credential
       and extra like 'model=jev-latest, questions=3, files=0, request size=%';
    ut.expect(l_calls, 'the call is logged with counts').to_equal(1);

    select count(*)
      into l_count
      from logger_logs
     where id > l_last_id
       and (sys.dbms_lob.instr(extra, '"questions"') > 0
         or sys.dbms_lob.instr(extra, '"model":"jev-latest"') > 0
         or sys.dbms_lob.instr(extra, 'Authorization') > 0
         or sys.dbms_lob.instr(extra, 'Bearer') > 0);
    ut.expect(l_count, 'no log row holds a request body or a header').to_equal(0);
  end ts_body_is_not_logged;


  procedure ts_422_echo_is_not_logged
  as
    c_marker constant varchar2(60 char) := 'UC_AI_TS_ECHO_MARKER_9876543210';
    l_last_id number;
    l_code    number;
    l_message varchar2(4000 char);
    l_rows    pls_integer;
  begin
    select nvl(max(id), 0) into l_last_id from logger_logs;

    uc_ai_test_http_mock.enqueue(
      '{"detail":[{"type":"missing","loc":["body","questions"],"msg":"Field required","input":{"state":"' || c_marker || '"}}]}'
    , 422);
    ts_try('state', json_object_t.parse(c_q_pred), l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(uc_ai_error.c_err_provider_response);
    ut.expect(l_message, 'message').to_be_like('%HTTP 422: Field required (param questions)');
    ut.expect(l_message, 'the echo is not in the message').not_to_be_like('%' || c_marker || '%');

    select count(*)
      into l_rows
      from logger_logs
     where id > l_last_id
       and (instr(text, c_marker) > 0 or sys.dbms_lob.instr(extra, c_marker) > 0);
    ut.expect(l_rows, 'no log row holds the echo').to_equal(0);
  end ts_422_echo_is_not_logged;

  -- ---- OpenRouter Decisions (alpha) -------------------------------------------------------------
  -- The request is the TypeSafe one with another URL, so the neutral mapping is covered by the
  -- TypeSafe tests above. These tests cover what is OpenRouter's own: URL, model, credential,
  -- error body and the usage object. triage_response and error_unknown_model_response were
  -- recorded from the API on 2026-10-08 (the request id is redacted).

  procedure or_enqueue(p_sample in varchar2 default 'triage_response', p_status in pls_integer default 200)
  as
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get(c_or_prefix || p_sample), p_status);
  end or_enqueue;


  function or_decide(
    p_state     in clob
  , p_questions in json_object_t
  , p_options   in json_object_t default null
  , p_files     in json_array_t default null
  , p_model     in varchar2 default null
  ) return json_object_t
  as
  begin
    return uc_ai.decide(
      p_state     => p_state
    , p_questions => p_questions
    , p_provider  => uc_ai.c_provider_openrouter
    , p_model     => p_model
    , p_options   => p_options
    , p_files     => p_files
    );
  end or_decide;


  procedure or_url_model_and_request_shape
  as
    l_result json_object_t;
    l_body   json_object_t;
  begin
    or_enqueue;

    l_result := or_decide(c_triage_state, ts_triage_questions);

    test_uc_ai_wire.expect_url(1, c_or_url);
    test_uc_ai_wire.expect_request(1, c_or_prefix || 'triage_request');
    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_body.get_string('model'), 'default model').to_equal('typesafe/jev-1.13');
    ut.expect(l_body.get_string('state'), 'state').to_equal(c_triage_state);
    ut.expect(ts_wire_question(1, 'wants_refund').get_string('type'), 'boolean is noul').to_equal('noul');
    ut.expect(ts_wire_question(1, 'department').get_string('type'), 'choice').to_equal('choice');
    ut.expect(ts_wire_question(1, 'severity').get_array('criteria').get_size, 'levels').to_equal(3);
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Content-Type'), 'Content-Type').to_equal('application/json');
    ut.expect(uc_ai_test_http_mock.request(1).credential, 'credential name').to_equal(c_credential);
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Authorization'), 'no key header when a credential is named').to_be_null();
    test_uc_ai_wire.expect_all_consumed(1);
  end or_url_model_and_request_shape;


  procedure or_base_url_replaces_host
  as
    l_result json_object_t;
  begin
    or_enqueue;
    or_enqueue;

    uc_ai.g_base_url := 'https://proxy.example.test/or';
    l_result := or_decide(c_triage_state, ts_triage_questions);

    uc_ai.g_base_url := 'https://proxy.example.test/or/';
    l_result := or_decide(c_triage_state, ts_triage_questions);

    test_uc_ai_wire.expect_url(1, 'https://proxy.example.test/or/alpha/decisions');
    test_uc_ai_wire.expect_url(2, 'https://proxy.example.test/or/alpha/decisions');
    test_uc_ai_wire.expect_all_consumed(2);
  end or_base_url_replaces_host;


  procedure or_response_mapping
  as
    l_result  json_object_t;
    l_answers json_object_t;
    l_meta    json_object_t;
  begin
    or_enqueue;

    l_result  := or_decide(c_triage_state, ts_triage_questions);
    l_answers := l_result.get_object('answers');
    l_meta    := l_result.get_object('provider_metadata');

    ut.expect(l_answers.get_object('department').get_string('choice'), 'choice').to_equal('billing');
    ut.expect(l_answers.get_object('severity').get_number('score'), 'score').to_equal(1.97);
    ut.expect(l_answers.get_object('wants_refund').get_string('type'), 'boolean type').to_equal('boolean');
    ut.expect(l_answers.get_object('wants_refund').get_number('probability'), 'boolean probability').to_equal(0.99);
    ut.expect(l_result.get_string('model'), 'the model that answered').to_equal('typesafe/jev-1.13-20260917');
    ut.expect(l_result.get_object('usage').get_number('input_tokens'), 'input tokens').to_equal(458);
    ut.expect(l_result.get_object('usage').get_number('output_tokens'), 'output tokens').to_equal(71);
    ut.expect(l_meta.get_object('usage').get_number('cost'), 'cost in provider usage').to_equal(0.000019236);
    ut.expect(l_meta.get_object('confidence').get_number('severity'), 'confidence').to_equal(0.95);
    ut.expect(l_meta.get_object('confidence').has('wants_refund'), 'noul has no confidence').to_be_false();
    ut.expect(warnings_of(l_result).get_size, 'no warnings').to_equal(0);
  end or_response_mapping;


  procedure or_error_body
  as
    l_code    number := 0;
    l_message varchar2(4000 char);
    l_result  json_object_t;
  begin
    or_enqueue('error_unknown_model_response', 400);

    begin
      l_result := or_decide('state', json_object_t.parse(c_q_pred), p_model => 'typesafe/jev-nope');
    exception
      when others then
        l_code    := sqlcode;
        l_message := sqlerrm;
    end;

    ut.expect(l_code, 'code').to_equal(uc_ai_error.c_err_provider_response);
    ut.expect(l_message, 'message').to_be_like('%provider OpenRouter: HTTP 400: Model typesafe/jev-nope does not exist%');
  end or_error_body;


  procedure or_extra_body_and_options
  as
    l_result json_object_t;
    l_body   json_object_t;
  begin
    or_enqueue;

    l_result := or_decide(
      c_triage_state
    , ts_triage_questions
    , json_object_t.parse(
        '{"safety_identifier":"user-4711","extra_body":{"provider":{"zdr":true,"only":["TypeSafe"]},"model":"evil","state":"evil","questions":[]}}'));

    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_body.get_object('provider').get_boolean('zdr'), 'provider preferences').to_be_true();
    ut.expect(l_body.get_string('model'), 'model wins').to_equal('typesafe/jev-1.13');
    ut.expect(l_body.get_string('state'), 'state wins').to_equal(c_triage_state);
    ut.expect(key_count(l_body.get_object('questions')), 'questions win').to_equal(3);
    ut.expect(l_body.has('safety_identifier'), 'safety_identifier is OpenAI only').to_be_false();
    ut.expect(warnings_of(l_result).get_size, 'one warning').to_equal(1);
    ut.expect(warnings_of(l_result).get_string(0), 'warning').to_be_like('%safety_identifier%not supported for provider openrouter%');
  end or_extra_body_and_options;


  procedure or_credential_resolution
  as
    l_result json_object_t;
  begin
    or_enqueue;
    l_result := or_decide(c_triage_state, ts_triage_questions);
    ut.expect(uc_ai_test_http_mock.request(1).credential, 'common credential').to_equal(c_credential);

    uc_ai.g_apex_web_credential := null;
    uc_ai_openrouter.g_apex_web_credential := 'OR_WIRE_CREDENTIAL';
    or_enqueue;
    l_result := or_decide(c_triage_state, ts_triage_questions);
    ut.expect(uc_ai_test_http_mock.request(2).credential, 'OpenRouter credential').to_equal('OR_WIRE_CREDENTIAL');
    ut.expect(uc_ai_test_http_mock.request_header(2, 'Authorization'), 'no key header with a credential').to_be_null();

    uc_ai.g_apex_web_credential := c_credential;
    or_enqueue;
    l_result := or_decide(c_triage_state, ts_triage_questions);
    ut.expect(uc_ai_test_http_mock.request(3).credential, 'both set').to_equal(c_credential);
  end or_credential_resolution;


  procedure or_files_unsupported
  as
    l_files  json_array_t := json_array_t();
    l_code   number := 0;
    l_msg    varchar2(4000 char);
    l_result json_object_t;
  begin
    l_files.append(uc_ai_message_api.create_file_content('image/png', 'AAAA', 'a.png'));

    begin
      l_result := or_decide('state', json_object_t.parse(c_q_pred), p_files => l_files);
    exception
      when others then
        l_code := sqlcode;
        l_msg  := sqlerrm;
    end;

    ut.expect(l_code, 'code').to_equal(-20508);
    ut.expect(l_msg, 'message').to_be_like('%text only%');
    ut.expect(uc_ai_test_http_mock.request_count, 'no request is sent').to_equal(0);
  end or_files_unsupported;

end test_uc_ai_decisions_wire;
/
