create or replace package body test_uc_ai_ocr as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5040): the error tests catch the raised error to assert on its code and message
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on its message; a backtrace adds nothing

  procedure reset_state
  as
  begin
    uc_ai.reset_globals;
  end reset_state;


  function pdf_ocr(p_options in json_object_t default null, p_model in varchar2 default null) return json_object_t
  as
  begin
    return uc_ai.ocr(
      p_document   => uc_ai_test_utils.get_emp_pdf
    , p_media_type => 'application/pdf'
    , p_provider   => uc_ai.c_provider_mistral
    , p_model      => p_model
    , p_options    => p_options
    );
  end pdf_ocr;


  function first_page(p_result in json_object_t) return json_object_t
  as
  begin
    return treat(p_result.get_array('pages').get(0) as json_object_t);
  end first_page;


  procedure mistral_pdf
  as
    l_result json_object_t;
    l_blocks json_array_t;
    l_box    json_object_t;
  begin
    l_result := pdf_ocr;

    sys.dbms_output.put_line('markdown: ' || l_result.get_clob('markdown'));

    ut.expect(l_result.get_clob('markdown'), 'markdown').to_be_like('%Dwight%');
    ut.expect(l_result.get_clob('markdown'), 'markdown table').to_be_like('%Schrute%');
    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
    ut.expect(l_result.get_object('usage').get_number('bytes'), 'usage.bytes').to_be_greater_than(0);
    ut.expect(l_result.get_array('pages').get_size, 'pages').to_equal(1);
    ut.expect(l_result.get_string('model'), 'model').to_be_like('mistral-ocr%');
    ut.expect(l_result.get_array('warnings').get_size, 'warnings').to_equal(0);
    ut.expect(l_result.get_object('raw').has('usage_info'), 'raw is the provider response').to_be_true();

    l_blocks := first_page(l_result).get_array('blocks');
    ut.expect(l_blocks.get_size, 'blocks').to_be_greater_than(0);
    <<block_loop>>
    for i in 0 .. l_blocks.get_size - 1 loop
      l_box := treat(l_blocks.get(i) as json_object_t).get_object('box');
      ut.expect(l_box.get_number('x1') between 0 and 1 and l_box.get_number('y1') between 0 and 1
            and l_box.get_number('x2') between 0 and 1 and l_box.get_number('y2') between 0 and 1
        , 'box ' || i || ' is inside 0..1').to_be_true();
    end loop block_loop;
  end mistral_pdf;


  procedure mistral_pdf_media_type_params
  as
    l_result json_object_t;
  begin
    l_result := uc_ai.ocr(uc_ai_test_utils.get_emp_pdf, 'Application/PDF; charset=binary', uc_ai.c_provider_mistral);

    ut.expect(l_result.get_clob('markdown')).to_be_like('%Dwight%');
  end mistral_pdf_media_type_params;


  procedure mistral_png
  as
    l_result json_object_t;
  begin
    l_result := uc_ai.ocr(uc_ai_test_utils.get_apple_png, 'image/png', uc_ai.c_provider_mistral);

    ut.expect(l_result.get_array('pages').get_size, 'pages').to_equal(1);
    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
    ut.expect(l_result.get_clob('markdown'), 'markdown').to_be_not_null();
  end mistral_png;


  procedure mistral_webp
  as
    l_result json_object_t;
  begin
    l_result := uc_ai.ocr(uc_ai_test_utils.get_apple_webp, 'image/webp', uc_ai.c_provider_mistral);

    ut.expect(l_result.get_array('pages').get_size, 'pages').to_equal(1);
    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
  end mistral_webp;


  procedure mistral_pages_option
  as
    l_result json_object_t;
  begin
    l_result := pdf_ocr(json_object_t('{"pages":[0]}'));

    ut.expect(l_result.get_array('pages').get_size, 'pages').to_equal(1);
    ut.expect(l_result.get_clob('markdown')).to_be_like('%Dwight%');
  end mistral_pages_option;


  procedure mistral_tables_option
  as
    l_result json_object_t;
    l_tables json_array_t;
  begin
    l_result := pdf_ocr(json_object_t('{"tables":true}'));

    ut.expect(l_result.get_clob('markdown'), 'markdown holds the table').to_be_like('%Dwight%Schrute%');
    ut.expect(l_result.get_clob('markdown'), 'no dead table link').not_to_be_like('%tbl-0.md%');

    l_tables := treat(l_result.get_object('raw').get_array('pages').get(0) as json_object_t).get_array('tables');
    ut.expect(l_tables.get_size, 'the provider lists the table separately').to_equal(1);
  end mistral_tables_option;


  procedure mistral_confidence_option
  as
    l_result json_object_t;
    l_conf   number;
  begin
    l_result := pdf_ocr(json_object_t('{"confidence_scores_granularity":"page"}'));

    l_conf := first_page(l_result).get_number('confidence');
    sys.dbms_output.put_line('page confidence: ' || l_conf);
    ut.expect(l_conf between 0 and 1, 'page confidence in 0..1').to_be_true();
  end mistral_confidence_option;


  procedure mistral_passthrough_option
  as
    l_result json_object_t;
    l_images json_array_t;
  begin
    l_result := uc_ai.ocr(
      p_document   => uc_ai_test_utils.get_apple_png
    , p_media_type => 'image/png'
    , p_provider   => uc_ai.c_provider_mistral
    , p_options    => json_object_t('{"include_image_base64":true}')
    );

    l_images := treat(l_result.get_object('raw').get_array('pages').get(0) as json_object_t).get_array('images');
    ut.expect(l_images.get_size, 'images in the raw response').to_be_greater_than(0);
    ut.expect(treat(l_images.get(0) as json_object_t).get('image_base64').is_string, 'image_base64 was requested').to_be_true();
  end mistral_passthrough_option;


  procedure mistral_model_4_1
  as
    l_result json_object_t;
  begin
    l_result := pdf_ocr(p_model => uc_ai_mistral.c_model_mistral_ocr_4_1);

    ut.expect(l_result.get_clob('markdown')).to_be_like('%Dwight%');
    ut.expect(l_result.get_string('model')).to_be_like('mistral-ocr%');
  end mistral_model_4_1;


  procedure mistral_bad_model
  as
    l_result json_object_t;
    l_code   number;
    l_msg    varchar2(4000 char);
  begin
    begin
      l_result := pdf_ocr(p_model => 'no-such-ocr-model');
      l_code := 0;
    exception
      when others then
        l_code := sqlcode;
        l_msg  := sqlerrm;
    end;

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_msg, 'message').to_be_like('%Invalid model%no-such-ocr-model%');
  end mistral_bad_model;


  procedure mistral_url_overload
  as
    l_result json_object_t;
  begin
    l_result := uc_ai.ocr(
      p_url      => 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'
    , p_provider => uc_ai.c_provider_mistral
    );

    ut.expect(l_result.get_clob('markdown')).to_be_like('%Dummy PDF file%');
    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
  end mistral_url_overload;


  procedure mistral_ocr_text
  as
    l_text clob;
  begin
    l_text := uc_ai.ocr_text(uc_ai_test_utils.get_emp_pdf, 'application/pdf', uc_ai.c_provider_mistral);

    ut.expect(l_text).to_be_like('%Dwight%');
  end mistral_ocr_text;


  procedure unsupported_media_type
  as
    l_result json_object_t;
    l_code   number;
  begin
    begin
      l_result := uc_ai.ocr(uc_ai_test_utils.get_emp_pdf, 'text/csv', uc_ai.c_provider_mistral);
      l_code := 0;
    exception
      when others then
        l_code := sqlcode;
    end;

    ut.expect(l_code).to_equal(-20508);
  end unsupported_media_type;


  procedure null_provider
  as
    l_result json_object_t;
    l_code   number;
  begin
    begin
      l_result := uc_ai.ocr(uc_ai_test_utils.get_emp_pdf, 'application/pdf', null);
      l_code := 0;
    exception
      when others then
        l_code := sqlcode;
    end;

    ut.expect(l_code).to_equal(-20306);
  end null_provider;

end test_uc_ai_ocr;
/
