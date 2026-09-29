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


  /*
   * OCI needs a compartment and a signing credential; both are named on the OCI
   * globals only, so a Mistral call in the same test does not see them.
   */
  procedure setup_oci
  as
  begin
    uc_ai_oci.g_compartment_id      := get_oci_compratment_id;
    uc_ai_oci.g_region              := 'eu-frankfurt-1';
    uc_ai_oci.g_apex_web_credential := 'OCI_KEY';
  end setup_oci;


  function oci_pdf_ocr(p_options in json_object_t default null) return json_object_t
  as
  begin
    setup_oci;
    return uc_ai.ocr(
      p_document   => uc_ai_test_utils.get_emp_pdf
    , p_media_type => 'application/pdf'
    , p_provider   => uc_ai.c_provider_oci
    , p_options    => p_options
    );
  end oci_pdf_ocr;


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


  /*
   * Same server and credential as test_uc_ai_ollama.
   */
  procedure setup_ollama
  as
  begin
    uc_ai.g_base_url            := 'https://ai.united-codes.com/api';
    uc_ai.g_apex_web_credential := 'OLLAMA';
  end setup_ollama;


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


  procedure oci_pdf
  as
    l_result json_object_t;
    l_blocks json_array_t;
    l_box    json_object_t;
  begin
    l_result := oci_pdf_ocr;

    sys.dbms_output.put_line('markdown: ' || l_result.get_clob('markdown'));

    ut.expect(l_result.get_clob('markdown'), 'markdown').to_be_like('%Dwight%');
    ut.expect(l_result.get_clob('markdown'), 'markdown, last name').to_be_like('%Schrute%');
    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
    ut.expect(l_result.get_array('pages').get_size, 'pages').to_equal(1);
    ut.expect(l_result.get_array('warnings').get_size, 'warnings').to_equal(0);
    ut.expect(l_result.get_string('model'), 'model').to_be_not_null();
    ut.expect(l_result.get_object('raw').has('documentMetadata'), 'raw is the provider response').to_be_true();
    ut.expect(first_page(l_result).get_number('index'), 'index is 0-based').to_equal(0);

    l_blocks := first_page(l_result).get_array('blocks');
    ut.expect(l_blocks.get_size, 'blocks').to_be_greater_than(0);
    <<block_loop>>
    for i in 0 .. l_blocks.get_size - 1 loop
      l_box := treat(l_blocks.get(i) as json_object_t).get_object('box');
      ut.expect(l_box.get_number('x1') between 0 and 1 and l_box.get_number('y1') between 0 and 1
            and l_box.get_number('x2') between 0 and 1 and l_box.get_number('y2') between 0 and 1
        , 'box ' || i || ' is inside 0..1').to_be_true();
    end loop block_loop;
  end oci_pdf;


  procedure oci_pdf_tables
  as
    l_result json_object_t;
  begin
    l_result := oci_pdf_ocr(json_object_t('{"tables":true}'));

    sys.dbms_output.put_line('markdown: ' || l_result.get_clob('markdown'));

    ut.expect(l_result.get_clob('markdown'), 'table row with Scott').to_be_like('%| Michael | Scott |%');
    ut.expect(l_result.get_clob('markdown'), 'table separator').to_be_like('%| --- | --- | --- |%');
    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
  end oci_pdf_tables;


  procedure oci_png_no_text
  as
    l_result json_object_t;
  begin
    setup_oci;
    l_result := uc_ai.ocr(uc_ai_test_utils.get_apple_png, 'image/png', uc_ai.c_provider_oci);

    ut.expect(l_result.get_array('warnings').get_size, 'warnings').to_be_greater_than(0);
    ut.expect(l_result.get_array('warnings').get_string(0), 'warning').to_be_like('FEATURE_NOT_SUPPORTED%');
    ut.expect(sys.dbms_lob.getlength(l_result.get_clob('markdown')), 'no text').to_equal(0);
    ut.expect(l_result.get_array('pages').get_size, 'pages').to_equal(1);
  end oci_png_no_text;


  procedure oci_webp_raises
  as
    l_result json_object_t;
    l_code   number;
  begin
    setup_oci;
    begin
      l_result := uc_ai.ocr(uc_ai_test_utils.get_apple_webp, 'image/webp', uc_ai.c_provider_oci);
      l_code := 0;
    exception
      when others then
        l_code := sqlcode;
    end;

    ut.expect(l_code).to_equal(-20508);
  end oci_webp_raises;


  procedure oci_pages_option
  as
    l_result json_object_t;
  begin
    l_result := oci_pdf_ocr(json_object_t('{"pages":[0]}'));
    ut.expect(l_result.get_array('pages').get_size, 'page 0 is kept').to_equal(1);
    ut.expect(l_result.get_clob('markdown')).to_be_like('%Dwight%');

    l_result := oci_pdf_ocr(json_object_t('{"pages":[1]}'));
    ut.expect(l_result.get_array('pages').get_size, 'page 1 does not exist').to_equal(0);
    ut.expect(sys.dbms_lob.getlength(l_result.get_clob('markdown')), 'no text').to_equal(0);
  end oci_pages_option;


  procedure oci_ocr_text
  as
    l_text clob;
  begin
    setup_oci;
    l_text := uc_ai.ocr_text(uc_ai_test_utils.get_emp_pdf, 'application/pdf', uc_ai.c_provider_oci);

    ut.expect(l_text).to_be_like('%Dwight%');
  end oci_ocr_text;


  procedure ollama_jpeg
  as
    l_result json_object_t;
    l_page   json_object_t;
  begin
    setup_ollama;

    l_result := uc_ai.ocr(
      p_document   => uc_ai_test_utils.get_emp_table_jpeg
    , p_media_type => 'image/jpeg'
    , p_provider   => uc_ai.c_provider_ollama
    , p_model      => 'gemma4:26b'
    );

    sys.dbms_output.put_line('markdown: ' || l_result.get_clob('markdown'));

    ut.expect(lower(l_result.get_clob('markdown')), 'markdown has the first name').to_be_like('%dwight%');
    ut.expect(lower(l_result.get_clob('markdown')), 'markdown has the last name').to_be_like('%schrute%');
    ut.expect(l_result.get_array('pages').get_size, 'pages').to_equal(1);

    l_page := first_page(l_result);
    ut.expect(l_page.get_number('index'), 'index').to_equal(0);
    ut.expect(l_page.has('blocks'), 'no blocks').to_be_false();
    ut.expect(l_result.get_object('usage').has('input_tokens'), 'input_tokens').to_be_true();
    ut.expect(l_result.get_object('usage').has('output_tokens'), 'output_tokens').to_be_true();
    ut.expect(l_result.get_object('usage').get_number('output_tokens'), 'output tokens').to_be_greater_than(0);
    ut.expect(l_result.get_string('model'), 'model').to_be_like('gemma4%');
    ut.expect(l_result.get_object('raw').has('message'), 'raw is the provider response').to_be_true();
  end ollama_jpeg;


  procedure ollama_pdf_raises
  as
    l_result json_object_t;
    l_code   number;
  begin
    setup_ollama;
    begin
      l_result := uc_ai.ocr(
        p_document   => uc_ai_test_utils.get_emp_pdf
      , p_media_type => 'application/pdf'
      , p_provider   => uc_ai.c_provider_ollama
      , p_model      => 'gemma4:26b'
      );
      l_code := 0;
    exception
      when others then
        l_code := sqlcode;
    end;

    ut.expect(l_code).to_equal(-20508);
  end ollama_pdf_raises;


  procedure ollama_null_model
  as
    l_result json_object_t;
    l_code   number;
  begin
    setup_ollama;
    begin
      l_result := uc_ai.ocr(uc_ai_test_utils.get_emp_table_jpeg, 'image/jpeg', uc_ai.c_provider_ollama);
      l_code := 0;
    exception
      when others then
        l_code := sqlcode;
    end;

    ut.expect(l_code).to_equal(-20503);
  end ollama_null_model;


  procedure ollama_unknown_model
  as
    l_result  json_object_t;
    l_code    number;
    l_message varchar2(4000 char);
  begin
    setup_ollama;
    begin
      l_result := uc_ai.ocr(uc_ai_test_utils.get_emp_table_jpeg, 'image/jpeg', uc_ai.c_provider_ollama, 'no-such-model:1b');
      l_code := 0;
    exception
      when others then
        l_code    := sqlcode;
        l_message := sqlerrm;
    end;

    ut.expect(l_code, 'code').to_equal(-20302);
    ut.expect(l_message, 'message').to_be_like('%not found%');
  end ollama_unknown_model;


  procedure cross_provider_pdf
  as
    l_mistral json_object_t;
    l_oci     json_object_t;
  begin
    -- the same words, not the same text: OCR output is not exact and the two differ in layout
    l_mistral := pdf_ocr;
    l_oci     := oci_pdf_ocr(json_object_t('{"tables":true}'));

    ut.expect(l_mistral.get_clob('markdown'), 'Mistral: Dwight').to_be_like('%Dwight%');
    ut.expect(l_mistral.get_clob('markdown'), 'Mistral: Scott').to_be_like('%Scott%');
    ut.expect(l_oci.get_clob('markdown'), 'OCI: Dwight').to_be_like('%Dwight%');
    ut.expect(l_oci.get_clob('markdown'), 'OCI: Scott').to_be_like('%Scott%');
    ut.expect(l_mistral.get_object('usage').get_number('pages'), 'same page count')
      .to_equal(l_oci.get_object('usage').get_number('pages'));
  end cross_provider_pdf;


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
