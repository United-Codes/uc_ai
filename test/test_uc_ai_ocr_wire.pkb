create or replace package body test_uc_ai_ocr_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-2160): allow initialzing variables in declare in test packages
  -- @dblinter ignore(g-5040): the error tests catch the raised error to assert on its code and message
  -- @dblinter ignore(g-4395): the fixed size of the large option value is the point of that test
  -- @dblinter ignore(g-5080): the error tests catch the expected exception to assert on its message; a backtrace adds nothing

  -- Named on every call so no request asks uc_ai_get_key for a key.
  c_credential constant varchar2(30 char) := 'WIRE_OCR_CREDENTIAL';

  c_ocr_url constant varchar2(100 char) := 'https://api.mistral.ai/v1/ocr';

  c_sample_pdf         constant varchar2(100 char) := 'mistral/ocr-pdf-response';
  c_sample_pdf_tables  constant varchar2(100 char) := 'mistral/ocr-pdf-tables-response';
  c_sample_png         constant varchar2(100 char) := 'mistral/ocr-png-response';
  c_sample_webp_empty  constant varchar2(100 char) := 'mistral/ocr-webp-empty-response';
  c_sample_bad_model   constant varchar2(100 char) := 'mistral/ocr-invalid-model-response';

  -- a fake OCID: nothing here talks to OCI
  c_oci_compartment constant varchar2(100 char) := 'ocid1.compartment.oc1..wiretestcompartment';

  c_oci_sample_pdf     constant varchar2(100 char) := 'oci/ocr-pdf-text-response';
  c_oci_sample_tables  constant varchar2(100 char) := 'oci/ocr-pdf-tables-response';
  c_oci_sample_png     constant varchar2(100 char) := 'oci/ocr-png-no-text-response';
  c_oci_sample_400     constant varchar2(100 char) := 'oci/ocr-unsupported-type-response';
  c_oci_sample_401     constant varchar2(100 char) := 'oci/ocr-signature-401-response';


  -- ---- helpers ---------------------------------------------------------------

  /*
   * Runs uc_ai.ocr and hands back the error a test expects instead of raising it.
   * po_code is 0 when the call did not raise.
   */
  procedure try_ocr(
    p_document   in blob
  , p_media_type in varchar2
  , p_provider   in varchar2
  , p_options    in json_object_t default null
  , po_code      out number
  , po_message   out varchar2
  )
  as
    l_result json_object_t;
  begin
    po_code := 0;
    l_result := uc_ai.ocr(
      p_document   => p_document
    , p_media_type => p_media_type
    , p_provider   => p_provider
    , p_options    => p_options
    );
  exception
    when others then
      po_code    := sqlcode;
      po_message := sqlerrm;
  end try_ocr;


  function pdf_ocr(p_options in json_object_t default null) return json_object_t
  as
  begin
    return uc_ai.ocr(
      p_document   => uc_ai_test_utils.get_emp_pdf
    , p_media_type => 'application/pdf'
    , p_provider   => uc_ai.c_provider_mistral
    , p_options    => p_options
    );
  end pdf_ocr;


  function document_of(p_index in pls_integer) return json_object_t
  as
  begin
    return uc_ai_test_http_mock.request_json(p_index).get_object('document');
  end document_of;


  function small_blob return blob
  as
  begin
    return sys.utl_raw.cast_to_raw('not a real document, only bytes for the wire');
  end small_blob;


  /*
   * A response with the given page objects and the flat usage_info Mistral sends.
   */
  function pages_response(
    p_pages in varchar2
  , p_usage in varchar2 default '{"pages_processed":2,"doc_size_bytes":100}'
  ) return clob
  as
  begin
    return '{"pages":[' || p_pages || '],"model":"mistral-ocr-latest","document_annotation":null,"usage_info":' || p_usage || '}';
  end pages_response;


  function page(
    p_index    in pls_integer
  , p_markdown in varchar2
  ) return varchar2
  as
  begin
    return '{"index":' || p_index || ',"markdown":"' || p_markdown
        || '","images":[],"tables":[],"dimensions":{"dpi":72,"height":100,"width":200},"blocks":[]}';
  end page;


  function oci_ocr(p_options in json_object_t default null) return json_object_t
  as
  begin
    return uc_ai.ocr(
      p_document   => uc_ai_test_utils.get_emp_pdf
    , p_media_type => 'application/pdf'
    , p_provider   => uc_ai.c_provider_oci
    , p_options    => p_options
    );
  end oci_ocr;


  /*
   * A blob of exactly p_bytes zero bytes.
   */
  function sized_blob(p_bytes in pls_integer) return blob
  as
    l_blob  blob;
    l_left  pls_integer := p_bytes;
    l_chunk pls_integer;
  begin
    sys.dbms_lob.createtemporary(l_blob, true);
    <<chunk_loop>>
    while l_left > 0 loop
      l_chunk := least(l_left, 32000);
      sys.dbms_lob.writeappend(l_blob, l_chunk, sys.utl_raw.copies('00', l_chunk));
      l_left := l_left - l_chunk;
    end loop chunk_loop;
    return l_blob;
  end sized_blob;


  -- Builders for OCI responses. Numbers are passed as text so the JSON keeps a dot.

  function oci_poly(p_x1 in varchar2, p_y1 in varchar2, p_x2 in varchar2, p_y2 in varchar2) return varchar2
  as
  begin
    return '{"normalizedVertices":[{"x":' || p_x1 || ',"y":' || p_y1 || '},{"x":' || p_x2 || ',"y":' || p_y1
        || '},{"x":' || p_x2 || ',"y":' || p_y2 || '},{"x":' || p_x1 || ',"y":' || p_y2 || '}]}';
  end oci_poly;


  function oci_line(p_text in varchar2, p_x1 in varchar2, p_y1 in varchar2, p_x2 in varchar2, p_y2 in varchar2) return varchar2
  as
  begin
    return '{"text":"' || p_text || '","confidence":0.9,"boundingPolygon":' || oci_poly(p_x1, p_y1, p_x2, p_y2) || ',"wordIndexes":[]}';
  end oci_line;


  function oci_cell(p_text in varchar2, p_row in number, p_col in number) return varchar2
  as
  begin
    return '{"text":"' || p_text || '","rowIndex":' || p_row || ',"columnIndex":' || p_col || ',"confidence":1}';
  end oci_cell;


  function oci_row(p_cells in varchar2) return varchar2
  as
  begin
    return '{"cells":' || p_cells || '}';
  end oci_row;


  function oci_table(p_header in varchar2, p_body in varchar2, p_polygon in varchar2) return varchar2
  as
  begin
    return '{"rowCount":2,"columnCount":2,"headerRows":' || p_header || ',"bodyRows":' || p_body
        || ',"footerRows":[],"confidence":0.9,"boundingPolygon":' || nvl(p_polygon, 'null') || '}';
  end oci_table;


  function oci_page(p_number in pls_integer, p_lines in varchar2, p_tables in varchar2 default 'null') return varchar2
  as
  begin
    return '{"pageNumber":' || p_number || ',"dimensions":{"width":10,"height":20,"unit":"INCH"},"words":[],"lines":['
        || p_lines || '],"tables":' || p_tables || '}';
  end oci_page;


  function oci_response(p_pages in varchar2, p_errors in varchar2 default 'null', p_page_count in pls_integer default 1) return clob
  as
  begin
    return '{"documentMetadata":{"pageCount":' || p_page_count || ',"mimeType":"application/pdf"},"pages":[' || p_pages
        || '],"errors":' || p_errors || ',"textExtractionModelVersion":"wire-test-1"}';
  end oci_response;


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
    uc_ai_oci.g_compartment_id := c_oci_compartment;
  end reset_state;


  -- ---- request shape ---------------------------------------------------------

  procedure mistral_url_and_model
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := pdf_ocr;

    test_uc_ai_wire.expect_url(1, c_ocr_url);
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('model')).to_equal('mistral-ocr-latest');
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Content-Type')).to_equal('application/json');
    test_uc_ai_wire.expect_all_consumed(1);
  end mistral_url_and_model;


  procedure mistral_pdf_document_url
  as
    l_result   json_object_t;
    l_document json_object_t;
    l_url      clob;
    c_prefix   constant varchar2(100 char) := 'data:application/pdf;base64,';
    l_b64      clob;
    l_decoded  blob;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := pdf_ocr;

    l_document := document_of(1);
    ut.expect(l_document.get_string('type'), 'document.type').to_equal('document_url');
    ut.expect(l_document.has('image_url'), 'no image_url key').to_be_false();

    l_url := l_document.get_clob('document_url');
    ut.expect(sys.dbms_lob.substr(l_url, length(c_prefix), 1), 'data URL prefix').to_equal(c_prefix);

    -- the payload decodes to the exact bytes of the document
    sys.dbms_lob.createtemporary(l_b64, true);
    sys.dbms_lob.copy(l_b64, l_url, sys.dbms_lob.getlength(l_url) - length(c_prefix), 1, length(c_prefix) + 1);
    l_decoded := apex_web_service.clobbase642blob(l_b64);
    ut.expect(sys.dbms_lob.compare(l_decoded, uc_ai_test_utils.get_emp_pdf), 'decoded payload equals the document').to_equal(0);
    ut.expect(instr(l_b64, chr(10)), 'no line breaks in the payload').to_equal(0);

    test_uc_ai_wire.expect_all_consumed(1);
  end mistral_pdf_document_url;


  procedure mistral_image_url
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_png);
    test_uc_ai_wire.enqueue_sample(c_sample_webp_empty);

    l_result := uc_ai.ocr(uc_ai_test_utils.get_apple_png, 'image/png', uc_ai.c_provider_mistral);
    l_result := uc_ai.ocr(uc_ai_test_utils.get_apple_webp, 'image/webp', uc_ai.c_provider_mistral);

    ut.expect(document_of(1).get_string('type'), 'png document.type').to_equal('image_url');
    ut.expect(sys.dbms_lob.substr(document_of(1).get_clob('image_url'), 22, 1), 'png prefix').to_equal('data:image/png;base64,');
    ut.expect(document_of(2).get_string('type'), 'webp document.type').to_equal('image_url');
    ut.expect(sys.dbms_lob.substr(document_of(2).get_clob('image_url'), 23, 1), 'webp prefix').to_equal('data:image/webp;base64,');

    test_uc_ai_wire.expect_all_consumed(2);
  end mistral_image_url;


  procedure media_type_is_normalized
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := uc_ai.ocr(uc_ai_test_utils.get_emp_pdf, ' Application/PDF; charset=binary ', uc_ai.c_provider_mistral);

    ut.expect(document_of(1).get_string('type')).to_equal('document_url');
    ut.expect(sys.dbms_lob.substr(document_of(1).get_clob('document_url'), 28, 1)).to_equal('data:application/pdf;base64,');
    test_uc_ai_wire.expect_all_consumed(1);
  end media_type_is_normalized;


  procedure image_jpg_alias
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_png);

    l_result := uc_ai.ocr(uc_ai_test_utils.get_apple_png, 'image/JPG', uc_ai.c_provider_mistral);

    ut.expect(document_of(1).get_string('type')).to_equal('image_url');
    ut.expect(sys.dbms_lob.substr(document_of(1).get_clob('image_url'), 23, 1)).to_equal('data:image/jpeg;base64,');
  end image_jpg_alias;


  procedure options_pass_through
  as
    l_result json_object_t;
    l_body   json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := pdf_ocr(json_object_t(
      '{"pages":[0,2],"include_image_base64":true,"image_limit":3,"table_format":"html"'
      || ',"document_annotation_format":{"type":"json_schema","json_schema":{"name":"x"}}'
      || ',"some_future_key":"kept"}'));

    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_body.get_array('pages').to_string, 'pages').to_equal('[0,2]');
    ut.expect(l_body.get_boolean('include_image_base64'), 'include_image_base64').to_be_true();
    ut.expect(l_body.get_number('image_limit'), 'image_limit').to_equal(3);
    ut.expect(l_body.get_string('table_format'), 'table_format').to_equal('html');
    ut.expect(l_body.get_object('document_annotation_format').get_object('json_schema').get_string('name'), 'nested option').to_equal('x');
    ut.expect(l_body.get_string('some_future_key'), 'unknown key is passed on').to_equal('kept');
    ut.expect(l_body.has('extra_body'), 'no extra_body key in the request').to_be_false();
  end options_pass_through;


  procedure huge_option_value
  as
    l_result  json_object_t;
    l_options json_object_t := json_object_t();
    l_huge    clob;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    sys.dbms_lob.createtemporary(l_huge, true);
    <<fill_loop>>
    for i in 1 .. 50 loop
      sys.dbms_lob.writeappend(l_huge, 4000, rpad('x', 4000, 'y'));
    end loop fill_loop;
    l_options.put('document_annotation_prompt', l_huge);

    l_result := pdf_ocr(l_options);

    ut.expect(sys.dbms_lob.getlength(uc_ai_test_http_mock.request_json(1).get_clob('document_annotation_prompt'))).to_equal(200000);
  end huge_option_value;


  procedure tables_sets_table_format
  as
    l_result json_object_t;
    l_body   json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf_tables);
    test_uc_ai_wire.enqueue_sample(c_sample_pdf_tables);
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := pdf_ocr(json_object_t('{"tables":true}'));
    l_result := pdf_ocr(json_object_t('{"tables":true,"table_format":"html"}'));
    l_result := pdf_ocr(json_object_t('{"tables":false}'));

    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('table_format'), 'tables => true').to_equal('markdown');
    ut.expect(uc_ai_test_http_mock.request_json(1).has('tables'), 'tables key not sent (1)').to_be_false();
    ut.expect(uc_ai_test_http_mock.request_json(2).get_string('table_format'), 'explicit table_format wins').to_equal('html');

    l_body := uc_ai_test_http_mock.request_json(3);
    ut.expect(l_body.has('table_format'), 'tables => false sets no table_format').to_be_false();
    ut.expect(l_body.has('tables'), 'tables key not sent (3)').to_be_false();
  end tables_sets_table_format;


  procedure extra_body_merge
  as
    l_result json_object_t;
    l_body   json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := pdf_ocr(json_object_t(
      '{"image_limit":1,"extra_body":{"image_limit":9,"top_secret_flag":true,"model":"evil-model","document":"evil"}}'));

    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_body.get_number('image_limit'), 'extra_body overrides an option').to_equal(9);
    ut.expect(l_body.get_boolean('top_secret_flag'), 'extra_body key is merged').to_be_true();
    ut.expect(l_body.get_string('model'), 'model is reserved').to_equal('mistral-ocr-latest');
    ut.expect(l_body.get('document').is_object, 'document is reserved').to_be_true();
    ut.expect(l_body.get_object('document').get_string('type'), 'document.type').to_equal('document_url');
  end extra_body_merge;


  procedure extra_body_not_object
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_mistral, json_object_t('{"extra_body":"top_p=1"}'), l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20503);
    ut.expect(l_message, 'message').to_be_like('%extra_body%');
    test_uc_ai_wire.expect_all_consumed(0);
  end extra_body_not_object;


  procedure model_override
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := uc_ai.ocr(
      p_document   => uc_ai_test_utils.get_emp_pdf
    , p_media_type => 'application/pdf'
    , p_provider   => uc_ai.c_provider_mistral
    , p_model      => uc_ai_mistral.c_model_mistral_ocr_4_1
    );

    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('model')).to_equal('mistral-ocr-4-1');
    -- the response names the model that ran
    ut.expect(l_result.get_string('model')).to_equal('mistral-ocr-latest');
  end model_override;


  -- ---- authentication --------------------------------------------------------

  procedure credential_replaces_auth_header
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := pdf_ocr;

    ut.expect(uc_ai_test_http_mock.request(1).credential, 'credential static id').to_equal(c_credential);
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Authorization'), 'Authorization').to_be_null();
  end credential_replaces_auth_header;


  /*
   * The one test that reads uc_ai_get_key, because the header is only built when
   * no credential is named. It skips when the schema has no Mistral key. The key
   * is never printed: the assertion is a boolean, so a failure shows true/false.
   */
  procedure bearer_header_without_credential
  as
    l_result json_object_t;
    l_key    varchar2(4000 char);
  begin
    begin
      l_key := uc_ai_get_key(uc_ai.c_provider_mistral);
    exception
      when others then
        l_key := null;
    end;

    if l_key is null then
      return;
    end if;

    uc_ai.g_apex_web_credential := null;
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := pdf_ocr;

    ut.expect(uc_ai_test_http_mock.request(1).credential, 'credential static id').to_be_null();
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Authorization') like 'Bearer %', 'Authorization is a Bearer header').to_be_true();
  end bearer_header_without_credential;


  procedure extra_headers_are_sent
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);
    uc_ai.g_extra_headers('X-Tenant-Id') := 'acme';

    l_result := pdf_ocr;

    ut.expect(uc_ai_test_http_mock.request_header(1, 'X-Tenant-Id')).to_equal('acme');
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Content-Type')).to_equal('application/json');
  end extra_headers_are_sent;


  -- ---- url overload ----------------------------------------------------------

  procedure url_overload_document_url
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := uc_ai.ocr(
      p_url      => 'https://example.com/files/report.pdf'
    , p_provider => uc_ai.c_provider_mistral
    );

    test_uc_ai_wire.expect_url(1, c_ocr_url);
    ut.expect(document_of(1).get_string('type')).to_equal('document_url');
    ut.expect(document_of(1).get_string('document_url')).to_equal('https://example.com/files/report.pdf');
    ut.expect(uc_ai_test_http_mock.request_json(1).get_string('model')).to_equal('mistral-ocr-latest');
    test_uc_ai_wire.expect_all_consumed(1);
  end url_overload_document_url;


  procedure url_overload_image_url
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_png);
    test_uc_ai_wire.enqueue_sample(c_sample_png);
    test_uc_ai_wire.enqueue_sample(c_sample_png);

    l_result := uc_ai.ocr(p_url => 'https://example.com/a/scan.PNG', p_provider => uc_ai.c_provider_mistral);
    l_result := uc_ai.ocr(p_url => 'https://example.com/a/scan.jpg?sig=abc&x=1', p_provider => uc_ai.c_provider_mistral);
    l_result := uc_ai.ocr(p_url => 'data:image/webp;base64,AAAA', p_provider => uc_ai.c_provider_mistral);

    ut.expect(document_of(1).get_string('type'), 'png url').to_equal('image_url');
    ut.expect(document_of(1).get_string('image_url'), 'png url value').to_equal('https://example.com/a/scan.PNG');
    ut.expect(document_of(2).get_string('type'), 'jpg url with query').to_equal('image_url');
    ut.expect(document_of(3).get_string('type'), 'data image url').to_equal('image_url');
  end url_overload_image_url;


  procedure data_url_unsupported_type
  as
    l_result json_object_t;
    l_code   number;
  begin
    begin
      l_result := uc_ai.ocr(p_url => 'data:text/plain;base64,AAAA', p_provider => uc_ai.c_provider_mistral);
      l_code := 0;
    exception
      when others then
        l_code := sqlcode;
    end;

    ut.expect(l_code).to_equal(-20508);
    test_uc_ai_wire.expect_all_consumed(0);
  end data_url_unsupported_type;


  procedure document_and_url_conflict
  as
    l_code number;
    l_result json_object_t;
  begin
    begin
      l_result := uc_ai_ocr.ocr(
        p_document   => small_blob
      , p_url        => 'https://example.com/a.pdf'
      , p_media_type => 'application/pdf'
      , p_provider   => uc_ai.c_provider_mistral
      , p_model      => null
      , p_options    => null
      , p_settings   => uc_ai_settings.build_from_globals
      );
      l_code := 0;
    exception
      when others then
        l_code := sqlcode;
    end;

    ut.expect(l_code).to_equal(-20503);
    test_uc_ai_wire.expect_all_consumed(0);
  end document_and_url_conflict;


  -- ---- response mapping ------------------------------------------------------

  procedure result_shape
  as
    l_result json_object_t;
    l_page   json_object_t;
    l_block  json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := pdf_ocr;

    ut.expect(l_result.get_clob('markdown'), 'markdown').to_be_like('%Dwight | Schrute%');
    ut.expect(l_result.get_array('pages').get_size, 'page count').to_equal(1);
    ut.expect(l_result.get_string('model'), 'model').to_equal('mistral-ocr-latest');
    ut.expect(l_result.get_array('warnings').get_size, 'warnings').to_equal(0);

    l_page := treat(l_result.get_array('pages').get(0) as json_object_t);
    ut.expect(l_page.get_number('index'), 'page index is 0-based').to_equal(0);
    ut.expect(l_page.get_object('dimensions').get_number('width'), 'width').to_equal(720);
    ut.expect(l_page.get_object('dimensions').get_number('height'), 'height').to_equal(1018);
    ut.expect(l_page.get_array('blocks').get_size, 'blocks').to_equal(2);

    l_block := treat(l_page.get_array('blocks').get(1) as json_object_t);
    ut.expect(l_block.get_string('type'), 'block type').to_equal('table');
    ut.expect(l_block.get_string('text'), 'block text').to_be_like('%Michael | Scott%');
    ut.expect(l_block.has('confidence'), 'no confidence unless the provider sends one').to_be_false();

    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
    ut.expect(l_result.get_object('usage').get_number('bytes'), 'usage.bytes').to_equal(34116);
    ut.expect(l_result.get_object('usage').has('input_tokens'), 'no token usage from a page-billed provider').to_be_false();

    -- raw is the provider response as returned
    ut.expect(l_result.get_object('raw').get_object('usage_info').get_number('pages_processed'), 'raw.usage_info').to_equal(1);
    ut.expect(l_result.get_object('raw').get_array('pages').get_size, 'raw.pages').to_equal(1);
  end result_shape;


  procedure box_is_normalized
  as
    l_result json_object_t;
    l_blocks json_array_t;
    l_box    json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := pdf_ocr;

    l_blocks := treat(l_result.get_array('pages').get(0) as json_object_t).get_array('blocks');

    -- pixel box 66,67 - 148,87 on a 720 x 1018 page
    l_box := treat(l_blocks.get(0) as json_object_t).get_object('box');
    ut.expect(l_box.get_number('x1'), 'x1').to_equal(round(66 / 720, 6));
    ut.expect(l_box.get_number('y1'), 'y1').to_equal(round(67 / 1018, 6));
    ut.expect(l_box.get_number('x2'), 'x2').to_equal(round(148 / 720, 6));
    ut.expect(l_box.get_number('y2'), 'y2').to_equal(round(87 / 1018, 6));

    <<block_loop>>
    for i in 0 .. l_blocks.get_size - 1 loop
      l_box := treat(l_blocks.get(i) as json_object_t).get_object('box');
      ut.expect(l_box.get_number('x1') between 0 and 1 and l_box.get_number('y1') between 0 and 1
            and l_box.get_number('x2') between 0 and 1 and l_box.get_number('y2') between 0 and 1
            and l_box.get_number('x1') < l_box.get_number('x2') and l_box.get_number('y1') < l_box.get_number('y2')
        , 'box ' || i || ' is inside the page').to_be_true();
    end loop block_loop;
  end box_is_normalized;


  procedure table_link_is_replaced
  as
    l_result   json_object_t;
    l_markdown clob;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf_tables);

    l_result := pdf_ocr(json_object_t('{"tables":true}'));

    -- the recorded provider markdown holds a link, the neutral one holds the table
    ut.expect(l_result.get_object('raw').get_array('pages').to_clob, 'raw keeps the link').to_be_like('%[tbl-0.md](tbl-0.md)%');
    l_markdown := l_result.get_clob('markdown');
    ut.expect(l_markdown, 'markdown holds the table').to_be_like('%Dwight | Schrute | dwight.schrute@dundermifflin.com%');
    ut.expect(l_markdown, 'no dead link').not_to_be_like('%tbl-0.md%');
    ut.expect(treat(l_result.get_array('pages').get(0) as json_object_t).get_clob('markdown'), 'page markdown').not_to_be_like('%tbl-0.md%');
  end table_link_is_replaced;


  procedure pages_are_joined
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(pages_response(
      page(0, 'First page') || ',' || page(1, null) || ',' || page(2, 'Second\n\nparagraph')));

    l_result := pdf_ocr;

    ut.expect(l_result.get_clob('markdown')).to_equal(to_clob('First page' || chr(10) || chr(10) || 'Second' || chr(10) || chr(10) || 'paragraph'));
    ut.expect(l_result.get_array('pages').get_size, 'all pages are kept').to_equal(3);
    ut.expect(treat(l_result.get_array('pages').get(2) as json_object_t).get_number('index'), 'index of page 3').to_equal(2);
  end pages_are_joined;


  procedure usage_info_null_is_guarded
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(pages_response(page(0, 'A'), 'null'));
    uc_ai_test_http_mock.enqueue('{"pages":[' || page(0, 'B') || ']}');

    l_result := pdf_ocr;
    ut.expect(l_result.get_object('usage').get_size, 'usage_info null').to_equal(0);
    ut.expect(l_result.get_clob('markdown')).to_equal(to_clob('A'));

    l_result := pdf_ocr;
    ut.expect(l_result.get_object('usage').get_size, 'usage_info missing').to_equal(0);
    ut.expect(l_result.get_string('model'), 'model falls back to the requested one').to_equal('mistral-ocr-latest');
    ut.expect(l_result.get_clob('markdown')).to_equal(to_clob('B'));
  end usage_info_null_is_guarded;


  procedure empty_page_is_not_an_error
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_webp_empty);

    l_result := uc_ai.ocr(uc_ai_test_utils.get_apple_webp, 'image/webp', uc_ai.c_provider_mistral);

    ut.expect(sys.dbms_lob.getlength(l_result.get_clob('markdown')), 'markdown is empty').to_equal(0);
    ut.expect(l_result.get_array('pages').get_size, 'one page').to_equal(1);
    ut.expect(treat(l_result.get_array('pages').get(0) as json_object_t).get_array('blocks').get_size, 'no blocks').to_equal(0);
    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
  end empty_page_is_not_an_error;


  procedure page_confidence
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue('{"pages":[{"index":0,"markdown":"A","dimensions":{"width":10,"height":10},'
      || '"confidence_scores":{"average_page_confidence_score":0.97,"minimum_page_confidence_score":0.5},'
      || '"blocks":[{"top_left_x":0,"top_left_y":0,"bottom_right_x":5,"bottom_right_y":5,"content":"A","confidence_scores":0.9,"type":"text"}]}]}');

    l_result := pdf_ocr(json_object_t('{"confidence_scores_granularity":"page"}'));

    ut.expect(treat(l_result.get_array('pages').get(0) as json_object_t).get_number('confidence'), 'page confidence').to_equal(0.97);
    ut.expect(treat(treat(l_result.get_array('pages').get(0) as json_object_t).get_array('blocks').get(0) as json_object_t).get_number('confidence'), 'block confidence').to_equal(0.9);
  end page_confidence;


  procedure ocr_text_equals_markdown
  as
    l_result json_object_t;
    l_text   clob;
  begin
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    l_result := pdf_ocr;
    l_text := uc_ai.ocr_text(
      p_document   => uc_ai_test_utils.get_emp_pdf
    , p_media_type => 'application/pdf'
    , p_provider   => uc_ai.c_provider_mistral
    );

    ut.expect(l_text).to_equal(l_result.get_clob('markdown'));
    ut.expect(l_text).to_be_like('List of users:%Dwight | Schrute%');
  end ocr_text_equals_markdown;


  -- ---- OCI Document Understanding --------------------------------------------

  procedure oci_url_from_region
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    -- the default region of uc_ai_oci
    l_result := oci_ocr;

    uc_ai_oci.g_region := 'eu-frankfurt-1';
    l_result := oci_ocr;

    -- base_url replaces the host; a trailing slash does not double
    uc_ai.g_base_url := 'https://example.test/oci/';
    l_result := oci_ocr;

    test_uc_ai_wire.expect_url(1, 'https://document.aiservice.us-ashburn-1.oci.oraclecloud.com/20221109/actions/analyzeDocument');
    test_uc_ai_wire.expect_url(2, 'https://document.aiservice.eu-frankfurt-1.oci.oraclecloud.com/20221109/actions/analyzeDocument');
    test_uc_ai_wire.expect_url(3, 'https://example.test/oci/20221109/actions/analyzeDocument');
    test_uc_ai_wire.expect_all_consumed(3);
  end oci_url_from_region;


  procedure oci_content_type_exact
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    l_result := oci_ocr;

    -- OCI signs this header: a charset makes every call fail with 401
    ut.expect(uc_ai_test_http_mock.request_header(1, 'Content-Type'), 'Content-Type').to_equal('application/json');

    uc_ai.g_extra_headers('X-Tenant-Id') := 'acme';
    l_result := oci_ocr;
    ut.expect(uc_ai_test_http_mock.request_header(2, 'Content-Type'), 'Content-Type with extra headers').to_equal('application/json');
    ut.expect(uc_ai_test_http_mock.request_header(2, 'X-Tenant-Id'), 'extra header').to_equal('acme');
  end oci_content_type_exact;


  procedure oci_compartment_and_document
  as
    l_result   json_object_t;
    l_body     json_object_t;
    l_document json_object_t;
    l_b64      clob;
    l_decoded  blob;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    l_result := oci_ocr;

    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_body.get_string('compartmentId'), 'compartmentId').to_equal(c_oci_compartment);

    l_document := l_body.get_object('document');
    ut.expect(l_document.get_string('source'), 'document.source').to_equal('INLINE');

    l_b64 := l_document.get_clob('data');
    l_decoded := apex_web_service.clobbase642blob(l_b64);
    ut.expect(sys.dbms_lob.compare(l_decoded, uc_ai_test_utils.get_emp_pdf), 'decoded payload equals the document').to_equal(0);
    ut.expect(instr(l_b64, chr(10)), 'no line breaks in the payload').to_equal(0);
    ut.expect(l_body.has('model'), 'OCI has no model in the request').to_be_false();
    test_uc_ai_wire.expect_all_consumed(1);
  end oci_compartment_and_document;


  procedure oci_default_features
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    l_result := oci_ocr;

    ut.expect(uc_ai_test_http_mock.request_json(1).get_array('features').to_string).to_equal('[{"featureType":"TEXT_EXTRACTION"}]');
  end oci_default_features;


  procedure oci_tables_feature
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_tables);
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    l_result := oci_ocr(json_object_t('{"tables":true}'));
    l_result := oci_ocr(json_object_t('{"tables":false}'));
    l_result := oci_ocr(json_object_t('{"tables":true,"features":[{"featureType":"KEY_VALUE_EXTRACTION"}]}'));

    ut.expect(uc_ai_test_http_mock.request_json(1).get_array('features').to_string, 'tables => true')
      .to_equal('[{"featureType":"TEXT_EXTRACTION"},{"featureType":"TABLE_EXTRACTION"}]');
    ut.expect(uc_ai_test_http_mock.request_json(2).get_array('features').to_string, 'tables => false')
      .to_equal('[{"featureType":"TEXT_EXTRACTION"}]');
    ut.expect(uc_ai_test_http_mock.request_json(3).get_array('features').to_string, 'a passed features array wins')
      .to_equal('[{"featureType":"KEY_VALUE_EXTRACTION"}]');
    ut.expect(uc_ai_test_http_mock.request_json(1).has('tables'), 'tables is not an OCI key').to_be_false();
  end oci_tables_feature;


  procedure oci_options_pass_through
  as
    l_result json_object_t;
    l_body   json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    l_result := oci_ocr(json_object_t(
      '{"language":"DEU","documentType":"INVOICE","features":[{"featureType":"TEXT_EXTRACTION","generateSearchablePdf":true}]'
      || ',"some_future_key":"kept","pages":[0],"tables":true}'));

    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_body.get_string('language'), 'language').to_equal('DEU');
    ut.expect(l_body.get_string('documentType'), 'documentType').to_equal('INVOICE');
    ut.expect(l_body.get_array('features').to_string, 'features').to_equal('[{"featureType":"TEXT_EXTRACTION","generateSearchablePdf":true}]');
    ut.expect(l_body.get_string('some_future_key'), 'unknown key is passed on').to_equal('kept');
    ut.expect(l_body.has('pages'), 'pages is a neutral option').to_be_false();
    ut.expect(l_body.has('tables'), 'tables is a neutral option').to_be_false();
    ut.expect(l_body.has('extra_body'), 'no extra_body key').to_be_false();
  end oci_options_pass_through;


  procedure oci_extra_body_merge
  as
    l_result json_object_t;
    l_body   json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    l_result := oci_ocr(json_object_t(
      '{"language":"ENG","extra_body":{"language":"FRA","top_secret_flag":true,"compartmentId":"evil","document":"evil"}}'));

    l_body := uc_ai_test_http_mock.request_json(1);
    ut.expect(l_body.get_string('language'), 'extra_body overrides an option').to_equal('FRA');
    ut.expect(l_body.get_boolean('top_secret_flag'), 'extra_body key is merged').to_be_true();
    ut.expect(l_body.get_string('compartmentId'), 'compartmentId is reserved').to_equal(c_oci_compartment);
    ut.expect(l_body.get('document').is_object, 'document is reserved').to_be_true();
  end oci_extra_body_merge;


  procedure oci_invalid_options
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_oci, json_object_t('{"features":"TEXT_EXTRACTION"}'), l_code, l_message);
    ut.expect(l_code, 'features code').to_equal(-20503);
    ut.expect(l_message, 'features message').to_be_like('%features%');

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_oci, json_object_t('{"extra_body":"x"}'), l_code, l_message);
    ut.expect(l_code, 'extra_body code').to_equal(-20503);
    ut.expect(l_message, 'extra_body message').to_be_like('%extra_body%');

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_oci, json_object_t('{"pages":"1"}'), l_code, l_message);
    ut.expect(l_code, 'pages code').to_equal(-20503);
    ut.expect(l_message, 'pages message').to_be_like('%pages%');

    test_uc_ai_wire.expect_all_consumed(0);
  end oci_invalid_options;


  procedure oci_missing_compartment
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_oci.g_compartment_id := null;

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_oci, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20502);
    ut.expect(l_message, 'message').to_be_like('%OCI%g_compartment_id%');
    test_uc_ai_wire.expect_all_consumed(0);
  end oci_missing_compartment;


  procedure oci_credential
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    l_result := oci_ocr;
    ut.expect(uc_ai_test_http_mock.request(1).credential, 'general credential').to_equal(c_credential);

    uc_ai.g_apex_web_credential := null;
    uc_ai_oci.g_apex_web_credential := 'WIRE_OCI_ONLY';
    l_result := oci_ocr;
    ut.expect(uc_ai_test_http_mock.request(2).credential, 'OCI credential').to_equal('WIRE_OCI_ONLY');
    ut.expect(uc_ai_test_http_mock.request_header(2, 'Authorization'), 'no Authorization header').to_be_null();
  end oci_credential;


  procedure oci_media_types
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_png);
    test_uc_ai_wire.enqueue_sample(c_oci_sample_png);
    test_uc_ai_wire.enqueue_sample(c_oci_sample_png);

    l_result := uc_ai.ocr(small_blob, 'image/jpg', uc_ai.c_provider_oci);
    l_result := uc_ai.ocr(small_blob, 'image/TIFF; charset=binary', uc_ai.c_provider_oci);
    l_result := uc_ai.ocr(small_blob, 'image/png', uc_ai.c_provider_oci);

    test_uc_ai_wire.expect_all_consumed(3);
  end oci_media_types;


  procedure oci_unsupported_media_type
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    try_ocr(uc_ai_test_utils.get_apple_webp, 'image/webp', uc_ai.c_provider_oci, null, l_code, l_message);
    ut.expect(l_code, 'webp code').to_equal(-20508);
    ut.expect(l_message, 'webp message').to_be_like('%image/webp%oci%application/pdf%image/png%image/jpeg%image/tiff%');

    try_ocr(small_blob, 'image/gif', uc_ai.c_provider_oci, null, l_code, l_message);
    ut.expect(l_code, 'gif code').to_equal(-20508);

    try_ocr(small_blob, 'text/plain', uc_ai.c_provider_oci, null, l_code, l_message);
    ut.expect(l_code, 'text code').to_equal(-20508);

    try_ocr(small_blob, null, uc_ai.c_provider_oci, null, l_code, l_message);
    ut.expect(l_code, 'null type code').to_equal(-20508);

    test_uc_ai_wire.expect_all_consumed(0);
  end oci_unsupported_media_type;


  procedure oci_document_size_limit
  as
    l_code    number;
    l_message varchar2(4000 char);
    l_result  json_object_t;
  begin
    try_ocr(sized_blob(8388609), 'application/pdf', uc_ai.c_provider_oci, null, l_code, l_message);
    ut.expect(l_code, 'error code').to_equal(-20503);
    ut.expect(l_message, 'message').to_be_like('%8388609 bytes%8 MB%');
    test_uc_ai_wire.expect_all_consumed(0);

    -- the limit itself is allowed
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);
    l_result := uc_ai.ocr(sized_blob(8388608), 'application/pdf', uc_ai.c_provider_oci);
    test_uc_ai_wire.expect_all_consumed(1);
  end oci_document_size_limit;


  procedure oci_url_overload_raises
  as
    l_result  json_object_t;
    l_code    number;
    l_message varchar2(4000 char);
  begin
    begin
      l_result := uc_ai.ocr(p_url => 'https://example.com/files/report.pdf', p_provider => uc_ai.c_provider_oci);
      l_code := 0;
    exception
      when others then
        l_code    := sqlcode;
        l_message := sqlerrm;
    end;
    ut.expect(l_code, 'https url').to_equal(-20508);
    ut.expect(l_message, 'message names the provider').to_be_like('%oci%blob%');

    begin
      l_result := uc_ai.ocr(p_url => 'data:image/png;base64,AAAA', p_provider => uc_ai.c_provider_oci);
      l_code := 0;
    exception
      when others then
        l_code := sqlcode;
    end;
    ut.expect(l_code, 'data url').to_equal(-20508);

    test_uc_ai_wire.expect_all_consumed(0);
  end oci_url_overload_raises;


  procedure oci_result_shape
  as
    l_result json_object_t;
    l_page   json_object_t;
    l_block  json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    l_result := oci_ocr;

    -- one line per text line, in the order OCI sends them
    ut.expect(l_result.get_clob('markdown'), 'markdown start')
      .to_be_like('List of users:' || chr(10) || 'First Name' || chr(10) || 'Last Name' || chr(10) || 'Email' || chr(10) || 'Michael%');
    ut.expect(l_result.get_clob('markdown'), 'markdown holds the row')
      .to_be_like('%Dwight' || chr(10) || 'Schrute' || chr(10) || 'dwight.schrute@dundermifflin.com%');
    ut.expect(l_result.get_clob('markdown'), 'no table without the table feature').not_to_be_like('%| ---%');
    ut.expect(l_result.get_array('pages').get_size, 'page count').to_equal(1);
    ut.expect(l_result.get_array('warnings').get_size, 'warnings').to_equal(0);

    l_page := treat(l_result.get_array('pages').get(0) as json_object_t);
    ut.expect(l_page.get_number('index'), 'page index is 0-based').to_equal(0);
    ut.expect(l_page.get_object('dimensions').get_number('width'), 'width').to_be_between(8.26, 8.27);
    ut.expect(l_page.get_object('dimensions').get_string('unit'), 'unit').to_equal('INCH');
    ut.expect(l_page.get_array('blocks').get_size, 'blocks').to_equal(22);

    l_block := treat(l_page.get_array('blocks').get(0) as json_object_t);
    ut.expect(l_block.get_string('type'), 'block type').to_equal('text');
    ut.expect(l_block.get_string('text'), 'block text').to_equal('List of users:');
    ut.expect(l_block.get_number('confidence'), 'block confidence').to_be_between(0, 1);

    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
    ut.expect(l_result.get_object('usage').has('bytes'), 'OCI reports no bytes').to_be_false();

    -- raw is the provider response as returned
    ut.expect(l_result.get_object('raw').get_object('documentMetadata').get_string('mimeType'), 'raw.documentMetadata').to_equal('application/pdf');
    ut.expect(treat(l_result.get_object('raw').get_array('pages').get(0) as json_object_t).get_array('lines').get_size, 'raw lines').to_equal(22);
    ut.expect(treat(l_result.get_object('raw').get_array('pages').get(0) as json_object_t).get_number('pageNumber'), 'raw keeps the 1-based number').to_equal(1);
  end oci_result_shape;


  procedure oci_box_from_polygon
  as
    l_result   json_object_t;
    l_blocks   json_array_t;
    l_block    json_object_t;
    l_box      json_object_t;
    l_vertices json_array_t;
    l_raw_line json_object_t;
    l_min_x    number;
    l_max_x    number;
    l_min_y    number;
    l_max_y    number;
    l_x        number;
    l_y        number;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    l_result := oci_ocr;

    l_blocks := treat(l_result.get_array('pages').get(0) as json_object_t).get_array('blocks');
    l_raw_line := treat(treat(l_result.get_object('raw').get_array('pages').get(0) as json_object_t).get_array('lines').get(1) as json_object_t);
    l_vertices := l_raw_line.get_object('boundingPolygon').get_array('normalizedVertices');

    <<vertex_loop>>
    for i in 0 .. l_vertices.get_size - 1 loop
      l_x := treat(l_vertices.get(i) as json_object_t).get_number('x');
      l_y := treat(l_vertices.get(i) as json_object_t).get_number('y');
      l_min_x := least(nvl(l_min_x, l_x), l_x);
      l_max_x := greatest(nvl(l_max_x, l_x), l_x);
      l_min_y := least(nvl(l_min_y, l_y), l_y);
      l_max_y := greatest(nvl(l_max_y, l_y), l_y);
    end loop vertex_loop;

    -- block 1 is the line "First Name"
    l_block := treat(l_blocks.get(1) as json_object_t);
    l_box := l_block.get_object('box');
    ut.expect(l_box.get_number('x1'), 'x1').to_equal(round(l_min_x, 6));
    ut.expect(l_box.get_number('y1'), 'y1').to_equal(round(l_min_y, 6));
    ut.expect(l_box.get_number('x2'), 'x2').to_equal(round(l_max_x, 6));
    ut.expect(l_box.get_number('y2'), 'y2').to_equal(round(l_max_y, 6));
    ut.expect(l_block.get_array('polygon').get_size, 'polygon is kept').to_equal(4);
    ut.expect(treat(l_block.get_array('polygon').get(0) as json_object_t).get_number('x'), 'polygon x of the first vertex')
      .to_equal(treat(l_vertices.get(0) as json_object_t).get_number('x'));

    <<block_loop>>
    for i in 0 .. l_blocks.get_size - 1 loop
      l_box := treat(l_blocks.get(i) as json_object_t).get_object('box');
      ut.expect(l_box.get_number('x1') between 0 and 1 and l_box.get_number('y1') between 0 and 1
            and l_box.get_number('x2') between 0 and 1 and l_box.get_number('y2') between 0 and 1
            and l_box.get_number('x1') < l_box.get_number('x2') and l_box.get_number('y1') < l_box.get_number('y2')
        , 'box ' || i || ' is inside the page').to_be_true();
    end loop block_loop;
  end oci_box_from_polygon;


  procedure oci_table_markdown_recorded
  as
    l_result   json_object_t;
    l_markdown clob;
    l_blocks   json_array_t;
    l_block    json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_tables);

    l_result := oci_ocr(json_object_t('{"tables":true}'));

    l_markdown := l_result.get_clob('markdown');
    ut.expect(l_markdown, 'title, then the table')
      .to_be_like('List of users:' || chr(10) || chr(10) || '| First Name | Last Name | Email |' || chr(10) || '| --- | --- | --- |' || chr(10)
                  || '| Michael | Scott | michael.scott@dundermifflin.com |' || chr(10) || '%');
    ut.expect(l_markdown, 'last row')
      .to_be_like('%' || chr(10) || '| Kevin | Malone | kevin.malone@dundermifflin.com |');
    -- the lines inside the table are not repeated: "Dwight" is in the table only
    ut.expect(regexp_count(l_markdown, 'Dwight'), 'Dwight once').to_equal(1);
    ut.expect(regexp_count(l_markdown, chr(10) || '\|'), 'header, separator and six rows').to_equal(8);

    l_blocks := treat(l_result.get_array('pages').get(0) as json_object_t).get_array('blocks');
    ut.expect(l_blocks.get_size, '22 text blocks and one table block').to_equal(23);
    l_block := treat(l_blocks.get(22) as json_object_t);
    ut.expect(l_block.get_string('type'), 'last block type').to_equal('table');
    ut.expect(l_block.get_string('text'), 'table block text').to_be_like('| First Name |%| Kevin | Malone |%');
    ut.expect(l_block.get_object('box').get_number('y1'), 'table box y1').to_be_between(0, 1);
    ut.expect(l_block.get_array('polygon').get_size, 'table polygon').to_equal(4);
    ut.expect(l_result.get_object('raw').get_string('tableExtractionModelVersion'), 'raw').to_be_not_null();
  end oci_table_markdown_recorded;


  procedure oci_reading_order
  as
    l_result json_object_t;
    l_table  varchar2(4000 char);
  begin
    l_table := oci_table(
      '[' || oci_row('[' || oci_cell('H1', 0, 0) || ',' || oci_cell('H2', 0, 1) || ']') || ']'
    , '[' || oci_row('[' || oci_cell('A', 1, 0) || ',' || oci_cell('B', 1, 1) || ']') || ']'
    , oci_poly('0.0', '0.09', '0.9', '0.14')
    );

    -- Title, the table lines H1 H2 A B (the table repeats them), After
    uc_ai_test_http_mock.enqueue(oci_response(oci_page(1,
      oci_line('Title', '0.1', '0.05', '0.3', '0.07') || ','
      || oci_line('H1', '0.1', '0.10', '0.2', '0.12') || ','
      || oci_line('H2', '0.5', '0.10', '0.6', '0.12') || ','
      || oci_line('A', '0.1', '0.13', '0.2', '0.14') || ','
      || oci_line('B', '0.5', '0.13', '0.6', '0.14') || ','
      || oci_line('After', '0.1', '0.30', '0.3', '0.32')
    , '[' || l_table || ']')));

    l_result := oci_ocr;

    ut.expect(l_result.get_clob('markdown'))
      .to_equal(to_clob('Title' || chr(10) || chr(10) || '| H1 | H2 |' || chr(10) || '| --- | --- |' || chr(10) || '| A | B |' || chr(10) || chr(10) || 'After'));

    -- a wider gap than one line height starts a paragraph
    uc_ai_test_http_mock.enqueue(oci_response(oci_page(1,
      oci_line('L1', '0.1', '0.10', '0.3', '0.12') || ','
      || oci_line('L2', '0.1', '0.125', '0.3', '0.145') || ','
      || oci_line('L3', '0.1', '0.20', '0.3', '0.22'))));

    l_result := oci_ocr;
    ut.expect(l_result.get_clob('markdown'), 'paragraphs').to_equal(to_clob('L1' || chr(10) || 'L2' || chr(10) || chr(10) || 'L3'));
  end oci_reading_order;


  procedure oci_table_without_polygon
  as
    l_result json_object_t;
    l_blocks json_array_t;
  begin
    uc_ai_test_http_mock.enqueue(oci_response(oci_page(1,
      oci_line('T1', '0.1', '0.05', '0.3', '0.07')
    , '[' || oci_table('[]', '[' || oci_row('[' || oci_cell('H', 0, 0) || ']') || ']', null) || ']')));

    l_result := oci_ocr;

    ut.expect(l_result.get_clob('markdown'))
      .to_equal(to_clob('T1' || chr(10) || chr(10) || '| H |  |' || chr(10) || '| --- | --- |'));  -- columnCount of the builder is 2

    l_blocks := treat(l_result.get_array('pages').get(0) as json_object_t).get_array('blocks');
    ut.expect(l_blocks.get_size, 'text block and table block').to_equal(2);
    ut.expect(treat(l_blocks.get(1) as json_object_t).get_string('type'), 'table block').to_equal('table');
    ut.expect(treat(l_blocks.get(1) as json_object_t).has('box'), 'no box without a polygon').to_be_false();
  end oci_table_without_polygon;


  procedure oci_table_cell_escaping
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(oci_response(oci_page(1, null
    , '[' || oci_table(
        '[' || oci_row('[' || oci_cell('a|b', 0, 0) || ',' || oci_cell('Head\nline', 0, 1) || ']') || ']'
      , '[' || oci_row('[' || oci_cell('x | y | z', 1, 0) || ',' || oci_cell('two\r\nlines', 1, 1) || ']') || ']'
      , null) || ']')));

    l_result := oci_ocr;

    ut.expect(l_result.get_clob('markdown'))
      .to_equal(to_clob('| a\|b | Head line |' || chr(10) || '| --- | --- |' || chr(10) || '| x \| y \| z | two lines |'));
  end oci_table_cell_escaping;


  procedure oci_table_edge_cases
  as
    l_result json_object_t;
    l_page   json_object_t;
  begin
    -- table 1: gaps, a cell without text, indexes that are negative, huge, fractional or a
    --          string, a cell without index, columnCount larger than the cells
    -- table 2: no cell at all (skipped, no block)
    -- table 3: rows without a cells array (skipped)
    -- then something that is not a table
    uc_ai_test_http_mock.enqueue(oci_response(oci_page(1, null, '['
      || '{"rowCount":3,"columnCount":4,"headerRows":[' || oci_row('[' || oci_cell('H', 0, 0) || ',' || oci_cell('Z', 0, 2) || ']') || ']'
      || ',"bodyRows":[' || oci_row('[{"rowIndex":1,"columnIndex":0,"confidence":1}]') || ','
      || oci_row('[' || oci_cell('gap', 2, 1) || ',' || oci_cell('neg', -1, 0) || ',' || oci_cell('huge', 20000, 0) || ','
                 || oci_cell('huge col', 0, 20000) || ',{"text":"frac","rowIndex":1.5,"columnIndex":0},{"text":"str","rowIndex":"1","columnIndex":0}'
                 || ',{"text":"no index"}]') || ']'
      || ',"footerRows":null,"boundingPolygon":null}'
      || ',{"rowCount":0,"columnCount":0,"headerRows":[],"bodyRows":[],"footerRows":[]}'
      || ',{"headerRows":null,"bodyRows":[{"note":"no cells"},{"cells":null},"junk"],"footerRows":[]}'
      || ',"not an object"]')));

    l_result := oci_ocr;

    ut.expect(l_result.get_clob('markdown'))
      .to_equal(to_clob('| H |  | Z |  |' || chr(10) || '| --- | --- | --- | --- |' || chr(10)
                        || '|  |  |  |  |' || chr(10) || '|  | gap |  |  |'));

    l_page := treat(l_result.get_array('pages').get(0) as json_object_t);
    ut.expect(l_page.get_array('blocks').get_size, 'one table block, empty tables are skipped').to_equal(1);
  end oci_table_edge_cases;


  procedure oci_line_edge_cases
  as
    l_result json_object_t;
    l_blocks json_array_t;
    l_block  json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(oci_response(oci_page(1,
      '{"text":"null polygon","confidence":0.5,"boundingPolygon":null}'
      || ',{"text":"no polygon"}'
      || ',{"text":"empty vertices","boundingPolygon":{"normalizedVertices":[]}}'
      || ',{"text":"bad vertices","boundingPolygon":{"normalizedVertices":[{"x":"a","y":1},null,{"y":1}]}}'
      || ',{"text":"no confidence","boundingPolygon":{"normalizedVertices":[{"x":0.1,"y":0.2},{"x":0.3,"y":0.2},{"x":0.3,"y":0.4},{"x":0.1,"y":0.4}]}}'
      || ',{"text":"","confidence":1}'
      || ',{"text":null}'
      || ',{"confidence":1}'
      || ',"junk"'
      || ',null'
    )));

    l_result := oci_ocr;

    ut.expect(l_result.get_clob('markdown')).to_equal(to_clob('null polygon' || chr(10) || 'no polygon' || chr(10) || 'empty vertices'
      || chr(10) || 'bad vertices' || chr(10) || 'no confidence'));

    l_blocks := treat(l_result.get_array('pages').get(0) as json_object_t).get_array('blocks');
    ut.expect(l_blocks.get_size, 'blocks of lines with text').to_equal(5);

    l_block := treat(l_blocks.get(0) as json_object_t);
    ut.expect(l_block.get_number('confidence'), 'confidence kept').to_equal(0.5);
    ut.expect(l_block.has('box'), 'null polygon: no box').to_be_false();
    ut.expect(l_block.has('polygon'), 'null polygon: no polygon').to_be_false();
    ut.expect(treat(l_blocks.get(1) as json_object_t).has('box'), 'missing polygon: no box').to_be_false();
    ut.expect(treat(l_blocks.get(2) as json_object_t).has('box'), 'no vertices: no box').to_be_false();
    ut.expect(treat(l_blocks.get(3) as json_object_t).has('box'), 'unusable vertices: no box').to_be_false();

    l_block := treat(l_blocks.get(4) as json_object_t);
    ut.expect(l_block.has('confidence'), 'no confidence unless OCI sends one').to_be_false();
    ut.expect(l_block.get_object('box').get_number('y2'), 'box of a line without confidence').to_equal(0.4);
  end oci_line_edge_cases;


  procedure oci_usage_and_model
  as
    l_result json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);
    test_uc_ai_wire.enqueue_sample(c_oci_sample_png);
    uc_ai_test_http_mock.enqueue('{"pages":[' || oci_page(1, oci_line('A', '0.1', '0.1', '0.2', '0.2')) || ']}');

    l_result := oci_ocr;
    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
    ut.expect(l_result.get_string('model'), 'model from the response').to_be_like('1.13%');

    l_result := uc_ai.ocr(uc_ai_test_utils.get_apple_png, 'image/png', uc_ai.c_provider_oci);
    ut.expect(l_result.get_string('model'), 'model is null in the response').to_equal('oci-document-understanding');

    l_result := oci_ocr;
    ut.expect(l_result.get_object('usage').get_size, 'no documentMetadata, no usage').to_equal(0);
    ut.expect(l_result.get_string('model'), 'no model in the response').to_equal('oci-document-understanding');

    -- p_model is ignored
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);
    l_result := uc_ai.ocr(uc_ai_test_utils.get_emp_pdf, 'application/pdf', uc_ai.c_provider_oci, 'some-model');
    ut.expect(uc_ai_test_http_mock.request_json(4).has('model'), 'model is not sent').to_be_false();
    ut.expect(l_result.get_string('model'), 'model of the response').to_be_like('1.13%');
  end oci_usage_and_model;


  procedure oci_no_text_is_warning
  as
    l_result json_object_t;
    l_page   json_object_t;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_png);

    l_result := uc_ai.ocr(uc_ai_test_utils.get_apple_png, 'image/png', uc_ai.c_provider_oci);

    ut.expect(sys.dbms_lob.getlength(l_result.get_clob('markdown')), 'markdown is empty').to_equal(0);
    ut.expect(l_result.get_array('warnings').get_size, 'one warning').to_equal(1);
    ut.expect(l_result.get_array('warnings').get_string(0), 'warning').to_be_like('FEATURE_NOT_SUPPORTED: %Text Extraction feature is not supported%');
    ut.expect(l_result.get_array('pages').get_size, 'one page').to_equal(1);

    l_page := treat(l_result.get_array('pages').get(0) as json_object_t);
    ut.expect(l_page.get_number('index'), 'index').to_equal(0);
    ut.expect(l_page.get_array('blocks').get_size, 'no blocks').to_equal(0);
    ut.expect(l_page.has('dimensions'), 'dimensions are null in the response').to_be_false();
    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage.pages').to_equal(1);
    ut.expect(l_result.get_object('raw').get_array('errors').get_size, 'raw keeps the errors').to_equal(1);
  end oci_no_text_is_warning;


  procedure oci_errors_with_pages
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(oci_response(
      oci_page(1, oci_line('A', '0.1', '0.1', '0.2', '0.2'))
    , '[{"code":"W1","message":"first"},{"code":"W2"},{"message":"only message"},"plain text",{}]'));

    l_result := oci_ocr;

    ut.expect(l_result.get_clob('markdown'), 'text is returned').to_equal(to_clob('A'));
    ut.expect(l_result.get_array('warnings').to_string, 'warnings')
      .to_equal('["W1: first","W2","only message","plain text","unknown error"]');
  end oci_errors_with_pages;


  procedure oci_errors_without_pages
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue('{"documentMetadata":null,"pages":null,"errors":[{"code":"INVALID_DOCUMENT","message":"cannot read it"}]}');
    uc_ai_test_http_mock.enqueue('{"pages":[],"errors":[{"code":"INVALID_DOCUMENT","message":"cannot read it"}]}');
    uc_ai_test_http_mock.enqueue('{"documentMetadata":{"pageCount":1}}');
    uc_ai_test_http_mock.enqueue('{"pages":null,"errors":null}');

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_oci, null, l_code, l_message);
    ut.expect(l_code, 'errors, pages null').to_equal(-20302);
    ut.expect(l_message, 'message').to_be_like('%OCI%INVALID_DOCUMENT: cannot read it%');

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_oci, null, l_code, l_message);
    ut.expect(l_code, 'errors, empty pages').to_equal(-20302);

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_oci, null, l_code, l_message);
    ut.expect(l_code, 'no pages, no errors').to_equal(-20302);
    ut.expect(l_message, 'no pages message').to_be_like('%no pages array%');

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_oci, null, l_code, l_message);
    ut.expect(l_code, 'pages null, errors null').to_equal(-20302);
  end oci_errors_without_pages;


  procedure oci_empty_pages_array
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue('{"pages":[],"errors":null}');

    l_result := oci_ocr;

    ut.expect(l_result.get_array('pages').get_size, 'no pages').to_equal(0);
    ut.expect(sys.dbms_lob.getlength(l_result.get_clob('markdown')), 'empty markdown').to_equal(0);
    ut.expect(l_result.get_array('warnings').get_size, 'no warnings').to_equal(0);
  end oci_empty_pages_array;


  procedure oci_pages_option
  as
    l_result   json_object_t;
    l_response clob;
  begin
    l_response := oci_response(
      oci_page(1, oci_line('one', '0.1', '0.1', '0.2', '0.2')) || ','
      || oci_page(2, oci_line('two', '0.1', '0.1', '0.2', '0.2')) || ','
      || oci_page(3, oci_line('three', '0.1', '0.1', '0.2', '0.2'))
    , 'null', 3);
    uc_ai_test_http_mock.enqueue(l_response);
    uc_ai_test_http_mock.enqueue(l_response);
    uc_ai_test_http_mock.enqueue(l_response);

    l_result := oci_ocr(json_object_t('{"pages":[1]}'));
    ut.expect(l_result.get_array('pages').get_size, 'one page').to_equal(1);
    ut.expect(treat(l_result.get_array('pages').get(0) as json_object_t).get_number('index'), 'index of the kept page').to_equal(1);
    ut.expect(l_result.get_clob('markdown'), 'markdown of the kept page').to_equal(to_clob('two'));
    ut.expect(l_result.get_object('raw').get_array('pages').get_size, 'raw keeps all pages').to_equal(3);
    ut.expect(l_result.get_object('usage').get_number('pages'), 'usage stays what OCI processed').to_equal(3);

    l_result := oci_ocr(json_object_t('{"pages":[2,0,7,"x",-1]}'));
    ut.expect(l_result.get_clob('markdown'), 'pages 0 and 2, in the order of the response').to_equal(to_clob('one' || chr(10) || chr(10) || 'three'));

    l_result := oci_ocr(json_object_t('{"pages":[]}'));
    ut.expect(l_result.get_array('pages').get_size, 'an empty list keeps nothing').to_equal(0);
    ut.expect(uc_ai_test_http_mock.request_json(1).has('pages'), 'pages is not sent').to_be_false();
  end oci_pages_option;


  procedure oci_pages_are_joined
  as
    l_result json_object_t;
  begin
    uc_ai_test_http_mock.enqueue(oci_response(
      oci_page(1, oci_line('First page', '0.1', '0.1', '0.2', '0.2')) || ','
      || oci_page(2, null) || ','
      || oci_page(3, oci_line('Second', '0.1', '0.1', '0.2', '0.2') || ',' || oci_line('page', '0.1', '0.12', '0.2', '0.22'))
    , 'null', 3));

    l_result := oci_ocr;

    ut.expect(l_result.get_clob('markdown')).to_equal(to_clob('First page' || chr(10) || chr(10) || 'Second' || chr(10) || 'page'));
    ut.expect(l_result.get_array('pages').get_size, 'all pages are kept').to_equal(3);
    ut.expect(treat(l_result.get_array('pages').get(2) as json_object_t).get_number('index'), 'index of page 3').to_equal(2);
  end oci_pages_are_joined;


  procedure oci_ocr_text
  as
    l_result json_object_t;
    l_text   clob;
  begin
    test_uc_ai_wire.enqueue_sample(c_oci_sample_tables);
    test_uc_ai_wire.enqueue_sample(c_oci_sample_tables);

    l_result := oci_ocr(json_object_t('{"tables":true}'));
    l_text := uc_ai.ocr_text(
      p_document   => uc_ai_test_utils.get_emp_pdf
    , p_media_type => 'application/pdf'
    , p_provider   => uc_ai.c_provider_oci
    , p_options    => json_object_t('{"tables":true}')
    );

    ut.expect(l_text).to_equal(l_result.get_clob('markdown'));
    ut.expect(l_text).to_be_like('List of users:%| Dwight | Schrute |%');
  end oci_ocr_text;


  procedure oci_error_401
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get(c_oci_sample_401), 401);

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_oci, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_message, 'message').to_be_like('%OCI%HTTP 401%Failed to verify the HTTP(S) Signature%');
  end oci_error_401;


  procedure oci_error_400
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get(c_oci_sample_400), 400);

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_oci, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_message, 'message').to_be_like('%OCI%HTTP 400%Input file type is not supported%');
  end oci_error_400;


  procedure oci_body_is_not_logged
  as
    -- 45 bytes give 60 base64 characters without a line break
    c_text    constant varchar2(45 char) := 'UC_AI_OCR_LOG_MARKER_0123456789_abcdefghijklm';
    l_marker  varchar2(100 char);
    l_last_id number;
    l_result  json_object_t;
    l_count   pls_integer;
    l_calls   pls_integer;
    l_rows    pls_integer;
  begin
    select nvl(max(id), 0) into l_last_id from logger_logs;

    l_marker := sys.utl_raw.cast_to_varchar2(sys.utl_encode.base64_encode(sys.utl_raw.cast_to_raw(c_text)));
    test_uc_ai_wire.enqueue_sample(c_oci_sample_pdf);

    -- control: the query does find the marker when something logs it
    uc_ai_logger.log('control row', 'test_uc_ai_ocr_wire.oci_body_is_not_logged', l_marker);

    l_result := uc_ai.ocr(to_blob(sys.utl_raw.cast_to_raw(c_text)), 'application/pdf', uc_ai.c_provider_oci);
    ut.expect(instr(uc_ai_test_http_mock.request_json(1).get_object('document').get_string('data'), l_marker), 'the request does hold the base64').to_be_greater_than(0);

    select count(*)
      into l_rows
      from logger_logs
     where id > l_last_id
       and (instr(text, l_marker) > 0 or sys.dbms_lob.instr(extra, l_marker) > 0);
    ut.expect(l_rows, 'only the control row holds the base64').to_equal(1);

    select count(*)
      into l_calls
      from logger_logs
     where id > l_last_id
       and text like 'Calling OCI Document Understanding%';
    ut.expect(l_calls, 'the call is logged').to_equal(1);

    select count(*)
      into l_count
      from logger_logs
     where id > l_last_id
       and (sys.dbms_lob.instr(extra, '"document"') > 0 or sys.dbms_lob.instr(extra, '"compartmentId"') > 0
            or sys.dbms_lob.instr(extra, '"INLINE"') > 0);
    ut.expect(l_count, 'no log row holds the request body').to_equal(0);
  end oci_body_is_not_logged;


  -- ---- errors ----------------------------------------------------------------

  procedure rate_limit_error
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    -- the flat error shape of the platform; 429 is the status of a real rate limit
    uc_ai_test_http_mock.enqueue(
      '{"object":"error","message":"Rate limit exceeded","type":"rate_limited","param":null,"code":"1300","raw_status_code":429}'
    , 429);

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_mistral, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_message, 'message').to_be_like('%Mistral%Rate limit exceeded%');
    test_uc_ai_wire.expect_all_consumed(1);
  end rate_limit_error;


  procedure invalid_model_error
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue(uc_ai_test_samples.get(c_sample_bad_model), 400);

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_mistral, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_message, 'message').to_be_like('%Invalid model: no-such-ocr-model%');
  end invalid_model_error;


  procedure html_error_body
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue('<html><body>502 Bad Gateway</body></html>', 502);

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_mistral, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_message, 'message').to_be_like('%502%');
  end html_error_body;


  procedure response_without_pages
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue('{"model":"mistral-ocr-latest","usage_info":null}');
    uc_ai_test_http_mock.enqueue('{"pages":null}');

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_mistral, null, l_code, l_message);
    ut.expect(l_code, 'error code, no pages key').to_equal(-20302);
    ut.expect(l_message, 'message').to_be_like('%no pages array%');

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_mistral, null, l_code, l_message);
    ut.expect(l_code, 'error code, pages null').to_equal(-20302);
  end response_without_pages;


  procedure error_object_in_200
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    uc_ai_test_http_mock.enqueue('{"object":"error","message":"Something odd","type":"x","code":"1"}', 200);

    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_mistral, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20302);
    ut.expect(l_message, 'message').to_be_like('%Something odd%');
  end error_object_in_200;


  procedure unsupported_media_type
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    try_ocr(small_blob, 'text/plain', uc_ai.c_provider_mistral, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20508);
    ut.expect(l_message, 'names the media type').to_be_like('%text/plain%');
    ut.expect(l_message, 'names the supported types').to_be_like('%application/pdf%image/png%image/webp%');
    test_uc_ai_wire.expect_all_consumed(0);

    -- TIFF is an OCI type, not a Mistral one
    try_ocr(small_blob, 'image/tiff', uc_ai.c_provider_mistral, null, l_code, l_message);
    ut.expect(l_code, 'error code tiff').to_equal(-20508);
    test_uc_ai_wire.expect_all_consumed(0);
  end unsupported_media_type;


  procedure null_media_type
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    try_ocr(small_blob, null, uc_ai.c_provider_mistral, null, l_code, l_message);

    ut.expect(l_code, 'error code').to_equal(-20508);
    ut.expect(l_message, 'message').to_be_like('%null%');
    test_uc_ai_wire.expect_all_consumed(0);
  end null_media_type;


  procedure empty_document
  as
    l_code    number;
    l_message varchar2(4000 char);
    l_empty   blob;
  begin
    try_ocr(null, 'application/pdf', uc_ai.c_provider_mistral, null, l_code, l_message);
    ut.expect(l_code, 'null blob').to_equal(-20503);

    sys.dbms_lob.createtemporary(l_empty, true);
    try_ocr(l_empty, 'application/pdf', uc_ai.c_provider_mistral, null, l_code, l_message);
    ut.expect(l_code, 'empty blob').to_equal(-20503);
    ut.expect(l_message, 'message').to_be_like('%empty%');

    test_uc_ai_wire.expect_all_consumed(0);
  end empty_document;


  procedure null_and_unknown_provider
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    try_ocr(small_blob, 'application/pdf', null, null, l_code, l_message);
    ut.expect(l_code, 'null provider').to_equal(-20306);

    try_ocr(small_blob, 'application/pdf', 'nope', null, l_code, l_message);
    ut.expect(l_code, 'unknown provider').to_equal(-20306);
    ut.expect(l_message, 'message').to_be_like('%nope%');

    -- a provider that exists but cannot do OCR
    try_ocr(small_blob, 'application/pdf', uc_ai.c_provider_openai, null, l_code, l_message);
    ut.expect(l_code, 'openai').to_equal(-20306);

    test_uc_ai_wire.expect_all_consumed(0);
  end null_and_unknown_provider;


  procedure providers_without_adapter
  as
    l_code    number;
    l_message varchar2(4000 char);
  begin
    try_ocr(uc_ai_test_utils.get_apple_png, 'image/png', uc_ai.c_provider_ollama, null, l_code, l_message);
    ut.expect(l_code, 'ollama').to_equal(-20306);
    ut.expect(l_message, 'ollama message').to_be_like('%not supported yet%ollama%');

    test_uc_ai_wire.expect_all_consumed(0);
  end providers_without_adapter;


  -- ---- logging ---------------------------------------------------------------

  procedure body_is_not_logged
  as
    -- 45 bytes give 60 base64 characters without a line break
    c_text   constant varchar2(45 char) := 'UC_AI_OCR_LOG_MARKER_0123456789_abcdefghijklm';
    l_marker varchar2(100 char);
    -- only rows this test wrote
    l_last_id number;
    l_result json_object_t;
    l_count  pls_integer;
    l_calls  pls_integer;

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

    l_marker := sys.utl_raw.cast_to_varchar2(sys.utl_encode.base64_encode(sys.utl_raw.cast_to_raw(c_text)));
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);
    test_uc_ai_wire.enqueue_sample(c_sample_pdf);

    -- control: the query does find the marker when something logs it
    uc_ai_logger.log('control row', 'test_uc_ai_ocr_wire.body_is_not_logged', l_marker);
    ut.expect(marker_rows(l_last_id, l_marker), 'control row is found').to_equal(1);

    l_result := uc_ai.ocr(to_blob(sys.utl_raw.cast_to_raw(c_text)), 'application/pdf', uc_ai.c_provider_mistral);
    ut.expect(instr(uc_ai_test_http_mock.request_json(1).get_object('document').get_string('document_url'), l_marker), 'the request does hold the base64').to_be_greater_than(0);

    -- the URL overload with a data URL must not log the payload either
    l_result := uc_ai.ocr(p_url => 'data:application/pdf;base64,' || l_marker, p_provider => uc_ai.c_provider_mistral);

    ut.expect(marker_rows(l_last_id, l_marker), 'no log row holds the base64').to_equal(1);

    -- the call was logged, so an empty result above is not a silent logger
    select count(*)
      into l_calls
      from logger_logs
     where id > l_last_id
       and text like 'Calling Mistral OCR%';
    ut.expect(l_calls, 'the calls are logged').to_equal(2);

    select count(*)
      into l_count
      from logger_logs
     where id > l_last_id
       and (sys.dbms_lob.instr(extra, '"document_url"') > 0 or sys.dbms_lob.instr(extra, '"model":"mistral-ocr') > 0);
    ut.expect(l_count, 'no log row holds the request body').to_equal(0);
  end body_is_not_logged;

end test_uc_ai_ocr_wire;
/
