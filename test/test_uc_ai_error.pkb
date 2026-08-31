create or replace package body test_uc_ai_error as
  -- @dblinter ignore(g-5040): the tests assert THAT an error is raised; sqlcode/sqlerrm are the assertion
  -- @dblinter ignore(g-5080): the tests assert on sqlerrm itself; a backtrace would only add noise to the test log

  procedure reset_status_code
  as
  begin
    apex_web_service.g_status_code := null;
  end reset_status_code;


  procedure default_template_single_sub
  as
  begin
    begin
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_unknown_provider
      , p0           => 'foo'
      , p_log        => false
      );
      ut.fail('Expected raise_error to raise');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_unknown_provider);
        ut.expect(sqlerrm).to_equal('ORA-20306: Unknown AI provider: foo');
    end;
  end default_template_single_sub;


  procedure default_template_multi_sub
  as
  begin
    begin
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p0           => 'OpenAI'
      , p1           => 'boom'
      , p_log        => false
      );
      ut.fail('Expected raise_error to raise');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_provider_response);
        ut.expect(sqlerrm).to_equal('ORA-20302: Error response from provider OpenAI: boom');
    end;
  end default_template_multi_sub;


  procedure message_override
  as
  begin
    begin
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_unknown_provider
      , p0           => 'a'
      , p1           => 'b'
      , p_message    => 'Custom %0/%1'
      , p_log        => false
      );
      ut.fail('Expected raise_error to raise');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_unknown_provider);
        ut.expect(sqlerrm).to_equal('ORA-20306: Custom a/b');
    end;
  end message_override;


  procedure all_ten_placeholders
  as
  begin
    begin
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p0 => '0', p1 => '1', p2 => '2', p3 => '3', p4 => '4'
      , p5 => '5', p6 => '6', p7 => '7', p8 => '8', p9 => '9'
      , p_message    => '%0%1%2%3%4%5%6%7%8%9'
      , p_log        => false
      );
      ut.fail('Expected raise_error to raise');
    exception
      when others then
        ut.expect(sqlerrm).to_equal('ORA-20503: 0123456789');
    end;
  end all_ten_placeholders;


  procedure unknown_code_fallback
  as
  begin
    begin
      uc_ai_error.raise_error(
        p_error_code => -20999
      , p_log        => false
      );
      ut.fail('Expected raise_error to raise');
    exception
      when others then
        ut.expect(sqlcode).to_equal(-20999);
        ut.expect(sqlerrm).to_equal('ORA-20999: Error -20999');
    end;
  end unknown_code_fallback;


  procedure null_placeholder_renders_empty
  as
  begin
    begin
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_unknown_provider
      , p0           => null
      , p_log        => false
      );
      ut.fail('Expected raise_error to raise');
    exception
      when others then
        -- apex_string.format renders a null placeholder as empty string;
        -- raise_application_error trims the trailing space
        ut.expect(sqlerrm).to_equal('ORA-20306: Unknown AI provider:');
    end;
  end null_placeholder_renders_empty;


  procedure parse_ok_status_200
  as
    l_result json_object_t;
  begin
    apex_web_service.g_status_code := 200;

    l_result := uc_ai_error.parse_json_response(
      p_response => '{"a":1}'
    , p_provider => 'Test'
    , p_scope    => 'test_uc_ai_error.parse_ok_status_200'
    );

    ut.expect(l_result.get_number('a')).to_equal(1);
  end parse_ok_status_200;


  procedure parse_ok_status_null
  as
    l_result json_object_t;
  begin
    apex_web_service.g_status_code := null;

    l_result := uc_ai_error.parse_json_response(
      p_response => '{"ok":true}'
    , p_provider => 'Test'
    , p_scope    => 'test_uc_ai_error.parse_ok_status_null'
    );

    ut.expect(l_result.get_boolean('ok')).to_be_true();
  end parse_ok_status_null;


  procedure parse_http_error_status
  as
    l_result json_object_t;
  begin
    apex_web_service.g_status_code := 404;

    begin
      -- valid JSON body must still fail because of the HTTP status guard
      l_result := uc_ai_error.parse_json_response(
        p_response => '{"code":"404","message":"Entity not found"}'
      , p_provider => 'Test'
      , p_scope    => 'test_uc_ai_error.parse_http_error_status'
      );
      ut.fail('Expected parse_json_response to raise for HTTP 404');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_provider_response);
        ut.expect(sqlerrm).to_be_like('%HTTP 404 from provider%');
        -- error must not be double-wrapped by the OTHERS handler
        ut.expect(sqlerrm).not_to_be_like('%Status Code from provider%');
    end;
  end parse_http_error_status;


  procedure parse_invalid_json
  as
    l_result json_object_t;
  begin
    apex_web_service.g_status_code := 200;

    begin
      l_result := uc_ai_error.parse_json_response(
        p_response => '<html>err</html>'
      , p_provider => 'Test'
      , p_scope    => 'test_uc_ai_error.parse_invalid_json'
      );
      ut.fail('Expected parse_json_response to raise for invalid JSON');
    exception
      when others then
        ut.expect(sqlcode).to_equal(uc_ai_error.c_err_provider_response);
        ut.expect(sqlerrm).to_be_like('%Error response from provider Test%');
        ut.expect(sqlerrm).to_be_like('%Provider response: <html>err</html>%');
    end;
  end parse_invalid_json;

end test_uc_ai_error;
/
