create or replace package body test_uc_ai_message_api as

  function big_clob (
    p_length in pls_integer
  ) return clob
  as
    l_clob  clob;
    l_chunk varchar2(4000 char) := rpad('x', 4000, 'x');
    l_len   pls_integer := 0;
  begin
    sys.dbms_lob.createtemporary(l_clob, true);
    while l_len < p_length loop
      sys.dbms_lob.append(l_clob, substr(l_chunk, 1, least(4000, p_length - l_len)));
      l_len := l_len + least(4000, p_length - l_len);
    end loop;
    return l_clob;
  end big_clob;


  procedure text_content_shape
  as
    l_content json_object_t;
  begin
    l_content := uc_ai_message_api.create_text_content('hi there');

    ut.expect(l_content.get_string('type')).to_equal('text');
    ut.expect(l_content.get_string('text')).to_equal('hi there');
    ut.expect(l_content.has('providerOptions')).to_be_false();
  end text_content_shape;


  procedure text_content_provider_options
  as
    l_content json_object_t;
  begin
    l_content := uc_ai_message_api.create_text_content(
      p_text             => 'hi'
    , p_provider_options => json_object_t('{"openai":{"cacheControl":true}}')
    );

    ut.expect(l_content.has('providerOptions')).to_be_true();
    ut.expect(
      l_content.get_object('providerOptions').get_object('openai').get_boolean('cacheControl')
    ).to_be_true();
  end text_content_provider_options;


  procedure text_content_clob_32k
  as
    l_content json_object_t;
  begin
    l_content := uc_ai_message_api.create_text_content(big_clob(100000));

    ut.expect(sys.dbms_lob.getlength(l_content.get_clob('text'))).to_equal(100000);
  end text_content_clob_32k;


  procedure file_content_clob_overload
  as
    l_content json_object_t;
  begin
    l_content := uc_ai_message_api.create_file_content(
      p_media_type  => 'image/png'
    , p_data_base64 => 'AAAA'
    , p_filename    => 'a.png'
    );

    ut.expect(l_content.get_string('type')).to_equal('file');
    ut.expect(l_content.get_string('mediaType')).to_equal('image/png');
    ut.expect(l_content.get_string('data')).to_equal('AAAA');
    ut.expect(l_content.get_string('filename')).to_equal('a.png');
  end file_content_clob_overload;


  procedure file_content_no_filename
  as
    l_content json_object_t;
  begin
    l_content := uc_ai_message_api.create_file_content(
      p_media_type  => 'application/pdf'
    , p_data_base64 => 'AAAA'
    );

    ut.expect(l_content.has('filename')).to_be_false();
    ut.expect(l_content.has('providerOptions')).to_be_false();
  end file_content_no_filename;


  procedure file_content_blob_overload
  as
    l_source  blob;
    l_content json_object_t;
    l_decoded blob;
  begin
    l_source := to_blob(utl_raw.cast_to_raw('Hello UC AI file content'));

    l_content := uc_ai_message_api.create_file_content(
      p_media_type => 'application/pdf'
    , p_data_blob  => l_source
    , p_filename   => 'test.pdf'
    );

    ut.expect(l_content.get_string('type')).to_equal('file');
    ut.expect(l_content.get_clob('data')).to_be_not_null();

    -- base64 data must decode back to the original bytes
    l_decoded := apex_web_service.clobbase642blob(l_content.get_clob('data'));
    ut.expect(sys.dbms_lob.compare(l_decoded, l_source)).to_equal(0);
  end file_content_blob_overload;


  procedure reasoning_content_shape
  as
    l_content json_object_t;
  begin
    l_content := uc_ai_message_api.create_reasoning_content('thinking...');

    ut.expect(l_content.get_string('type')).to_equal('reasoning');
    ut.expect(l_content.get_string('text')).to_equal('thinking...');
  end reasoning_content_shape;


  procedure tool_call_content_shape
  as
    l_content json_object_t;
  begin
    l_content := uc_ai_message_api.create_tool_call_content(
      p_tool_call_id => 'call_123'
    , p_tool_name    => 'get_users'
    , p_args         => '{"limit":5}'
    );

    ut.expect(l_content.get_string('type')).to_equal('tool_call');
    ut.expect(l_content.get_string('toolCallId')).to_equal('call_123');
    ut.expect(l_content.get_string('toolName')).to_equal('get_users');
    -- args are stored as the raw string, not parsed
    ut.expect(l_content.get_string('args')).to_equal('{"limit":5}');
  end tool_call_content_shape;


  procedure tool_result_content_shape
  as
    l_content json_object_t;
  begin
    l_content := uc_ai_message_api.create_tool_result_content(
      p_tool_call_id => 'call_123'
    , p_tool_name    => 'get_users'
    , p_result       => 'no users found'
    );

    ut.expect(l_content.get_string('type')).to_equal('tool_result');
    ut.expect(l_content.get_string('toolCallId')).to_equal('call_123');
    ut.expect(l_content.get_string('toolName')).to_equal('get_users');
    ut.expect(l_content.get_string('result')).to_equal('no users found');
  end tool_result_content_shape;


  procedure system_message_shape
  as
    l_message json_object_t;
  begin
    l_message := uc_ai_message_api.create_system_message('You are helpful');

    ut.expect(l_message.get_string('role')).to_equal('system');
    -- system messages carry scalar content, not a content array
    ut.expect(l_message.get_string('content')).to_equal('You are helpful');
  end system_message_shape;


  procedure array_message_shapes
  as
    l_content json_array_t;
    l_message json_object_t;
  begin
    l_content := json_array_t();
    l_content.append(uc_ai_message_api.create_text_content('one'));
    l_content.append(uc_ai_message_api.create_text_content('two'));

    l_message := uc_ai_message_api.create_user_message(l_content);
    ut.expect(l_message.get_string('role')).to_equal('user');
    ut.expect(l_message.get_array('content').get_size).to_equal(2);

    l_message := uc_ai_message_api.create_assistant_message(l_content);
    ut.expect(l_message.get_string('role')).to_equal('assistant');
    ut.expect(l_message.get_array('content').get_size).to_equal(2);

    l_message := uc_ai_message_api.create_tool_message(l_content);
    ut.expect(l_message.get_string('role')).to_equal('tool');
    ut.expect(l_message.get_array('content').get_size).to_equal(2);
  end array_message_shapes;


  procedure simple_user_message
  as
    l_message json_object_t;
    l_element json_object_t;
  begin
    l_message := uc_ai_message_api.create_simple_user_message('What is 1+1?');

    ut.expect(l_message.get_string('role')).to_equal('user');
    ut.expect(l_message.get_array('content').get_size).to_equal(1);

    l_element := treat(l_message.get_array('content').get(0) as json_object_t);
    ut.expect(l_element.get_string('type')).to_equal('text');
    ut.expect(l_element.get_string('text')).to_equal('What is 1+1?');
  end simple_user_message;


  procedure simple_assistant_message
  as
    l_message json_object_t;
    l_element json_object_t;
  begin
    l_message := uc_ai_message_api.create_simple_assistant_message('It is 2.');

    ut.expect(l_message.get_string('role')).to_equal('assistant');
    ut.expect(l_message.get_array('content').get_size).to_equal(1);

    l_element := treat(l_message.get_array('content').get(0) as json_object_t);
    ut.expect(l_element.get_string('type')).to_equal('text');
    ut.expect(l_element.get_string('text')).to_equal('It is 2.');
  end simple_assistant_message;


  procedure user_message_with_files
  as
    l_files   uc_ai_message_api.t_files;
    l_message json_object_t;
    l_content json_array_t;
    l_text    json_object_t;
    l_file    json_object_t;
    l_decoded blob;
    l_source  blob;
  begin
    l_source := to_blob(utl_raw.cast_to_raw('PDF bytes here'));

    l_files := uc_ai_message_api.t_files();
    l_files.extend;
    l_files(1).media_type := 'application/pdf';
    l_files(1).data_blob  := l_source;
    l_files(1).filename   := 'report.pdf';

    l_message := uc_ai_message_api.create_user_message('Summarize this', l_files);

    ut.expect(l_message.get_string('role')).to_equal('user');

    l_content := l_message.get_array('content');
    -- text block first, then one file block
    ut.expect(l_content.get_size).to_equal(2);

    l_text := treat(l_content.get(0) as json_object_t);
    ut.expect(l_text.get_string('type')).to_equal('text');
    ut.expect(l_text.get_string('text')).to_equal('Summarize this');

    l_file := treat(l_content.get(1) as json_object_t);
    ut.expect(l_file.get_string('type')).to_equal('file');
    ut.expect(l_file.get_string('mediaType')).to_equal('application/pdf');
    ut.expect(l_file.get_string('filename')).to_equal('report.pdf');

    -- base64 data must decode back to the original bytes
    l_decoded := apex_web_service.clobbase642blob(l_file.get_clob('data'));
    ut.expect(sys.dbms_lob.compare(l_decoded, l_source)).to_equal(0);
  end user_message_with_files;


  procedure user_message_empty_files
  as
    l_files   uc_ai_message_api.t_files := uc_ai_message_api.t_files();
    l_message json_object_t;
    l_element json_object_t;
  begin
    -- empty collection behaves like create_simple_user_message
    l_message := uc_ai_message_api.create_user_message('Just text', l_files);

    ut.expect(l_message.get_string('role')).to_equal('user');
    ut.expect(l_message.get_array('content').get_size).to_equal(1);

    l_element := treat(l_message.get_array('content').get(0) as json_object_t);
    ut.expect(l_element.get_string('type')).to_equal('text');
    ut.expect(l_element.get_string('text')).to_equal('Just text');
  end user_message_empty_files;


  procedure user_message_files_no_text
  as
    l_files   uc_ai_message_api.t_files;
    l_message json_object_t;
    l_element json_object_t;
  begin
    l_files := uc_ai_message_api.t_files();
    l_files.extend;
    l_files(1).media_type := 'image/png';
    l_files(1).data_blob  := to_blob(utl_raw.cast_to_raw('png'));

    -- null text -> only the file block, no empty text block
    l_message := uc_ai_message_api.create_user_message(null, l_files);

    ut.expect(l_message.get_array('content').get_size).to_equal(1);

    l_element := treat(l_message.get_array('content').get(0) as json_object_t);
    ut.expect(l_element.get_string('type')).to_equal('file');
    ut.expect(l_element.get_string('mediaType')).to_equal('image/png');
    ut.expect(l_element.has('filename')).to_be_false();
  end user_message_files_no_text;

end test_uc_ai_message_api;
/
