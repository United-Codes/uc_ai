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

  procedure refusal_raises
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    -- the recorded refusal: "gay" is refused, the sibling "religion" is answered
    enqueue('refusal_response');

    try_decide(
      'I love cooking pasta with my partner on Sundays and we just adopted a dog.'
    , json_object_t.parse(
        '{"gay":{"type":"boolean","instructions":"The author is gay."}'
        || ',"religion":{"type":"choice","instructions":"What is the author''s religion?","criteria":{"christian":null,"muslim":null,"jewish":null,"none":null}}}')
    , null, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(uc_ai_error.c_err_decision_refused);
    ut.expect(l_message, 'the refused id').to_be_like('%gay%');
    ut.expect(l_message, 'the sibling id is not named').not_to_be_like('%religion%');
    ut.expect(l_message, 'the sibling answer does not leak').not_to_be_like('%0.97%');
    ut.expect(l_message, 'no sibling choice').not_to_be_like('%none%');
    test_uc_ai_wire.expect_all_consumed(1);
  end refusal_raises;


  procedure refusal_among_valid_answers
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    enqueue('refusal_illposed_response');

    try_decide(
      'The site is down for all customers.'
    , json_object_t.parse(
        '{"lottery":{"type":"boolean","instructions":"Will the next Euromillions draw contain the number 7?"}'
        || ',"nonsense":{"type":"choice","instructions":"Pick the colour of the number seven''s smell.","criteria":{"red":null,"blue":null}}}')
    , null, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20309);
    ut.expect(l_message, 'the refused id').to_be_like('%nonsense%');
    ut.expect(l_message, 'the answered id is not named').not_to_be_like('%lottery%');
    ut.expect(l_message, 'the answered probability does not leak').not_to_be_like('%0.47%');
  end refusal_among_valid_answers;


  procedure refusal_without_name
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    enqueue('refusal_no_name_response');

    try_decide('x', json_object_t.parse(c_q_pred), null, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20309);
    ut.expect(l_message, 'placeholder for the missing name').to_be_like('%(no name)%');
  end refusal_without_name;


  procedure refusal_raw_is_logged
  as
    l_code    number;
    l_message varchar2(4000 char);
    l_last_id number;
    l_rows    pls_integer;
  begin
    select nvl(max(id), 0) into l_last_id from logger_logs;

    enqueue('refusal_response');
    try_decide(
      'text'
    , json_object_t.parse(
        '{"gay":{"type":"boolean","instructions":"The author is gay."}'
        || ',"religion":{"type":"choice","instructions":"r","criteria":{"christian":null,"muslim":null,"jewish":null,"none":null}}}')
    , null, null, l_code, l_message);

    -- the sibling answer is not in the error but the logger keeps the whole response
    select count(*)
      into l_rows
      from logger_logs
     where id > l_last_id
       and logger_level = 2
       and sys.dbms_lob.instr(extra, '"name":"religion"') > 0;

    ut.expect(l_code, 'error code').to_equal(-20309);
    ut.expect(l_rows, 'one error row holds the raw response').to_equal(1);
  end refusal_raw_is_logged;


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

end test_uc_ai_decisions_wire;
/
