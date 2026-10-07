create or replace package body test_uc_ai_decisions as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5040): the error tests catch the raised error to assert on its code and message
  -- @dblinter ignore(g-4395): the sizes just above the provider limits are the point of the limit test
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on its message; a backtrace adds nothing

  -- Named on every call so no request asks uc_ai_get_key for a key.
  c_credential constant varchar2(30 char) := 'WIRE_DECISIONS_CREDENTIAL';

  c_valid_questions constant varchar2(500 char) := '{"p":{"type":"boolean","instructions":"Is it?"}}';


  -- ---- helpers ---------------------------------------------------------------

  /*
   * Runs uc_ai.decide and asserts the error and that no request was sent.
   */
  procedure expect_error(
    p_questions in json_object_t
  , p_code      in number
  , p_like      in varchar2
  , p_label     in varchar2
  , p_state     in clob default 'state'
  , p_files     in json_array_t default null
  , p_options   in json_object_t default null
  , p_provider  in varchar2 default uc_ai.c_provider_openai
  )
  as
    l_result json_object_t;
    l_code   number := 0;
    l_msg    varchar2(4000 char);
  begin
    begin
      l_result := uc_ai.decide(
        p_state     => p_state
      , p_questions => p_questions
      , p_provider  => p_provider
      , p_files     => p_files
      , p_options   => p_options
      );
    exception
      when others then
        l_code := sqlcode;
        l_msg  := sqlerrm;
    end;

    ut.expect(l_code, p_label || ': code').to_equal(p_code);
    ut.expect(l_msg, p_label || ': message').to_be_like(p_like);
    ut.expect(uc_ai_test_http_mock.request_count, p_label || ': requests sent').to_equal(0);
  end expect_error;


  /*
   * A question set with one question p_id of the given definition.
   */
  function one_question(
    p_id         in varchar2
  , p_definition in varchar2
  ) return json_object_t
  as
    l_questions json_object_t := json_object_t();
  begin
    l_questions.put(p_id, json_object_t.parse(p_definition));
    return l_questions;
  end one_question;


  procedure expect_invalid(
    p_definition in varchar2
  , p_like       in varchar2
  , p_label      in varchar2
  )
  as
  begin
    expect_error(one_question('q', p_definition), uc_ai_error.c_err_invalid_config, p_like, p_label);
  end expect_invalid;


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
    uc_ai.reset_globals;
  end unregister_mock;


  procedure reset_state
  as
  begin
    uc_ai.reset_globals;
    uc_ai_test_http_mock.reset;
    uc_ai.g_apex_web_credential := c_credential;
  end reset_state;


  -- ---- provider ----------------------------------------------------------------

  procedure unknown_provider
  as
  begin
    expect_error(json_object_t.parse(c_valid_questions), uc_ai_error.c_err_unknown_provider, '%null%openai%', 'null', p_provider => null);
    expect_error(json_object_t.parse(c_valid_questions), -20306, '%nope%openai%', 'unknown', p_provider => 'nope');
    -- providers that chat but have no decision API
    expect_error(json_object_t.parse(c_valid_questions), -20306, '%anthropic%openai%', 'anthropic', p_provider => uc_ai.c_provider_anthropic);
    expect_error(json_object_t.parse(c_valid_questions), -20306, '%google%openai%', 'google', p_provider => uc_ai.c_provider_google);
  end unknown_provider;


  procedure provider_before_questions
  as
  begin
    expect_error(null, -20306, '%nope%', 'bad provider and null questions', p_provider => 'nope');
  end provider_before_questions;


  procedure valid_input_reaches_transport
  as
    l_result json_object_t;
  begin
    -- the control for every test below: the same call with good input is sent
    uc_ai_test_http_mock.enqueue('{"model":"gpt-6-luna","answers":[{"type":"predicate","name":"p","probability":0.5}]}');

    l_result := uc_ai.decide('state', json_object_t.parse(c_valid_questions), uc_ai.c_provider_openai);

    ut.expect(uc_ai_test_http_mock.request_count, 'requests sent').to_equal(1);
    ut.expect(l_result.get_object('answers').get_object('p').get_number('probability'), 'probability').to_equal(0.5);
  end valid_input_reaches_transport;


  -- ---- questions ----------------------------------------------------------------

  procedure bad_question_id
  as
    l_ids sys.odcivarchar2list := sys.odcivarchar2list(
      '1a', '_a', 'a-b', 'a b', 'a.b', 'a:b', 'ä', 'a[0]', 'a' || chr(10), rpad('a', 65, 'b'));
  begin
    <<id_loop>>
    for i in 1 .. l_ids.count loop
      expect_error(
        one_question(l_ids(i), '{"type":"boolean","instructions":"x"}')
      , uc_ai_error.c_err_invalid_config
      , '%question id%'
      , 'id ' || i
      );
    end loop id_loop;
  end bad_question_id;


  procedure questions_null_or_empty
  as
    l_questions json_object_t := json_object_t();
  begin
    expect_error(null, uc_ai_error.c_err_invalid_config, '%questions%null%', 'null');
    expect_error(json_object_t(), uc_ai_error.c_err_invalid_config, '%questions%empty%', 'empty');

    l_questions.put('q', 'not an object');
    expect_error(l_questions, uc_ai_error.c_err_invalid_config, '%"q"%JSON object%', 'string');

    l_questions := json_object_t();
    l_questions.put('q', json_array_t());
    expect_error(l_questions, uc_ai_error.c_err_invalid_config, '%"q"%JSON object%', 'array');

    -- one bad question among good ones
    l_questions := json_object_t.parse('{"good":{"type":"boolean","instructions":"x"},"bad":{"type":"nope","instructions":"x"}}');
    expect_error(l_questions, uc_ai_error.c_err_invalid_config, '%"bad"%', 'second question');
  end questions_null_or_empty;


  procedure bad_question_type
  as
  begin
    expect_invalid('{"instructions":"x"}', '%"q"%type is missing%', 'no type');
    expect_invalid('{"type":null,"instructions":"x"}', '%type is missing%', 'null type');
    expect_invalid('{"type":5,"instructions":"x"}', '%type is missing%', 'number type');
    expect_invalid('{"type":"","instructions":"x"}', '%type "" is not supported%', 'empty type');
    expect_invalid('{"type":"text","instructions":"x"}', '%type "text" is not supported%', 'unknown type');
    expect_invalid('{"type":"predicate","instructions":"x"}', '%type "predicate" is not supported%', 'wire name predicate');
    expect_invalid('{"type":"noul","instructions":"x"}', '%type "noul" is not supported%', 'wire name noul');
    expect_invalid('{"type":"Boolean","instructions":"x"}', '%not supported%', 'case matters');
  end bad_question_type;


  procedure bad_instructions
  as
  begin
    expect_invalid('{"type":"boolean"}', '%"q"%instructions are missing%', 'missing');
    expect_invalid('{"type":"boolean","instructions":null}', '%instructions are missing%', 'null');
    expect_invalid('{"type":"boolean","instructions":""}', '%instructions are missing%', 'empty');
    expect_invalid('{"type":"boolean","instructions":"   "}', '%instructions are missing%', 'blank');
    expect_invalid('{"type":"boolean","instructions":5}', '%instructions are missing%', 'number');
    expect_invalid('{"type":"choice","criteria":{"a":null,"b":null}}', '%instructions are missing%', 'choice without instructions');
  end bad_instructions;


  procedure bad_choice_criteria
  as
  begin
    expect_invalid('{"type":"choice","instructions":"x"}', '%"q"%needs criteria%', 'missing');
    expect_invalid('{"type":"choice","instructions":"x","criteria":null}', '%needs criteria%', 'null');
    expect_invalid('{"type":"choice","instructions":"x","criteria":["a","b"]}', '%needs criteria%', 'array');
    expect_invalid('{"type":"choice","instructions":"x","criteria":"a,b"}', '%needs criteria%', 'string');
    expect_invalid('{"type":"choice","instructions":"x","criteria":{}}', '%at least 2 options%found 0%', 'empty object');
    expect_invalid('{"type":"choice","instructions":"x","criteria":{"only":"one"}}', '%at least 2 options%found 1%', 'one option');
    expect_invalid('{"type":"choice","instructions":"x","criteria":{"a":5,"b":"y"}}', '%description of option "a"%', 'number description');
    expect_invalid('{"type":"choice","instructions":"x","criteria":{"":"x","b":"y"}}', '%option name is empty%', 'empty option name');
  end bad_choice_criteria;


  procedure bad_score_criteria
  as
  begin
    expect_invalid('{"type":"score","instructions":"x"}', '%"q"%needs criteria%', 'missing');
    expect_invalid('{"type":"score","instructions":"x","criteria":null}', '%needs criteria%', 'null');
    expect_invalid('{"type":"score","instructions":"x","criteria":{"0":"a","1":"b"}}', '%needs criteria%', 'object');
    expect_invalid('{"type":"score","instructions":"x","criteria":[]}', '%at least 2 levels%found 0%', 'empty array');
    expect_invalid('{"type":"score","instructions":"x","criteria":["one"]}', '%at least 2 levels%found 1%', 'one level');
    expect_invalid('{"type":"score","instructions":"x","criteria":["a",5]}', '%description of level 1%', 'number level');
  end bad_score_criteria;


  procedure bad_boolean_criteria
  as
  begin
    expect_invalid('{"type":"boolean","instructions":"x","criteria":["a"]}', '%criteria of a boolean question must be an object%', 'array');
    expect_invalid('{"type":"boolean","instructions":"x","criteria":{"maybe":"x"}}', '%allows the keys true and false, not "maybe"%', 'other key');
    expect_invalid('{"type":"boolean","instructions":"x","criteria":{"true":5}}', '%criteria.true must be a string%', 'number value');
  end bad_boolean_criteria;


  procedure provider_limits
  as
    l_options  json_object_t := json_object_t();
    l_levels   json_array_t := json_array_t();
    l_question json_object_t;
    l_questions json_object_t;
  begin
    <<option_loop>>
    for i in 1 .. 256 loop
      l_options.put_null('o' || i);
    end loop option_loop;
    l_question := json_object_t();
    l_question.put('type', 'choice');
    l_question.put('instructions', 'x');
    l_question.put('criteria', l_options);
    l_questions := json_object_t();
    l_questions.put('c', l_question);
    expect_error(l_questions, uc_ai_error.c_err_unsupported_content, '%256 options in question "c"%at most 255%', '256 options');

    <<level_loop>>
    for i in 1 .. 11 loop
      l_levels.append('level ' || i);
    end loop level_loop;
    l_question := json_object_t();
    l_question.put('type', 'score');
    l_question.put('instructions', 'x');
    l_question.put('criteria', l_levels);
    l_questions := json_object_t();
    l_questions.put('s', l_question);
    expect_error(l_questions, -20508, '%11 levels in question "s"%at most 10%', '11 levels');
  end provider_limits;


  -- ---- state and files ---------------------------------------------------------

  procedure empty_state
  as
    l_questions json_object_t := json_object_t.parse(c_valid_questions);
    l_empty     json_array_t := json_array_t();
  begin
    expect_error(l_questions, uc_ai_error.c_err_invalid_config, '%state%empty%', 'null', p_state => null);
    expect_error(l_questions, -20503, '%state%', 'blank', p_state => '   ');
    expect_error(l_questions, -20503, '%state%', 'line feeds', p_state => chr(10) || chr(10));
    expect_error(l_questions, -20503, '%state%', 'empty files array', p_state => null, p_files => l_empty);
  end empty_state;


  procedure unsupported_media_type
  as
    l_questions json_object_t := json_object_t.parse(c_valid_questions);
    l_types     sys.odcivarchar2list := sys.odcivarchar2list('application/pdf', 'image/gif', 'text/plain', 'image/svg+xml', 'image/avif');
    l_files     json_array_t;
  begin
    <<type_loop>>
    for i in 1 .. l_types.count loop
      l_files := json_array_t();
      l_files.append(uc_ai_message_api.create_file_content(l_types(i), 'AAAA', 'f'));
      expect_error(
        l_questions
      , uc_ai_error.c_err_unsupported_content
      , '%' || l_types(i) || '%Supported: image/png, image/jpeg, image/webp%'
      , l_types(i)
      , p_files => l_files
      );
    end loop type_loop;

    -- the second file is the bad one
    l_files := json_array_t();
    l_files.append(uc_ai_message_api.create_file_content('image/png', 'AAAA', 'ok.png'));
    l_files.append(uc_ai_message_api.create_file_content('application/pdf', 'AAAA', 'bad.pdf'));
    expect_error(l_questions, -20508, '%application/pdf for file 2%', 'second file', p_files => l_files);
  end unsupported_media_type;


  procedure bad_file_shape
  as
    l_questions json_object_t := json_object_t.parse(c_valid_questions);
    l_files     json_array_t;
  begin
    l_files := json_array_t('["a string"]');
    expect_error(l_questions, uc_ai_error.c_err_invalid_config, '%file 1%create_file_content%', 'not an object', p_files => l_files);

    l_files := json_array_t('[{"type":"file","data":"AAAA"}]');
    expect_error(l_questions, -20503, '%file 1%mediaType is missing%', 'no media type', p_files => l_files);

    l_files := json_array_t('[{"type":"file","mediaType":"image/png"}]');
    expect_error(l_questions, -20503, '%file 1%data is missing%', 'no data', p_files => l_files);

    l_files := json_array_t('[{"type":"file","mediaType":"image/png","data":""}]');
    expect_error(l_questions, -20503, '%file 1%data is missing%', 'empty data', p_files => l_files);

    l_files := json_array_t('[{"type":"text","text":"hi"}]');
    expect_error(l_questions, -20503, '%file 1%type must be file%', 'a text content', p_files => l_files);
  end bad_file_shape;


  -- ---- options -------------------------------------------------------------------

  procedure bad_options
  as
    l_questions json_object_t := json_object_t.parse(c_valid_questions);
  begin
    expect_error(l_questions, uc_ai_error.c_err_invalid_config, '%safety_identifier%string%', 'safety_identifier', p_options => json_object_t.parse('{"safety_identifier":5}'));
    expect_error(l_questions, -20503, '%extra_body%object%', 'extra_body array', p_options => json_object_t.parse('{"extra_body":[1]}'));
    expect_error(l_questions, -20503, '%extra_body%object%', 'extra_body string', p_options => json_object_t.parse('{"extra_body":"x"}'));
  end bad_options;

end test_uc_ai_decisions;
/
