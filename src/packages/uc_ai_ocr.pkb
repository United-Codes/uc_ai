create or replace package body uc_ai_ocr as

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  -- OCR of a large document can take much longer than a chat call
  c_transfer_timeout constant pls_integer := 300;

  c_mistral_base_url constant varchar2(100 char) := 'https://api.mistral.ai/v1';

  -- Ollama, same default as uc_ai_ollama
  c_ollama_base_url constant varchar2(100 char) := 'http://localhost:11434/api';
  c_ollama_prompt   constant varchar2(1000 char) :=
    'Extract all text from this image as Markdown. Preserve tables as Markdown tables.';
  c_ollama_unreadable_hint constant varchar2(1000 char) :=
    'If the image is blank or unreadable, reply with exactly UNREADABLE';
  c_ollama_unreadable_word constant varchar2(20 char) := 'UNREADABLE';

  c_mime_pdf  constant varchar2(100 char) := 'application/pdf';
  c_mime_docx constant varchar2(100 char) := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  c_mime_pptx constant varchar2(100 char) := 'application/vnd.openxmlformats-officedocument.presentationml.presentation';

  -- Comma separated, without spaces (membership test is instr on ',type,')
  c_types_mistral constant varchar2(1000 char) :=
    c_mime_pdf || ',image/png,image/jpeg,image/webp,image/avif,' || c_mime_docx || ',' || c_mime_pptx;
  c_types_oci     constant varchar2(1000 char) := c_mime_pdf || ',image/png,image/jpeg,image/tiff';
  c_types_ollama  constant varchar2(1000 char) := 'image/png,image/jpeg,image/webp';

  -- OCI Document Understanding
  c_oci_url_prefix   constant varchar2(100 char) := 'https://document.aiservice.';
  c_oci_analyze_path constant varchar2(100 char) := '/20221109/actions/analyzeDocument';
  c_oci_model        constant varchar2(100 char) := 'oci-document-understanding';
  -- limit of a synchronous analyzeDocument call; more needs an async job
  c_oci_max_bytes    constant pls_integer := 8388608;
  -- a table cell index above this is not a real cell; it would only grow the grid
  c_oci_max_index    constant pls_integer := 9999;
  -- rows x columns of one table; a larger grid is not a real table
  c_oci_max_grid     constant pls_integer := 250000;

  type t_num_tab   is table of number index by pls_integer;
  type t_bool_tab  is table of boolean index by pls_integer;
  type t_clob_tab  is table of clob index by pls_integer;
  type t_obj_tab   is table of json_object_t index by pls_integer;

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
                        || case when p_provider = uc_ai.c_provider_ollama and p_media_type = c_mime_pdf
                                then '. PDFs are not supported: Ollama reads images only and PL/SQL cannot make an image of a PDF page.'
                                     || ' Pass an image with an opaque background'
                           end
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
   * Merge the keys of the option extra_body into the request body. A key of
   * extra_body replaces a key that is already in the body. A value that is not
   * an object raises -20503; a missing or null extra_body changes nothing.
   */
  procedure merge_extra_body (
    pio_body  in out nocopy json_object_t
  , p_options in            json_object_t
  , p_scope   in            varchar2
  )
  as
    l_extra      json_object_t;
    l_extra_keys json_key_list;
  begin
    if p_options is null or not p_options.has('extra_body') or p_options.get('extra_body').is_null then
      return;
    end if;

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
      pio_body.put(l_extra_keys(i), l_extra.get(l_extra_keys(i)));
    end loop extra_loop;
  end merge_extra_body;


  /*
   * The option pages as an array. Null when the option is missing or JSON null;
   * a value that is not an array raises -20503.
   */
  function pages_option (
    p_options in json_object_t
  , p_scope   in varchar2
  ) return json_array_t
  as
  begin
    if p_options is null or not p_options.has('pages') or p_options.get('pages').is_null then
      return null;
    end if;

    if not p_options.get('pages').is_array then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => p_scope
      , p0           => 'OCR option pages'
      , p1           => 'it must be an array of 0-based page indexes'
      );
    end if;

    return p_options.get_array('pages');
  end pages_option;


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

        if l_json.has('error') and l_json.get('error').is_string then
          -- Ollama: {"error": "..."}
          l_message := substr(l_json.get_string('error'), 1, 4000);
        elsif l_error.has('message') and l_error.get('message').is_string then
          l_message := l_error.get_string('message');
        end if;

        if l_message is not null then
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
        continue when not l_tables.get(i).is_object;
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
        continue when not l_blocks_in.get(i).is_object;
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

    merge_extra_body(l_body, p_options, p_scope);

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
    l_page           json_object_t;
    l_warnings       json_array_t := json_array_t();
    l_usage_in       json_object_t;
    l_usage          json_object_t := json_object_t();
    l_resp_model     varchar2(255 char);
    l_url            varchar2(4000 char);
  begin
    l_url   := rtrim(coalesce(p_settings.base_url, c_mistral_base_url), '/') || '/ocr';
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
      if l_pages_in.get(i).is_object then
        l_pages.append(mistral_page(treat(l_pages_in.get(i) as json_object_t), i));
      else
        -- keep the position: an empty page stands in for the element
        l_page := json_object_t();
        l_page.put('index', i);
        l_page.put('markdown', empty_clob());
        l_pages.append(l_page);
        l_warnings.append('Page ' || i || ' was not an object');
      end if;
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
    , p_warnings => l_warnings
    , p_raw      => l_resp_json
    );
  end ocr_mistral;


  -- ---- OCI Document Understanding adapter -------------------------------------

  function oci_url (
    p_settings in uc_ai_settings.t_settings
  ) return varchar2
  as
  begin
    -- uc_ai.g_base_url does not apply: as in uc_ai_oci the URL comes from the region.
    -- Same default region as uc_ai_oci.
    return c_oci_url_prefix || coalesce(p_settings.oc_region, 'us-ashburn-1') || '.oci.oraclecloud.com' || c_oci_analyze_path;
  end oci_url;


  /*
   * The box (min and max of the vertices, rounded to 6 decimals) and the polygon
   * ([{x,y}]) of an OCI element with a boundingPolygon. Both are null when the
   * element has no usable vertex.
   */
  procedure oci_geometry (
    p_element    in  json_object_t
  , po_box       out json_object_t
  , po_polygon   out json_array_t
  )
  as
    l_vertices json_array_t;
    l_vertex   json_object_t;
    l_point    json_object_t;
    l_x        number;
    l_y        number;
    l_min_x    number;
    l_min_y    number;
    l_max_x    number;
    l_max_y    number;
  begin
    po_box     := null;
    po_polygon := null;

    if p_element is null
      or not p_element.has('boundingPolygon') or not p_element.get('boundingPolygon').is_object
    then
      return;
    end if;

    if not p_element.get_object('boundingPolygon').has('normalizedVertices')
      or not p_element.get_object('boundingPolygon').get('normalizedVertices').is_array
    then
      return;
    end if;

    l_vertices := p_element.get_object('boundingPolygon').get_array('normalizedVertices');
    po_polygon := json_array_t();

    <<vertex_loop>>
    for i in 0 .. l_vertices.get_size - 1 loop
      continue when not l_vertices.get(i).is_object;
      l_vertex := treat(l_vertices.get(i) as json_object_t);
      continue when not l_vertex.has('x') or not l_vertex.get('x').is_number
                 or not l_vertex.has('y') or not l_vertex.get('y').is_number;

      l_x := l_vertex.get_number('x');
      l_y := l_vertex.get_number('y');
      l_min_x := least(nvl(l_min_x, l_x), l_x);
      l_max_x := greatest(nvl(l_max_x, l_x), l_x);
      l_min_y := least(nvl(l_min_y, l_y), l_y);
      l_max_y := greatest(nvl(l_max_y, l_y), l_y);

      l_point := json_object_t();
      l_point.put('x', l_x);
      l_point.put('y', l_y);
      po_polygon.append(l_point);
    end loop vertex_loop;

    if l_min_x is null then
      po_polygon := null;
      return;
    end if;

    po_box := json_object_t();
    po_box.put('x1', round(l_min_x, 6));
    po_box.put('y1', round(l_min_y, 6));
    po_box.put('x2', round(l_max_x, 6));
    po_box.put('y2', round(l_max_y, 6));
  end oci_geometry;


  /*
   * A cell of a Markdown table: a pipe is escaped and a line break becomes a space.
   * A clob, so a long cell cannot overflow a varchar2.
   */
  function markdown_cell (
    p_text in clob
  ) return clob
  as
  begin
    return trim(replace(replace(replace(replace(p_text, '|', '\|'), chr(13) || chr(10), ' '), chr(10), ' '), chr(13), ' '));
  end markdown_cell;


  /*
   * A Markdown table from an OCI table. The cells of headerRows, bodyRows and
   * footerRows are put in a grid by rowIndex and columnIndex; a position without
   * a cell (a merged cell, a gap) stays empty. Markdown needs a header row, so
   * grid row 0 is the header row, whether OCI calls it a header row or not.
   * The stated columnCount adds empty columns, as long as the grid stays within
   * c_oci_max_grid positions. Returns null when the table holds no usable cell,
   * or when its cells would make a grid of more than c_oci_max_grid positions.
   * The result is built in a clob, so no line can overflow a varchar2.
   */
  function oci_table_markdown (
    p_table in json_object_t
  ) return clob
  as
    l_groups   json_key_list;
    l_rows     json_array_t;
    l_row      json_object_t;
    l_cells    json_array_t;
    l_cell     json_object_t;
    l_grid_arr     t_clob_tab;
    l_row_idx  number;
    l_col_idx  number;
    l_max_row  pls_integer := -1;
    l_max_col  pls_integer := -1;
    l_columns  number;
    l_result   clob;
  begin
    l_groups := json_key_list('headerRows', 'bodyRows', 'footerRows');

    <<group_loop>>
    for g in 1 .. l_groups.count loop
      continue when not p_table.has(l_groups(g)) or not p_table.get(l_groups(g)).is_array;
      l_rows := p_table.get_array(l_groups(g));

      <<row_loop>>
      for r in 0 .. l_rows.get_size - 1 loop
        continue when not l_rows.get(r).is_object;
        l_row := treat(l_rows.get(r) as json_object_t);
        continue when not l_row.has('cells') or not l_row.get('cells').is_array;
        l_cells := l_row.get_array('cells');

        <<cell_loop>>
        for c in 0 .. l_cells.get_size - 1 loop
          continue when not l_cells.get(c).is_object;
          l_cell := treat(l_cells.get(c) as json_object_t);
          continue when not l_cell.has('rowIndex') or not l_cell.get('rowIndex').is_number
                     or not l_cell.has('columnIndex') or not l_cell.get('columnIndex').is_number;

          l_row_idx := l_cell.get_number('rowIndex');
          l_col_idx := l_cell.get_number('columnIndex');
          continue when l_row_idx not between 0 and c_oci_max_index or l_col_idx not between 0 and c_oci_max_index
                     or l_row_idx != trunc(l_row_idx) or l_col_idx != trunc(l_col_idx);

          l_grid_arr(l_row_idx * (c_oci_max_index + 1) + l_col_idx) :=
            case when l_cell.has('text') and l_cell.get('text').is_string
                 then markdown_cell(l_cell.get_clob('text')) end;
          l_max_row := greatest(l_max_row, l_row_idx);
          l_max_col := greatest(l_max_col, l_col_idx);
        end loop cell_loop;
      end loop row_loop;
    end loop group_loop;

    if l_max_row < 0 or (l_max_row + 1) * (l_max_col + 1) > c_oci_max_grid then
      return null;
    end if;

    -- the stated size can be larger than the cells that came back
    if p_table.has('columnCount') and p_table.get('columnCount').is_number then
      l_columns := trunc(p_table.get_number('columnCount'));
      if l_columns > l_max_col + 1 and (l_max_row + 1) * l_columns <= c_oci_max_grid then
        l_max_col := l_columns - 1;
      end if;
    end if;

    sys.dbms_lob.createtemporary(l_result, true);

    <<grid_row_loop>>
    for r in 0 .. l_max_row loop
      sys.dbms_lob.writeappend(l_result, 1, '|');
      <<grid_col_loop>>
      for c in 0 .. l_max_col loop
        sys.dbms_lob.writeappend(l_result, 1, ' ');
        if l_grid_arr.exists(r * (c_oci_max_index + 1) + c) and sys.dbms_lob.getlength(l_grid_arr(r * (c_oci_max_index + 1) + c)) > 0 then
          sys.dbms_lob.append(l_result, l_grid_arr(r * (c_oci_max_index + 1) + c));
        end if;
        sys.dbms_lob.writeappend(l_result, 2, ' |');
      end loop grid_col_loop;
      sys.dbms_lob.writeappend(l_result, 1, chr(10));

      if r = 0 then
        sys.dbms_lob.writeappend(l_result, 1, '|');
        <<separator_loop>>
        for c in 0 .. l_max_col loop
          sys.dbms_lob.writeappend(l_result, 6, ' --- |');
        end loop separator_loop;
        sys.dbms_lob.writeappend(l_result, 1, chr(10));
      end if;
    end loop grid_row_loop;

    -- no trailing line break
    sys.dbms_lob.trim(l_result, sys.dbms_lob.getlength(l_result) - 1);
    return l_result;
  end oci_table_markdown;


  /*
   * Append text to the markdown, after the separator unless the markdown is empty.
   */
  procedure md_append (
    pio_markdown in out nocopy clob
  , p_text       in            clob
  , p_sep        in            varchar2
  )
  as
  begin
    if sys.dbms_lob.getlength(pio_markdown) > 0 then
      sys.dbms_lob.writeappend(pio_markdown, length(p_sep), p_sep);
    end if;
    sys.dbms_lob.append(pio_markdown, p_text);
  end md_append;


  /*
   * One OCI page in the neutral shape. The markdown holds the text lines (a wider
   * vertical gap than one line height starts a new paragraph) and the tables. A
   * table sits where its polygon starts, in reading order, and replaces the lines
   * inside its polygon (they repeat its cells). A table without a polygon comes
   * after the text.
   * Blocks: the text lines first (all of them, also the ones inside a table),
   * then the tables.
   */
  function oci_page (
    p_page     in json_object_t
  , p_position in pls_integer
  ) return json_object_t
  as
    l_page       json_object_t := json_object_t();
    l_dim        json_object_t;
    l_dimensions json_object_t;
    l_lines      json_array_t := json_array_t();
    l_tables     json_array_t := json_array_t();
    l_blocks     json_array_t := json_array_t();
    l_line       json_object_t;
    l_table      json_object_t;
    l_block      json_object_t;
    l_box        json_object_t;
    l_polygon    json_array_t;
    l_text       clob;
    l_markdown   clob;
    l_t_md_arr t_clob_tab;
    l_t_has_box_arr  t_bool_tab;
    l_t_x1_arr       t_num_tab;
    l_t_y1_arr       t_num_tab;
    l_t_x2_arr       t_num_tab;
    l_t_y2_arr       t_num_tab;
    l_t_done_arr     t_bool_tab;
    l_t_block_arr    t_obj_tab;
    l_cx         number;
    l_cy         number;
    l_inside     boolean;
    l_next       pls_integer;
    l_prev_y2    number;
    l_prev_h     number;
    l_after_gap  boolean := false;
    l_index      number;
  begin
    sys.dbms_lob.createtemporary(l_markdown, true);

    if p_page.has('lines') and p_page.get('lines').is_array then
      l_lines := p_page.get_array('lines');
    end if;
    if p_page.has('tables') and p_page.get('tables').is_array then
      l_tables := p_page.get_array('tables');
    end if;

    -- tables first: their markdown and boxes decide where the lines go
    <<table_loop>>
    for t in 0 .. l_tables.get_size - 1 loop
      continue when not l_tables.get(t).is_object;
      l_table := treat(l_tables.get(t) as json_object_t);
      l_text  := oci_table_markdown(l_table);
      continue when l_text is null;

      l_t_md_arr(t) := l_text;
      l_t_done_arr(t) := false;
      oci_geometry(l_table, l_box, l_polygon);
      l_t_has_box_arr(t) := l_box is not null;
      if l_box is not null then
        l_t_x1_arr(t) := l_box.get_number('x1');
        l_t_y1_arr(t) := l_box.get_number('y1');
        l_t_x2_arr(t) := l_box.get_number('x2');
        l_t_y2_arr(t) := l_box.get_number('y2');
      end if;

      l_block := json_object_t();
      l_block.put('type', 'table');
      l_block.put('text', l_text);
      if l_table.has('confidence') and l_table.get('confidence').is_number then
        l_block.put('confidence', l_table.get_number('confidence'));
      end if;
      if l_box is not null then
        l_block.put('box', l_box);
        l_block.put('polygon', l_polygon);
      end if;
      -- appended after the text blocks below
      l_t_block_arr(t) := l_block;
    end loop table_loop;

    <<line_loop>>
    for i in 0 .. l_lines.get_size - 1 loop
      continue when not l_lines.get(i).is_object;
      l_line := treat(l_lines.get(i) as json_object_t);
      continue when not l_line.has('text') or not l_line.get('text').is_string;
      l_text := l_line.get_clob('text');
      continue when sys.dbms_lob.getlength(l_text) = 0;

      oci_geometry(l_line, l_box, l_polygon);

      l_block := json_object_t();
      l_block.put('type', 'text');
      l_block.put('text', l_text);
      if l_line.has('confidence') and l_line.get('confidence').is_number then
        l_block.put('confidence', l_line.get_number('confidence'));
      end if;
      if l_box is not null then
        l_block.put('box', l_box);
        l_block.put('polygon', l_polygon);
      end if;
      l_blocks.append(l_block);

      if l_box is not null then
        l_cx := (l_box.get_number('x1') + l_box.get_number('x2')) / 2;
        l_cy := (l_box.get_number('y1') + l_box.get_number('y2')) / 2;

        -- tables that start above this line, the highest first
        <<pending_loop>>
        loop
          l_next := null;
          <<pending_search_loop>>
          for t in 0 .. l_tables.get_size - 1 loop
            if l_t_done_arr.exists(t) and not l_t_done_arr(t) and l_t_has_box_arr(t) and l_t_y1_arr(t) <= l_cy
              and (l_next is null or l_t_y1_arr(t) < l_t_y1_arr(l_next))
            then
              l_next := t;
            end if;
          end loop pending_search_loop;
          exit pending_loop when l_next is null;
          l_t_done_arr(l_next) := true;
          md_append(l_markdown, l_t_md_arr(l_next), chr(10) || chr(10));
          l_after_gap := true;
          l_prev_y2   := null;
        end loop pending_loop;

        -- a line inside a table repeats its cells
        l_inside := false;
        <<inside_loop>>
        for t in 0 .. l_tables.get_size - 1 loop
          if l_t_done_arr.exists(t) and l_t_has_box_arr(t)
            and l_cx between l_t_x1_arr(t) and l_t_x2_arr(t) and l_cy between l_t_y1_arr(t) and l_t_y2_arr(t)
          then
            l_inside := true;
            exit inside_loop;
          end if;
        end loop inside_loop;
        continue when l_inside;
      end if;

      md_append(
        l_markdown
      , l_text
      , case when l_after_gap or (l_prev_y2 is not null and l_box is not null and l_prev_h > 0
                                  and l_box.get_number('y1') - l_prev_y2 > l_prev_h)
             then chr(10) || chr(10) else chr(10) end
      );
      l_after_gap := false;
      if l_box is not null then
        l_prev_y2 := l_box.get_number('y2');
        l_prev_h  := l_box.get_number('y2') - l_box.get_number('y1');
      else
        l_prev_y2 := null;
      end if;
    end loop line_loop;

    -- tables not placed yet: no polygon, or below the last line
    <<rest_loop>>
    for t in 0 .. l_tables.get_size - 1 loop
      if l_t_done_arr.exists(t) and not l_t_done_arr(t) then
        l_t_done_arr(t) := true;
        md_append(l_markdown, l_t_md_arr(t), chr(10) || chr(10));
        l_after_gap := true;
        l_prev_y2   := null;
      end if;
    end loop rest_loop;

    <<table_block_loop>>
    for t in 0 .. l_tables.get_size - 1 loop
      if l_t_done_arr.exists(t) then
        l_blocks.append(l_t_block_arr(t));
      end if;
    end loop table_block_loop;

    l_index := case when p_page.has('pageNumber') and p_page.get('pageNumber').is_number
                    then p_page.get_number('pageNumber') - 1 else p_position end;
    l_page.put('index', l_index);
    l_page.put('markdown', l_markdown);
    l_page.put('blocks', l_blocks);

    if p_page.has('dimensions') and p_page.get('dimensions').is_object then
      l_dim := p_page.get_object('dimensions');
      if l_dim.has('width') and l_dim.get('width').is_number and l_dim.has('height') and l_dim.get('height').is_number then
        l_dimensions := json_object_t();
        l_dimensions.put('width', l_dim.get_number('width'));
        l_dimensions.put('height', l_dim.get_number('height'));
        if l_dim.has('unit') and l_dim.get('unit').is_string then
          l_dimensions.put('unit', l_dim.get_string('unit'));
        end if;
        l_page.put('dimensions', l_dimensions);
      end if;
    end if;

    return l_page;
  end oci_page;


  /*
   * The request body. Options are passed on (language, documentType, features and
   * any other key); the neutral keys pages and tables and the key extra_body are
   * not OCI keys. A passed features array wins over the default; features that is
   * not an array (also through extra_body) raises -20503. compartmentId and
   * document are reserved and set by the caller after this.
   */
  function oci_body (
    p_options in json_object_t
  , p_scope   in varchar2
  ) return json_object_t
  as
    l_body       json_object_t := json_object_t();
    l_keys       json_key_list;
    l_features   json_array_t := json_array_t();
    l_feature    json_object_t;
  begin
    if p_options is not null then
      l_keys := p_options.get_keys;
      <<option_loop>>
      for i in 1 .. l_keys.count loop
        continue when l_keys(i) in ('extra_body', 'tables', 'pages');
        l_body.put(l_keys(i), p_options.get(l_keys(i)));
      end loop option_loop;
    end if;

    if not l_body.has('features') then
      l_feature := json_object_t();
      l_feature.put('featureType', 'TEXT_EXTRACTION');
      l_features.append(l_feature);

      if p_options is not null and p_options.has('tables') and p_options.get('tables').is_true then
        l_feature := json_object_t();
        l_feature.put('featureType', 'TABLE_EXTRACTION');
        l_features.append(l_feature);
      end if;

      l_body.put('features', l_features);
    end if;

    merge_extra_body(l_body, p_options, p_scope);

    -- checked after the merge: extra_body can replace the features too
    if not l_body.get('features').is_array then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => p_scope
      , p0           => 'OCR option features'
      , p1           => 'it must be an array of {"featureType": ...} objects'
      );
    end if;

    return l_body;
  end oci_body;


  /*
   * True when p_index is in the 0-based index list of the neutral option pages.
   */
  function page_selected (
    p_pages in json_array_t
  , p_index in number
  ) return boolean
  as
  begin
    <<selected_loop>>
    for i in 0 .. p_pages.get_size - 1 loop
      if p_pages.get(i).is_number and p_pages.get(i).to_number = p_index then
        return true;
      end if;
    end loop selected_loop;
    return false;
  end page_selected;


  function ocr_oci (
    p_document   in blob
  , p_media_type in varchar2
  , p_options    in json_object_t
  , p_settings   in uc_ai_settings.t_settings
  ) return json_object_t
  as
    l_scope       uc_ai_logger.scope := c_scope_prefix || 'ocr_oci';
    l_url         varchar2(4000 char);
    l_web_credential varchar2(255 char);
    l_body        json_object_t;
    l_doc         json_object_t := json_object_t();
    l_data        clob;
    l_selection   json_array_t;
    l_resp        clob;
    l_resp_json   json_object_t;
    l_pages_in    json_array_t;
    l_pages       json_array_t := json_array_t();
    l_page        json_object_t;
    l_errors      json_array_t;
    l_error       json_object_t;
    l_warnings    json_array_t := json_array_t();
    l_usage       json_object_t := json_object_t();
    l_model       varchar2(255 char);
    l_warning     varchar2(4000 char);
  begin
    l_url := oci_url(p_settings);

    if sys.dbms_lob.getlength(p_document) > c_oci_max_bytes then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_invalid_config
      , p_scope      => l_scope
      , p0           => 'OCR document'
      , p1           => sys.dbms_lob.getlength(p_document) || ' bytes are more than the 8 MB limit of OCI Document Understanding'
      );
    end if;

    if p_settings.oc_compartment_id is null then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_missing_config
      , p_scope      => l_scope
      , p0           => 'OCI provider'
      , p1           => 'g_compartment_id to be configured'
      );
    end if;

    l_selection := pages_option(p_options, l_scope);

    l_body := oci_body(p_options, l_scope);
    l_body.put('compartmentId', p_settings.oc_compartment_id);

    l_data := to_base64(p_document);
    l_doc.put('source', 'INLINE');
    l_doc.put('data', l_data);
    l_body.put('document', l_doc);

    -- OCI signs the Content-Type header: with a charset added every call fails with
    -- 401 "Failed to verify the HTTP(S) Signature". Do not copy the header of uc_ai_oci.
    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers('Content-Type', 'application/json');
    uc_ai_settings.apply_extra_headers(p_settings);

    l_web_credential := coalesce(p_settings.apex_web_credential, p_settings.oc_apex_web_credential);

    -- Never log l_body: it holds the whole document as base64
    uc_ai_logger.log(
      'Calling OCI Document Understanding at ' || l_url || '. Web Credential: ' || nvl(l_web_credential, 'null')
    , l_scope
    , 'source=' || p_media_type || ', ' || sys.dbms_lob.getlength(p_document) || ' bytes'
      || ', option keys=' || nvl(option_keys(p_options), 'none')
    );

    l_resp := uc_ai_http.post(
      p_url                  => l_url
    , p_body                 => l_body.to_clob
    , p_credential_static_id => l_web_credential
    , p_transfer_timeout     => c_transfer_timeout
    );

    l_resp_json := parse_response(l_resp, 'OCI', l_scope);

    if l_resp_json.has('pages') and l_resp_json.get('pages').is_array then
      l_pages_in := l_resp_json.get_array('pages');
    end if;

    -- errors inside a 200 (for example FEATURE_NOT_SUPPORTED for an image without text)
    -- are warnings; without any page the request gave nothing, so that raises
    if l_resp_json.has('errors') and l_resp_json.get('errors').is_array then
      l_errors := l_resp_json.get_array('errors');
      <<error_loop>>
      for i in 0 .. l_errors.get_size - 1 loop
        if l_errors.get(i).is_object then
          l_error   := treat(l_errors.get(i) as json_object_t);
          l_warning := case when l_error.has('code') and l_error.get('code').is_string then l_error.get_string('code') end
                       || case when l_error.has('code') and l_error.get('code').is_string
                                and l_error.has('message') and l_error.get('message').is_string then ': ' end
                       || case when l_error.has('message') and l_error.get('message').is_string then l_error.get_string('message') end;
        elsif l_errors.get(i).is_string then
          l_warning := substr(l_errors.get_string(i), 1, 4000);
        else
          l_warning := null;
        end if;
        l_warnings.append(nvl(l_warning, 'unknown error'));
      end loop error_loop;

      if l_errors.get_size > 0 and (l_pages_in is null or l_pages_in.get_size = 0) then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_provider_response
        , p_scope      => l_scope
        , p0           => 'OCI'
        , p1           => l_warnings.get_string(0)
        , p_extra      => l_resp
        );
      end if;
    end if;

    if l_pages_in is null then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'OCI'
      , p1           => 'response has no pages array'
      , p_extra      => l_resp
      );
    end if;

    <<page_loop>>
    for i in 0 .. l_pages_in.get_size - 1 loop
      continue when not l_pages_in.get(i).is_object;
      l_page := oci_page(treat(l_pages_in.get(i) as json_object_t), i);

      if l_selection is null or page_selected(l_selection, l_page.get_number('index')) then
        l_pages.append(l_page);
      end if;
    end loop page_loop;

    if l_resp_json.has('documentMetadata') and l_resp_json.get('documentMetadata').is_object then
      if l_resp_json.get_object('documentMetadata').has('pageCount')
        and l_resp_json.get_object('documentMetadata').get('pageCount').is_number
      then
        l_usage.put('pages', l_resp_json.get_object('documentMetadata').get_number('pageCount'));
      end if;
    end if;

    l_model := case when l_resp_json.has('textExtractionModelVersion') and l_resp_json.get('textExtractionModelVersion').is_string
                    then l_resp_json.get_string('textExtractionModelVersion') else c_oci_model end;

    uc_ai_logger.log(
      'OCI Document Understanding response'
    , l_scope
    , 'pages=' || l_pages.get_size || ', warnings=' || l_warnings.get_size
      || ', response length=' || sys.dbms_lob.getlength(l_resp)
    );

    return new_result(
      p_pages    => l_pages
    , p_usage    => l_usage
    , p_model    => l_model
    , p_warnings => l_warnings
    , p_raw      => l_resp_json
    );
  end ocr_oci;


  -- ---- Ollama adapter ---------------------------------------------------------

  function ollama_url(
    p_settings in uc_ai_settings.t_settings
  ) return varchar2
  as
  begin
    return rtrim(coalesce(p_settings.base_url, c_ollama_base_url), '/') || '/chat';
  end ollama_url;


  /*
   * The text of the user message: the prompt option or the default prompt, and
   * the line that makes the model answer UNREADABLE for a blank image. The line
   * is left out when the option append_unreadable_hint is false.
   */
  function ollama_prompt(
    p_options in json_object_t
  , p_scope   in varchar2
  ) return varchar2
  as
    l_prompt varchar2(32000 char) := c_ollama_prompt;
    l_hint   boolean := true;
  begin
    if p_options is not null and p_options.has('prompt') and not p_options.get('prompt').is_null then
      if not p_options.get('prompt').is_string then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => p_scope
        , p0           => 'OCR option prompt'
        , p1           => 'it must be a string'
        );
      end if;
      l_prompt := p_options.get_string('prompt');
    end if;

    if p_options is not null and p_options.has('append_unreadable_hint') and p_options.get('append_unreadable_hint').is_false then
      l_hint := false;
    end if;

    if l_hint then
      l_prompt := l_prompt || chr(10) || c_ollama_unreadable_hint;
    end if;

    return l_prompt;
  end ollama_prompt;


  /*
   * Put the option p_key in the body when it is set and not JSON null.
   */
  procedure copy_option (
    pio_body  in out nocopy json_object_t
  , p_options in            json_object_t
  , p_key     in            varchar2
  )
  as
  begin
    if p_options is not null and p_options.has(p_key) and not p_options.get(p_key).is_null then
      pio_body.put(p_key, p_options.get(p_key));
    end if;
  end copy_option;


  /*
   * The request body without the image: the model, stream false, the messages
   * and the passthrough keys options, keep_alive and think.
   */
  function ollama_body(
    p_model   in varchar2
  , p_image   in clob
  , p_options in json_object_t
  , p_scope   in varchar2
  ) return json_object_t
  as
    l_body     json_object_t := json_object_t();
    l_messages json_array_t  := json_array_t();
    l_message  json_object_t;
    l_images   json_array_t  := json_array_t();
  begin
    if p_options is not null then
      if p_options.has('system') and not p_options.get('system').is_null then
        if not p_options.get('system').is_string then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_invalid_config
          , p_scope      => p_scope
          , p0           => 'OCR option system'
          , p1           => 'it must be a string'
          );
        end if;
        l_message := json_object_t();
        l_message.put('role', 'system');
        l_message.put('content', p_options.get_string('system'));
        l_messages.append(l_message);
      end if;

      if p_options.has('options') and not p_options.get('options').is_null and not p_options.get('options').is_object then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_invalid_config
        , p_scope      => p_scope
        , p0           => 'OCR option options'
        , p1           => 'it must be an object'
        );
      end if;
    end if;

    l_images.append(p_image);
    l_message := json_object_t();
    l_message.put('role', 'user');
    l_message.put('content', ollama_prompt(p_options, p_scope));
    l_message.put('images', l_images);
    l_messages.append(l_message);

    l_body.put('model', p_model);
    l_body.put('stream', false);
    l_body.put('messages', l_messages);

    copy_option(l_body, p_options, 'options');
    copy_option(l_body, p_options, 'keep_alive');
    copy_option(l_body, p_options, 'think');

    return l_body;
  end ollama_body;


  /*
   * A model that wraps its whole answer in one Markdown code fence gets the fence
   * removed. Text with more than one fence pair is left as it is.
   */
  function strip_fence(
    p_text in clob
  ) return clob
  as
    l_text clob := p_text;
  begin
    if l_text is null then
      return null;
    end if;

    l_text := regexp_replace(l_text, '^[[:space:]]+|[[:space:]]+$');

    if regexp_count(l_text, '```') = 2
      and regexp_like(l_text, '^```[^' || chr(10) || ']*' || chr(10))
      and regexp_like(l_text, chr(10) || '```$')
    then
      l_text := regexp_replace(l_text, '^```[^' || chr(10) || ']*' || chr(10));
      l_text := regexp_replace(l_text, chr(10) || '```$');
    end if;

    return l_text;
  end strip_fence;


  function is_unreadable(
    p_text in clob
  ) return boolean
  as
  begin
    return sys.dbms_lob.getlength(p_text) <= 30
      and upper(rtrim(rtrim(p_text), '.')) = c_ollama_unreadable_word;
  end is_unreadable;


  function ocr_ollama(
    p_document   in blob
  , p_media_type in varchar2
  , p_model      in varchar2
  , p_options    in json_object_t
  , p_settings   in uc_ai_settings.t_settings
  ) return json_object_t
  as
    l_scope          uc_ai_logger.scope := c_scope_prefix || 'ocr_ollama';
    l_url            varchar2(4000 char);
    l_web_credential varchar2(255 char);
    l_body           json_object_t;
    l_resp           clob;
    l_resp_json      json_object_t;
    l_message        json_object_t;
    l_content        clob;
    l_pages_opt      json_array_t;
    l_pages          json_array_t := json_array_t();
    l_page           json_object_t := json_object_t();
    l_usage          json_object_t := json_object_t();
    l_warnings       json_array_t := json_array_t();
    l_resp_model     varchar2(255 char);
  begin
    if p_model is null then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_missing_config
      , p_scope      => l_scope
      , p0           => 'OCR with provider ' || uc_ai.c_provider_ollama
      , p1           => 'p_model: Ollama has no default OCR model, pass a vision model'
      );
    end if;

    -- the model reads one image, so only page 0 exists
    l_pages_opt := pages_option(p_options, l_scope);
    if l_pages_opt is not null then
      <<page_check_loop>>
      for i in 0 .. l_pages_opt.get_size - 1 loop
        if not l_pages_opt.get(i).is_number or l_pages_opt.get(i).to_number != 0 then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_unsupported_content
          , p_scope      => l_scope
          , p0           => 'a page other than 0 for OCR with provider ' || uc_ai.c_provider_ollama
                            || '. An image is one page'
          );
        end if;
      end loop page_check_loop;
    end if;

    l_url  := ollama_url(p_settings);
    l_body := ollama_body(p_model, to_base64(p_document), p_options, l_scope);

    apex_web_service.clear_request_headers;
    apex_web_service.set_request_headers('Content-Type', 'application/json');
    uc_ai_settings.apply_extra_headers(p_settings);

    l_web_credential := coalesce(p_settings.apex_web_credential, p_settings.ol_apex_web_credential);

    -- Never log l_body: it holds the whole image as base64
    uc_ai_logger.log(
      'Calling Ollama OCR at ' || l_url || '. Web Credential: ' || nvl(l_web_credential, 'null')
    , l_scope
    , 'model=' || p_model
      || ', source=' || p_media_type || ', ' || sys.dbms_lob.getlength(p_document) || ' bytes'
      || ', option keys=' || nvl(option_keys(p_options), 'none')
    );

    l_resp := uc_ai_http.post(
      p_url                  => l_url
    , p_body                 => l_body.to_clob
    , p_credential_static_id => l_web_credential
    , p_transfer_timeout     => c_transfer_timeout
    );

    l_resp_json := parse_response(l_resp, 'Ollama', l_scope);

    -- a 200 can still carry {"error": "..."}
    if l_resp_json.has('error') and not l_resp_json.get('error').is_null then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'Ollama'
      , p1           => case when l_resp_json.get('error').is_string
                             then substr(l_resp_json.get_string('error'), 1, 4000) else 'error response' end
      , p_extra      => l_resp
      );
    end if;

    if not l_resp_json.has('message') or not l_resp_json.get('message').is_object then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'Ollama'
      , p1           => 'response has no message object'
      , p_extra      => l_resp
      );
    end if;

    -- message.thinking is ignored; it stays in raw
    l_message := l_resp_json.get_object('message');
    if l_message.has('content') and l_message.get('content').is_string then
      l_content := strip_fence(l_message.get_clob('content'));
    end if;

    -- an empty page has the markdown "" as in the other adapters, not JSON null
    if l_content is null or sys.dbms_lob.getlength(l_content) = 0 then
      l_content := empty_clob();
      l_warnings.append('The model returned no text');
    elsif is_unreadable(l_content) then
      l_content := empty_clob();
      l_warnings.append('The model reported that the image is blank or unreadable');
    end if;

    l_page.put('index', 0);
    l_page.put('markdown', l_content);
    l_pages.append(l_page);

    if l_resp_json.has('prompt_eval_count') and l_resp_json.get('prompt_eval_count').is_number then
      l_usage.put('input_tokens', l_resp_json.get_number('prompt_eval_count'));
    end if;
    if l_resp_json.has('eval_count') and l_resp_json.get('eval_count').is_number then
      l_usage.put('output_tokens', l_resp_json.get_number('eval_count'));
    end if;

    l_resp_model := case when l_resp_json.has('model') and l_resp_json.get('model').is_string
                         then l_resp_json.get_string('model') else p_model end;

    uc_ai_logger.log(
      'Ollama OCR response'
    , l_scope
    , 'warnings=' || l_warnings.get_size || ', response length=' || sys.dbms_lob.getlength(l_resp)
    );

    return new_result(
      p_pages    => l_pages
    , p_usage    => l_usage
    , p_model    => l_resp_model
    , p_warnings => l_warnings
    , p_raw      => l_resp_json
    );
  end ocr_ollama;


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

    -- 1. provider: null, unknown and providers without OCR raise the same error
    if p_provider is null or p_provider not in (uc_ai.c_provider_mistral, uc_ai.c_provider_oci, uc_ai.c_provider_ollama) then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_unknown_provider
      , p_scope      => l_scope
      , p_message    => 'Provider %0 has no OCR support. OCR providers: '
                        || uc_ai.c_provider_mistral || ', ' || uc_ai.c_provider_oci || ', ' || uc_ai.c_provider_ollama
      , p0           => nvl(p_provider, 'null')
      );
    end if;

    -- 2. input: one source, not empty, a media type the provider accepts
    if p_url is not null then
      -- only Mistral fetches a document from a URL
      if p_provider != uc_ai.c_provider_mistral then
        uc_ai_error.raise_error(
          p_error_code => uc_ai_error.c_err_unsupported_content
        , p_scope      => l_scope
        , p0           => 'a document URL for OCR with provider ' || p_provider || '. Pass the document as a blob'
        );
      end if;

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
    if p_provider = uc_ai.c_provider_oci then
      return ocr_oci(
        p_document   => p_document
      , p_media_type => l_media_type
      , p_options    => p_options
      , p_settings   => p_settings
      );
    end if;

    if p_provider = uc_ai.c_provider_ollama then
      return ocr_ollama(
        p_document   => p_document
      , p_media_type => l_media_type
      , p_model      => p_model
      , p_options    => p_options
      , p_settings   => p_settings
      );
    end if;

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
