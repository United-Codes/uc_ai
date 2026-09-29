create or replace package body uc_ai_ocr as

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  -- OCR of a large document can take much longer than a chat call
  c_transfer_timeout constant pls_integer := 300;

  c_mistral_base_url constant varchar2(100 char) := 'https://api.mistral.ai/v1';

  c_mime_pdf  constant varchar2(100 char) := 'application/pdf';
  c_mime_docx constant varchar2(100 char) := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  c_mime_pptx constant varchar2(100 char) := 'application/vnd.openxmlformats-officedocument.presentationml.presentation';

  -- Comma separated, without spaces (membership test is instr on ',type,')
  c_types_mistral constant varchar2(1000 char) :=
    c_mime_pdf || ',image/png,image/jpeg,image/webp,image/avif,' || c_mime_docx || ',' || c_mime_pptx;
  c_types_oci     constant varchar2(1000 char) := c_mime_pdf || ',image/png,image/jpeg,image/tiff';
  c_types_ollama  constant varchar2(1000 char) := 'image/png,image/jpeg,image/webp';

  -- ---- shared helpers ---------------------------------------------------------

  /*
   * 'Application/PDF; charset=binary' -> 'application/pdf'. image/jpg is a
   * common misspelling of image/jpeg.
   */
  function normalize_media_type (
    p_media_type in varchar2
  ) return varchar2
  as
    l_type varchar2(200 char);
  begin
    l_type := lower(trim(regexp_substr(p_media_type, '^[^;]*')));

    if l_type = 'image/jpg' then
      l_type := 'image/jpeg';
    end if;

    return l_type;
  end normalize_media_type;


  function supported_media_types (
    p_provider in varchar2
  ) return varchar2
  as
  begin
    return case p_provider
      when uc_ai.c_provider_mistral then c_types_mistral
      when uc_ai.c_provider_oci     then c_types_oci
      when uc_ai.c_provider_ollama  then c_types_ollama
    end;
  end supported_media_types;


  /*
   * Raises -20508 when the media type is not one the provider accepts. Runs
   * before any HTTP call, so an unsupported file costs no request.
   */
  procedure check_media_type (
    p_provider   in varchar2
  , p_media_type in varchar2
  , p_scope      in varchar2
  )
  as
    l_supported varchar2(1000 char);
  begin
    l_supported := supported_media_types(p_provider);

    if p_media_type is null or instr(',' || l_supported || ',', ',' || p_media_type || ',') = 0 then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_unsupported_content
      , p_scope      => p_scope
      , p0           => nvl(p_media_type, 'null') || ' for OCR with provider ' || p_provider
                        || '. Supported: ' || replace(l_supported, ',', ', ')
      );
    end if;
  end check_media_type;


  /*
   * Base64 of a blob as one line, as the data URLs of the providers need it.
   */
  function to_base64 (
    p_blob in blob
  ) return clob
  as
  begin
    return replace(replace(apex_web_service.blob2clobbase64(p_blob), chr(10)), chr(13));
  end to_base64;


  /*
   * The page texts joined with a blank line. Pages without text are left out so
   * a blank page does not add empty paragraphs.
   */
  function join_pages (
    p_pages in json_array_t
  ) return clob
  as
    l_result clob;
    l_page   json_object_t;
    l_text   clob;
  begin
    sys.dbms_lob.createtemporary(l_result, true);

    <<page_loop>>
    for i in 0 .. p_pages.get_size - 1 loop
      l_page := treat(p_pages.get(i) as json_object_t);
      l_text := l_page.get_clob('markdown');

      continue when l_text is null or sys.dbms_lob.getlength(l_text) = 0;

      if sys.dbms_lob.getlength(l_result) > 0 then
        sys.dbms_lob.writeappend(l_result, 2, chr(10) || chr(10));
      end if;
      sys.dbms_lob.append(l_result, l_text);
    end loop page_loop;

    return l_result;
  end join_pages;


  /*
   * The neutral result. p_usage, p_warnings and p_raw are complete objects the
   * adapter built; they are put in as they are.
   */
  function new_result (
    p_pages    in json_array_t
  , p_usage    in json_object_t
  , p_model    in varchar2
  , p_warnings in json_array_t
  , p_raw      in json_object_t
  ) return json_object_t
  as
    l_result json_object_t := json_object_t();
  begin
    l_result.put('markdown', join_pages(p_pages));
    l_result.put('pages', p_pages);
    l_result.put('usage', p_usage);
    l_result.put('model', p_model);
    l_result.put('warnings', p_warnings);
    l_result.put('raw', p_raw);
    return l_result;
  end new_result;


  /*
   * What a data: URL declares, without the payload, and a URL without its query
   * string (it can carry a signed token). Safe to log.
   */
  function describe_url (
    p_url in varchar2
  ) return varchar2
  as
  begin
    if lower(substr(p_url, 1, 5)) = 'data:' then
      return regexp_substr(p_url, '^[^,]*') || ',...';
    end if;
    return substr(regexp_substr(p_url, '^[^?#]*'), 1, 500);
  end describe_url;


  /*
   * Comma separated option keys; values can be large and are not logged.
   */
  function option_keys (
    p_options in json_object_t
  ) return varchar2
  as
    l_keys   json_key_list;
    l_result varchar2(4000 char);
  begin
    if p_options is null then
      return null;
    end if;

    l_keys := p_options.get_keys;
    <<key_loop>>
    for i in 1 .. l_keys.count loop
      l_result := l_result || case when i > 1 then ',' end || l_keys(i);
    end loop key_loop;

    return substr(l_result, 1, 500);
  end option_keys;


  /*
   * Parse a provider response. An error status with a flat or nested error body
   * becomes -20302 with the provider's own message; anything else that is not
   * JSON or not a success is left to uc_ai_error.parse_json_response.
   */
  function parse_response (
    p_response in clob
  , p_provider in varchar2
  , p_scope    in varchar2
  ) return json_object_t
  as
    l_status  number := apex_web_service.g_status_code;
    l_json    json_object_t;
    l_error   json_object_t;
    l_message varchar2(4000 char);
  begin
    if nvl(l_status, 0) >= 400 then
      begin
        l_json := json_object_t.parse(p_response);
      exception
        when others then -- @dblinter ignore(g-5040): a body that is not JSON is reported by parse_json_response below
          l_json := null;
      end;

      if l_json is not null then
        -- flat: {"message": "..."} (Mistral); nested: {"error": {"message": "..."}}
        l_error := l_json;
        if l_json.has('error') and l_json.get('error').is_object then
          l_error := l_json.get_object('error');
        end if;

        if l_error.has('message') and l_error.get('message').is_string then
          l_message := l_error.get_string('message');
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_provider_response
          , p_scope      => p_scope
          , p0           => p_provider
          , p1           => 'HTTP ' || l_status || ': ' || l_message
          , p_extra      => p_response
          );
        end if;
      end if;
    end if;

    return uc_ai_error.parse_json_response(p_response, p_provider, p_scope);
  end parse_response;


  -- ---- Mistral adapter --------------------------------------------------------

  /*
   * pixel box -> normalized box. Skipped when the page size is unknown.
   */
  function normalize_box (
    p_block  in json_object_t
  , p_width  in number
  , p_height in number
  ) return json_object_t
  as
    l_box json_object_t;
  begin
    if nvl(p_width, 0) <= 0 or nvl(p_height, 0) <= 0
      or not p_block.has('top_left_x') or p_block.get('top_left_x').is_null
      or not p_block.has('top_left_y') or p_block.get('top_left_y').is_null
      or not p_block.has('bottom_right_x') or p_block.get('bottom_right_x').is_null
      or not p_block.has('bottom_right_y') or p_block.get('bottom_right_y').is_null
    then
      return null;
    end if;

    l_box := json_object_t();
    l_box.put('x1', round(p_block.get_number('top_left_x') / p_width, 6));
    l_box.put('y1', round(p_block.get_number('top_left_y') / p_height, 6));
    l_box.put('x2', round(p_block.get_number('bottom_right_x') / p_width, 6));
    l_box.put('y2', round(p_block.get_number('bottom_right_y') / p_height, 6));
    return l_box;
  end normalize_box;


  function mistral_page (
    p_page     in json_object_t
  , p_position in pls_integer
  ) return json_object_t
  as
    l_page       json_object_t := json_object_t();
    l_dim        json_object_t;
    l_conf       json_object_t;
    l_dimensions json_object_t;
    l_blocks_in  json_array_t;
    l_blocks     json_array_t;
    l_block_in   json_object_t;
    l_block      json_object_t;
    l_box        json_object_t;
    l_width      number;
    l_height     number;
    l_markdown   clob;
    l_tables     json_array_t;
    l_table      json_object_t;
  begin
    l_markdown := case when p_page.has('markdown') and p_page.get('markdown').is_string then p_page.get_clob('markdown') else empty_clob() end;

    -- With table_format set Mistral leaves a link "[tbl-0.md](tbl-0.md)" in the
    -- markdown and returns the table in pages[].tables[]. Put the table back.
    if p_page.has('tables') and p_page.get('tables').is_array then
      l_tables := p_page.get_array('tables');
      <<table_loop>>
      for i in 0 .. l_tables.get_size - 1 loop
        l_table := treat(l_tables.get(i) as json_object_t);
        if l_table.has('id') and l_table.get('id').is_string and l_table.has('content') and l_table.get('content').is_string then
          l_markdown := replace(
            l_markdown
          , '[' || l_table.get_string('id') || '](' || l_table.get_string('id') || ')'
          , l_table.get_clob('content')
          );
        end if;
      end loop table_loop;
    end if;

    l_page.put('index', case when p_page.has('index') and p_page.get('index').is_number then p_page.get_number('index') else p_position end);
    l_page.put('markdown', l_markdown);

    if p_page.has('confidence_scores') and p_page.get('confidence_scores').is_object then
      l_conf := p_page.get_object('confidence_scores');
      if l_conf.has('average_page_confidence_score') and l_conf.get('average_page_confidence_score').is_number then
        l_page.put('confidence', l_conf.get_number('average_page_confidence_score'));
      end if;
    end if;

    if p_page.has('dimensions') and p_page.get('dimensions').is_object then
      l_dim := p_page.get_object('dimensions');
      if l_dim.has('width') and l_dim.get('width').is_number and l_dim.has('height') and l_dim.get('height').is_number then
        l_width  := l_dim.get_number('width');
        l_height := l_dim.get_number('height');
        l_dimensions := json_object_t();
        l_dimensions.put('width', l_width);
        l_dimensions.put('height', l_height);
        l_page.put('dimensions', l_dimensions);
      end if;
    end if;

    if p_page.has('blocks') and p_page.get('blocks').is_array then
      l_blocks_in := p_page.get_array('blocks');
      l_blocks    := json_array_t();

      <<block_loop>>
      for i in 0 .. l_blocks_in.get_size - 1 loop
        l_block_in := treat(l_blocks_in.get(i) as json_object_t);
        l_block    := json_object_t();
        l_block.put('type', case when l_block_in.has('type') and l_block_in.get('type').is_string then l_block_in.get_string('type') else 'text' end);
        l_block.put('text', case when l_block_in.has('content') and l_block_in.get('content').is_string then l_block_in.get_clob('content') else empty_clob() end);

        if l_block_in.has('confidence_scores') and l_block_in.get('confidence_scores').is_number then
          l_block.put('confidence', l_block_in.get_number('confidence_scores'));
        end if;

        l_box := normalize_box(l_block_in, l_width, l_height);
        if l_box is not null then
          l_block.put('box', l_box);
        end if;

        l_blocks.append(l_block);
      end loop block_loop;

      l_page.put('blocks', l_blocks);
    end if;

    return l_page;
  end mistral_page;


  /*
   * The document object of the Mistral request. Images go as image_url, all
   * other documents as document_url. p_url is a public or data: URL.
   */
  function mistral_document (
    p_document   in blob
  , p_url        in varchar2
  , p_media_type in varchar2
  ) return json_object_t
  as
    l_document json_object_t := json_object_t();
    l_type     varchar2(20 char);
    l_url      clob;
  begin
    if p_url is not null then
      l_url := p_url;
      l_type := case
        when lower(p_url) like 'data:image/%'
          or regexp_like(regexp_substr(p_url, '^[^?#]*'), '\.(png|jpe?g|webp|avif)$', 'i')
        then 'image_url'
        else 'document_url'
      end;
    else
      l_type := case when p_media_type like 'image/%' then 'image_url' else 'document_url' end;
      l_url  := 'data:' || p_media_type || ';base64,';
      sys.dbms_lob.append(l_url, to_base64(p_document));
    end if;

    l_document.put('type', l_type);
    l_document.put(l_type, l_url);
    return l_document;
  end mistral_document;


  /*
   * The request body without the document: options, then neutral keys, then
   * extra_body. Reserved keys (model, document) are set by the caller after this.
   */
  function mistral_body (
    p_options in json_object_t
  , p_scope   in varchar2
  ) return json_object_t
  as
    l_body       json_object_t := json_object_t();
    l_keys       json_key_list;
    l_extra      json_object_t;
    l_extra_keys json_key_list;
  begin
    if p_options is null then
      return l_body;
    end if;

    l_keys := p_options.get_keys;
    <<option_loop>>
    for i in 1 .. l_keys.count loop
      -- extra_body and the neutral tables key are not Mistral keys
      continue when l_keys(i) in ('extra_body', 'tables');
      l_body.put(l_keys(i), p_options.get(l_keys(i)));
    end loop option_loop;

    if p_options.has('tables') and p_options.get('tables').is_true and not l_body.has('table_format') then
      l_body.put('table_format', 'markdown');
    end if;

    if p_options.has('extra_body') and not p_options.get('extra_body').is_null then
      if not p_options.get('extra_body').is_object then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => p_scope
        , p0           => 'OCR option extra_body'
        , p1           => 'it must be a JSON object'
        );
      end if;

      l_extra      := p_options.get_object('extra_body');
      l_extra_keys := l_extra.get_keys;
      <<extra_loop>>
      for i in 1 .. l_extra_keys.count loop
        l_body.put(l_extra_keys(i), l_extra.get(l_extra_keys(i)));
      end loop extra_loop;
    end if;

    return l_body;
  end mistral_body;


  function ocr_mistral (
    p_document   in blob
  , p_url        in varchar2
  , p_media_type in varchar2
  , p_model      in varchar2
  , p_options    in json_object_t
  , p_settings   in uc_ai_settings.t_settings
  ) return json_object_t
  as
    l_scope          uc_ai_logger.scope := c_scope_prefix || 'ocr_mistral';
    l_body           json_object_t;
    l_model          varchar2(255 char);
    l_web_credential varchar2(255 char);
    l_resp           clob;
    l_resp_json      json_object_t;
    l_pages_in       json_array_t;
    l_pages          json_array_t := json_array_t();
    l_usage_in       json_object_t;
    l_usage          json_object_t := json_object_t();
    l_resp_model     varchar2(255 char);
    l_url            varchar2(4000 char) := c_mistral_base_url || '/ocr';
  begin
    l_model := coalesce(p_model, uc_ai_mistral.c_model_mistral_ocr);
    l_body  := mistral_body(p_options, l_scope);
    l_body.put('model', l_model);
    l_body.put('document', mistral_document(p_document, p_url, p_media_type));

    apex_web_service.clear_request_headers;
    apex_web_service.g_request_headers(1).name  := 'Content-Type';
    apex_web_service.g_request_headers(1).value := 'application/json';

    l_web_credential := coalesce(p_settings.apex_web_credential, p_settings.ms_apex_web_credential);

    if l_web_credential is null then
      apex_web_service.g_request_headers(2).name  := 'Authorization';
      apex_web_service.g_request_headers(2).value := 'Bearer ' || uc_ai_get_key(uc_ai.c_provider_mistral);
    end if;

    uc_ai_settings.apply_extra_headers(p_settings);

    -- Never log l_body: it holds the whole document as base64
    uc_ai_logger.log(
      'Calling Mistral OCR at ' || l_url || '. Web Credential: ' || nvl(l_web_credential, 'null')
    , l_scope
    , 'model=' || l_model
      || ', source=' || case when p_url is not null then describe_url(p_url)
                             else p_media_type || ', ' || sys.dbms_lob.getlength(p_document) || ' bytes' end
      || ', option keys=' || nvl(option_keys(p_options), 'none')
    );

    l_resp := uc_ai_http.post(
      p_url                  => l_url
    , p_body                 => l_body.to_clob
    , p_credential_static_id => l_web_credential
    , p_transfer_timeout     => c_transfer_timeout
    );

    l_resp_json := parse_response(l_resp, 'Mistral', l_scope);

    -- a 200 can still carry the flat error shape
    if l_resp_json.has('object') and l_resp_json.get('object').is_string and l_resp_json.get_string('object') = 'error' then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'Mistral'
      , p1           => case when l_resp_json.has('message') and l_resp_json.get('message').is_string
                             then l_resp_json.get_string('message') else 'error response' end
      , p_extra      => l_resp
      );
    end if;

    if not l_resp_json.has('pages') or not l_resp_json.get('pages').is_array then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'Mistral'
      , p1           => 'response has no pages array'
      , p_extra      => l_resp
      );
    end if;

    l_pages_in := l_resp_json.get_array('pages');
    <<page_loop>>
    for i in 0 .. l_pages_in.get_size - 1 loop
      l_pages.append(mistral_page(treat(l_pages_in.get(i) as json_object_t), i));
    end loop page_loop;

    -- usage_info can be missing or JSON null
    if l_resp_json.has('usage_info') and l_resp_json.get('usage_info').is_object then
      l_usage_in := l_resp_json.get_object('usage_info');
      if l_usage_in.has('pages_processed') and l_usage_in.get('pages_processed').is_number then
        l_usage.put('pages', l_usage_in.get_number('pages_processed'));
      end if;
      if l_usage_in.has('doc_size_bytes') and l_usage_in.get('doc_size_bytes').is_number then
        l_usage.put('bytes', l_usage_in.get_number('doc_size_bytes'));
      end if;
    end if;

    l_resp_model := case when l_resp_json.has('model') and l_resp_json.get('model').is_string
                         then l_resp_json.get_string('model') else l_model end;

    uc_ai_logger.log(
      'Mistral OCR response'
    , l_scope
    , 'pages=' || l_pages.get_size || ', response length=' || sys.dbms_lob.getlength(l_resp)
    );

    return new_result(
      p_pages    => l_pages
    , p_usage    => l_usage
    , p_model    => l_resp_model
    , p_warnings => json_array_t()
    , p_raw      => l_resp_json
    );
  end ocr_mistral;


  -- ---- dispatcher -------------------------------------------------------------

  function ocr (
    p_document   in blob
  , p_url        in varchar2
  , p_media_type in varchar2
  , p_provider   in uc_ai.provider_type
  , p_model      in uc_ai.model_type
  , p_options    in json_object_t
  , p_settings   in uc_ai_settings.t_settings
  ) return json_object_t
  as
    l_scope      uc_ai_logger.scope := c_scope_prefix || 'ocr';
    l_media_type varchar2(200 char);
    l_data_type  varchar2(200 char);
  begin
    l_media_type := normalize_media_type(p_media_type);

    -- 1. provider: null and unknown first, then the ones without an adapter yet
    if p_provider is null or p_provider not in (uc_ai.c_provider_mistral, uc_ai.c_provider_oci, uc_ai.c_provider_ollama) then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_unknown_provider
      , p_scope      => l_scope
      , p0           => nvl(p_provider, 'null')
      );
    end if;

    if p_provider != uc_ai.c_provider_mistral then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_unknown_provider
      , p_scope      => l_scope
      , p_message    => 'OCR is not supported yet for provider %0'
      , p0           => p_provider
      );
    end if;

    -- 2. input: one source, not empty, a media type the provider accepts
    if p_url is not null then
      if p_document is not null then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => l_scope
        , p0           => 'OCR input'
        , p1           => 'pass a document or a URL, not both'
        );
      end if;

      -- a data: URL states its own media type
      if lower(substr(p_url, 1, 5)) = 'data:' then
        l_data_type := normalize_media_type(regexp_substr(substr(p_url, 6), '^[^,]*'));
        check_media_type(p_provider, l_data_type, l_scope);
      end if;
    else
      if p_document is null or sys.dbms_lob.getlength(p_document) = 0 then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => l_scope
        , p0           => 'OCR document'
        , p1           => 'it is null or empty'
        );
      end if;

      check_media_type(p_provider, l_media_type, l_scope);
    end if;

    -- 3. adapter
    return ocr_mistral(
      p_document   => p_document
    , p_url        => p_url
    , p_media_type => l_media_type
    , p_model      => p_model
    , p_options    => p_options
    , p_settings   => p_settings
    );
  exception
    when others then -- @dblinter ignore(g-5040): logged and re-raised
      -- errors raised by raise_error are logged already
      -- @dblinter ignore(g-5020): must match the whole -20000..-20999 application-error range, no named exception applies
      if sqlcode not between -20999 and -20000 then
        uc_ai_logger.log_error(
          'OCR failed'
        , l_scope
        , sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
        );
      end if;
      raise;
  end ocr;

end uc_ai_ocr;
/
