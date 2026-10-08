create or replace package body uc_ai_decisions as

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  -- A decision call with images can take longer than a chat call
  c_transfer_timeout constant pls_integer := 300;

  c_openai_base_url   constant varchar2(100 char) := 'https://api.openai.com/v1';
  c_typesafe_base_url constant varchar2(100 char) := 'https://api.typesafe.ai/v1';
  -- OpenRouter Decisions is an alpha endpoint: <base>/alpha/decisions
  c_openrouter_base_url constant varchar2(100 char) := 'https://openrouter.ai/api';

  -- neutral question types
  c_type_boolean constant varchar2(10 char) := 'boolean';
  c_type_choice  constant varchar2(10 char) := 'choice';
  c_type_score   constant varchar2(10 char) := 'score';
  -- neutral answer type of a question the provider refused
  c_type_refused constant varchar2(10 char) := 'refused';

  c_id_pattern constant varchar2(100 char) := '^[A-Za-z][A-Za-z0-9_]{0,63}$';

  -- Every provider reports probabilities, scores and confidence with 2 decimals.
  -- A reported value can be off by half a unit of the last decimal. The distribution
  -- checks allow that for each rounded value that goes into a sum or a mean.
  c_epsilon   constant number := 0.000001;
  c_half_unit constant number := 0.005;

  -- Per-provider limits. A new provider adds one branch to limits_of,
  -- known_options and default_model, one to is_supported and one to the dispatcher.
  type t_limits is record (
    max_choices pls_integer
  , max_levels  pls_integer
    -- comma separated, without spaces (membership test is instr on ',type,').
    -- Null: the provider takes no files (text only).
  , media_types varchar2(1000 char)
  );


  -- ---- provider table ---------------------------------------------------------

  function is_supported (
    p_provider in varchar2
  ) return boolean
  as
  begin
    return p_provider in (uc_ai.c_provider_openai, uc_ai.c_provider_typesafe, uc_ai.c_provider_openrouter);
  end is_supported;


  function limits_of (
    p_provider in varchar2
  ) return t_limits
  as
    l_limits t_limits;
  begin
    l_limits.max_choices := 255;
    l_limits.max_levels  := 10;

    if p_provider in (uc_ai.c_provider_typesafe, uc_ai.c_provider_openrouter) then
      -- TypeSafe jev: up to 255 choices, up to 10 levels, text only (no image input).
      -- OpenRouter documents no limits and no image input; it uses the same ones.
      l_limits.media_types := null;
    else
      -- OpenAI Decisions: 2 to 255 choices, 2 to 10 levels, images as data URLs
      l_limits.media_types := 'image/png,image/jpeg,image/webp';
    end if;

    return l_limits;
  end limits_of;


  /*
   * The p_options keys the provider understands, comma separated.
   */
  function known_options (
    p_provider in varchar2
  ) return varchar2
  as
  begin
    return case p_provider
             when uc_ai.c_provider_typesafe then 'extra_body'
             when uc_ai.c_provider_openrouter then 'extra_body'
             else 'safety_identifier,extra_body'
           end;
  end known_options;


  function default_model (
    p_provider in varchar2
  ) return varchar2
  as
  begin
    return case p_provider
             when uc_ai.c_provider_typesafe then uc_ai_typesafe.c_model_jev_latest
             when uc_ai.c_provider_openrouter then uc_ai_openrouter.c_decision_model_jev
             else uc_ai_openai.c_model_gpt_6_luna
           end;
  end default_model;


  -- ---- shared helpers ---------------------------------------------------------

  procedure invalid_input (
    p_what  in varchar2
  , p_why   in varchar2
  , p_scope in varchar2
  )
  as
  begin
    uc_ai_error.raise_error(
      p_error_code => uc_ai_error.c_err_invalid_config
    , p_scope      => p_scope
    , p0           => p_what
    , p1           => p_why
    );
  end invalid_input;


  procedure unsupported_input (
    p_what  in varchar2
  , p_scope in varchar2
  )
  as
  begin
    uc_ai_error.raise_error(
      p_error_code => uc_ai_error.c_err_unsupported_content
    , p_scope      => p_scope
    , p0           => p_what
    );
  end unsupported_input;


  /*
   * A response that does not match the request. The raw response goes to the log.
   */
  procedure format_error (
    p_message in varchar2
  , p_raw     in clob
  , p_scope   in varchar2
  )
  as
  begin
    uc_ai_error.raise_error(
      p_error_code => uc_ai_error.c_err_format_processing
    , p_scope      => p_scope
    , p0           => p_message
    , p_extra      => p_raw
    );
  end format_error;


  /*
   * The string value of a key, or null when the key is missing, null or not a
   * string. Read with get_clob: a string can be longer than 32k.
   */
  function text_of (
    p_obj in json_object_t
  , p_key in varchar2
  ) return clob
  as
  begin
    if p_obj.has(p_key) and p_obj.get(p_key).is_string then
      return p_obj.get_clob(p_key);
    end if;
    return null;
  end text_of;


  /*
   * The string value of a key as varchar2, for ids, types and option values.
   * Null when the key is missing, not a string or longer than 4000 characters.
   */
  function short_text_of (
    p_obj in json_object_t
  , p_key in varchar2
  ) return varchar2
  as
    l_text clob;
  begin
    l_text := text_of(p_obj, p_key);

    if l_text is null or sys.dbms_lob.getlength(l_text) > 4000 then
      return null;
    end if;

    return sys.dbms_lob.substr(l_text, 4000, 1);
  end short_text_of;


  /*
   * Null, empty or only white space. A text of more than 4000 characters counts
   * as not blank without a look at the rest.
   */
  function is_blank (
    p_text in clob
  ) return boolean
  as
  begin
    if p_text is null or sys.dbms_lob.getlength(p_text) = 0 then
      return true;
    end if;

    return sys.dbms_lob.getlength(p_text) <= 4000
       and regexp_like(sys.dbms_lob.substr(p_text, 4000, 1), '^\s*$');
  end is_blank;


  procedure append_text (
    pio_clob in out nocopy clob
  , p_text   in            varchar2
  )
  as
  begin
    sys.dbms_lob.writeappend(pio_clob, length(p_text), p_text);
  end append_text;


  /*
   * 'Image/PNG; charset=binary' -> 'image/png'. image/jpg is a common misspelling
   * of image/jpeg.
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


  /*
   * A number as text for a message: dot as decimal character, no trailing zeros.
   */
  function num_text (
    p_number in number
  ) return varchar2
  as
  begin
    return rtrim(
      to_char(round(p_number, 6), 'FM9999990.999999', 'NLS_NUMERIC_CHARACTERS=''.,''')
    , '.'
    );
  end num_text;


  /*
   * Copies a number from one object to another when it is there.
   */
  procedure copy_number (
    p_from in            json_object_t
  , p_key  in            varchar2
  , pio_to in out nocopy json_object_t
  )
  as
  begin
    if p_from.has(p_key) and p_from.get(p_key).is_number then
      pio_to.put(p_key, p_from.get_number(p_key));
    end if;
  end copy_number;


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
      l_result := substr(l_result || case when i > 1 then ',' end || l_keys(i), 1, 500);
    end loop key_loop;

    return l_result;
  end option_keys;


  -- ---- neutral checks (before any request) ------------------------------------

  /*
   * One question. Raises -20503 for a malformed question and -20508 for a
   * question the provider cannot take. A key the neutral model does not know adds
   * a warning.
   */
  procedure check_question (
    p_id       in            varchar2
  , p_question in            json_object_t
  , p_limits   in            t_limits
  , pio_warnings in out nocopy json_array_t
  , p_scope    in            varchar2
  )
  as
    l_what     varchar2(200 char) := 'question "' || p_id || '"';
    l_keys     json_key_list;
    l_type     varchar2(4000 char);
    l_criteria json_object_t;
    l_levels   json_array_t;
    l_count    pls_integer;
  begin
    l_keys := p_question.get_keys;
    <<key_loop>>
    for i in 1 .. l_keys.count loop
      if l_keys(i) not in ('type', 'instructions', 'criteria') then
        pio_warnings.append('Question "' || p_id || '": the key "' || substr(l_keys(i), 1, 100) || '" is not supported and was ignored');
      end if;
    end loop key_loop;

    if not p_question.has('type') or not p_question.get('type').is_string then
      invalid_input(l_what, 'type is missing. Use boolean, choice or score', p_scope);
    end if;

    l_type := short_text_of(p_question, 'type');
    if l_type is null or l_type not in (c_type_boolean, c_type_choice, c_type_score) then
      invalid_input(l_what, 'type "' || substr(l_type, 1, 100) || '" is not supported. Use boolean, choice or score', p_scope);
    end if;

    if is_blank(text_of(p_question, 'instructions')) then
      invalid_input(l_what, 'instructions are missing. Pass a non-empty string', p_scope);
    end if;

    -- boolean: criteria is optional
    if l_type = c_type_boolean then
      if p_question.has('criteria') and not p_question.get('criteria').is_null then
        if not p_question.get('criteria').is_object then
          invalid_input(l_what, 'criteria of a boolean question must be an object {"true": "...", "false": "..."}', p_scope);
        end if;

        l_criteria := p_question.get_object('criteria');
        l_keys     := l_criteria.get_keys;
        <<boolean_key_loop>>
        for i in 1 .. l_keys.count loop
          if l_keys(i) not in ('true', 'false') then
            invalid_input(l_what, 'criteria of a boolean question allows the keys true and false, not "' || substr(l_keys(i), 1, 100) || '"', p_scope);
          end if;
          if not l_criteria.get(l_keys(i)).is_string and not l_criteria.get(l_keys(i)).is_null then
            invalid_input(l_what, 'criteria.' || l_keys(i) || ' must be a string', p_scope);
          end if;
        end loop boolean_key_loop;
      end if;

      return;
    end if;

    -- choice and score need criteria
    if l_type = c_type_choice then
      if not p_question.has('criteria') or not p_question.get('criteria').is_object then
        invalid_input(l_what, 'a choice question needs criteria: an object {"option": "description", ...} with at least 2 options', p_scope);
      end if;

      l_criteria := p_question.get_object('criteria');
      l_keys     := l_criteria.get_keys;
      l_count    := l_keys.count;

      if l_count < 2 then
        invalid_input(l_what, 'a choice question needs at least 2 options in criteria, found ' || l_count, p_scope);
      end if;

      if l_count > p_limits.max_choices then
        unsupported_input(l_count || ' options in ' || l_what || '. The provider allows at most ' || p_limits.max_choices, p_scope);
      end if;

      <<choice_key_loop>>
      for i in 1 .. l_count loop
        if l_keys(i) is null then
          invalid_input(l_what, 'an option name is empty', p_scope);
        end if;
        if not l_criteria.get(l_keys(i)).is_string and not l_criteria.get(l_keys(i)).is_null then
          invalid_input(l_what, 'the description of option "' || substr(l_keys(i), 1, 100) || '" must be a string or null', p_scope);
        end if;
      end loop choice_key_loop;
    else
      if not p_question.has('criteria') or not p_question.get('criteria').is_array then
        invalid_input(l_what, 'a score question needs criteria: an array of level descriptions with at least 2 levels', p_scope);
      end if;

      l_levels := p_question.get_array('criteria');
      l_count  := l_levels.get_size;

      if l_count < 2 then
        invalid_input(l_what, 'a score question needs at least 2 levels in criteria, found ' || l_count, p_scope);
      end if;

      if l_count > p_limits.max_levels then
        unsupported_input(l_count || ' levels in ' || l_what || '. The provider allows at most ' || p_limits.max_levels, p_scope);
      end if;

      <<level_loop>>
      for i in 0 .. l_count - 1 loop
        if not l_levels.get(i).is_string and not l_levels.get(i).is_null then
          invalid_input(l_what, 'the description of level ' || i || ' must be a string or null', p_scope);
        end if;
      end loop level_loop;
    end if;
  end check_question;


  procedure check_questions (
    p_questions  in            json_object_t
  , p_limits     in            t_limits
  , pio_warnings in out nocopy json_array_t
  , p_scope      in            varchar2
  )
  as
    l_ids json_key_list;
  begin
    if p_questions is null then
      invalid_input('questions', 'it is null. Pass an object with at least one question', p_scope);
    end if;

    l_ids := p_questions.get_keys;
    if l_ids.count = 0 then
      invalid_input('questions', 'it is empty. Pass at least one question', p_scope);
    end if;

    <<question_loop>>
    for i in 1 .. l_ids.count loop
      -- $ also matches before a trailing line feed, so that is checked on its own
      if not regexp_like(l_ids(i), c_id_pattern) or instr(l_ids(i), chr(10)) > 0 then
        invalid_input(
          'question id "' || replace(substr(l_ids(i), 1, 100), chr(10), ' ') || '"'
        , 'an id starts with a letter and has up to 64 letters, digits or underscores'
        , p_scope
        );
      end if;

      if not p_questions.get(l_ids(i)).is_object then
        invalid_input('question "' || l_ids(i) || '"', 'it must be a JSON object', p_scope);
      end if;

      check_question(l_ids(i), p_questions.get_object(l_ids(i)), p_limits, pio_warnings, p_scope);
    end loop question_loop;
  end check_questions;


  procedure check_state (
    p_state in clob
  , p_files in json_array_t
  , p_scope in varchar2
  )
  as
  begin
    if is_blank(p_state) and (p_files is null or p_files.get_size = 0) then
      invalid_input('state', 'it is null or empty and there is no file. Pass text, an image or both', p_scope);
    end if;
  end check_state;


  /*
   * The files are create_file_content objects. Raises -20503 for an object of
   * another shape and -20508 for a media type the provider does not take.
   */
  procedure check_files (
    p_files  in json_array_t
  , p_limits in t_limits
  , p_scope  in varchar2
  )
  as
    l_file       json_object_t;
    l_media_type varchar2(200 char);
    l_what       varchar2(100 char);
  begin
    if p_files is null then
      return;
    end if;

    -- a provider without media types takes text only
    if p_limits.media_types is null and p_files.get_size > 0 then
      unsupported_input('files. The provider takes text only, pass the state as text', p_scope);
    end if;

    <<file_loop>>
    for i in 0 .. p_files.get_size - 1 loop
      l_what := 'file ' || (i + 1);

      if not p_files.get(i).is_object then
        invalid_input(l_what, 'it must be an object from uc_ai_message_api.create_file_content', p_scope);
      end if;

      l_file := treat(p_files.get(i) as json_object_t);

      if l_file.has('type') and l_file.get('type').is_string and l_file.get_string('type') != 'file' then
        invalid_input(l_what, 'type must be file, found "' || substr(l_file.get_string('type'), 1, 100) || '"', p_scope);
      end if;

      l_media_type := normalize_media_type(short_text_of(l_file, 'mediaType'));
      if l_media_type is null then
        invalid_input(l_what, 'mediaType is missing', p_scope);
      end if;

      if instr(',' || p_limits.media_types || ',', ',' || l_media_type || ',') = 0 then
        unsupported_input(
          'media type ' || substr(l_media_type, 1, 100) || ' for ' || l_what
          || '. Supported: ' || replace(p_limits.media_types, ',', ', ')
        , p_scope
        );
      end if;

      if is_blank(text_of(l_file, 'data')) then
        invalid_input(l_what, 'data is missing. Pass the base64 of the file', p_scope);
      end if;
    end loop file_loop;
  end check_files;


  /*
   * p_options keys: safety_identifier must be a string, extra_body an object. A
   * key the provider does not know adds a warning and is ignored.
   */
  procedure check_options (
    p_options    in            json_object_t
  , p_provider   in            varchar2
  , pio_warnings in out nocopy json_array_t
  , p_scope      in            varchar2
  )
  as
    l_keys json_key_list;
  begin
    if p_options is null then
      return;
    end if;

    l_keys := p_options.get_keys;
    <<option_loop>>
    for i in 1 .. l_keys.count loop
      if instr(',' || known_options(p_provider) || ',', ',' || l_keys(i) || ',') = 0 then
        pio_warnings.append('Option "' || substr(l_keys(i), 1, 100) || '" is not supported for provider ' || p_provider || ' and was ignored');
      elsif p_options.get(l_keys(i)).is_null then
        null;
      elsif l_keys(i) = 'safety_identifier' and not p_options.get(l_keys(i)).is_string then
        invalid_input('option safety_identifier', 'it must be a string', p_scope);
      elsif l_keys(i) = 'extra_body' and not p_options.get(l_keys(i)).is_object then
        invalid_input('option extra_body', 'it must be a JSON object', p_scope);
      end if;
    end loop option_loop;
  end check_options;


  -- ---- distribution checks (warnings) -----------------------------------------

  /*
   * Probabilities that do not sum to 1 give a warning. Every probability is
   * rounded, so each one adds half a unit of rounding to the allowed deviation.
   */
  procedure check_sum (
    p_id           in            varchar2
  , p_probabilities in           json_object_t
  , pio_warnings   in out nocopy json_array_t
  )
  as
    l_keys json_key_list := p_probabilities.get_keys;
    l_sum  number := 0;
  begin
    <<sum_loop>>
    for i in 1 .. l_keys.count loop
      l_sum := l_sum + p_probabilities.get_number(l_keys(i));
    end loop sum_loop;

    if abs(l_sum - 1) > c_epsilon + c_half_unit * l_keys.count then
      pio_warnings.append(
        'Question "' || p_id || '": the probabilities sum to ' || num_text(l_sum) || ', not 1'
      );
    end if;
  end check_sum;


  /*
   * A score that differs from the probability-weighted mean of the level indexes
   * gives a warning. Rounding of probability i moves the mean by up to
   * 0.005 * i, and the score is rounded itself.
   */
  procedure check_mean (
    p_id            in            varchar2
  , p_score         in            number
  , p_probabilities in            json_object_t
  , pio_warnings    in out nocopy json_array_t
  )
  as
    l_keys      json_key_list := p_probabilities.get_keys;
    l_mean      number := 0;
    l_tolerance number := c_epsilon + c_half_unit;
  begin
    <<mean_loop>>
    for i in 1 .. l_keys.count loop
      l_mean      := l_mean + to_number(l_keys(i)) * p_probabilities.get_number(l_keys(i));
      l_tolerance := l_tolerance + c_half_unit * to_number(l_keys(i));
    end loop mean_loop;

    if abs(p_score - l_mean) > l_tolerance then
      pio_warnings.append(
        'Question "' || p_id || '": the score ' || num_text(p_score)
        || ' differs from the probability-weighted mean ' || num_text(l_mean)
      );
    end if;
  end check_mean;


  -- ---- HTTP -------------------------------------------------------------------

  /*
   * The message of a "detail" error body (TypeSafe, FastAPI shaped). detail is a
   * string, an object {"error_type", "message"} or a list of validation items
   * {"loc": [...], "msg": "..."}. Null for any other shape.
   *
   * A validation item also has "input", an echo of the offending part of the
   * request, which can hold the state. It is never read here.
   */
  function detail_message (
    p_json in json_object_t
  ) return varchar2
  as
    -- SQLERRM shows 512 bytes, so a long list has to stay short
    c_max_items constant pls_integer := 3;
    l_detail  json_element_t;
    l_items   json_array_t;
    l_item    json_object_t;
    l_loc     json_array_t;
    l_param   varchar2(500 char);
    l_message varchar2(3000 char);
    l_part    varchar2(1000 char);
  begin
    l_detail := p_json.get('detail');

    if l_detail is null then
      return null;
    elsif l_detail.is_string then
      return substr(p_json.get_string('detail'), 1, 3000);
    elsif l_detail.is_object then
      return substr(short_text_of(treat(l_detail as json_object_t), 'message'), 1, 3000);
    elsif not l_detail.is_array then
      return null;
    end if;

    l_items := treat(l_detail as json_array_t);
    <<item_loop>>
    for i in 0 .. least(l_items.get_size, c_max_items) - 1 loop
      if not l_items.get(i).is_object then
        continue;
      end if;
      l_item := treat(l_items.get(i) as json_object_t);

      -- loc is the path of the field, starting with "body"
      l_param := null;
      if l_item.has('loc') and l_item.get('loc').is_array then
        l_loc := l_item.get_array('loc');
        <<loc_loop>>
        for j in 0 .. l_loc.get_size - 1 loop
          if l_loc.get(j).is_scalar and not (j = 0 and l_loc.get_string(j) = 'body') then
            l_param := substr(l_param || case when l_param is not null then '.' end || l_loc.get_string(j), 1, 500);
          end if;
        end loop loc_loop;
      end if;

      l_part := substr(coalesce(short_text_of(l_item, 'msg'), 'invalid') || case when l_param is not null then ' (param ' || l_param || ')' end, 1, 200);
      l_message := substr(l_message || case when l_message is not null then '; ' end || l_part, 1, 3000);
    end loop item_loop;

    if l_items.get_size > c_max_items then
      l_message := substr(l_message || '; and ' || (l_items.get_size - c_max_items) || ' more', 1, 3000);
    end if;

    return l_message;
  end detail_message;


  /*
   * Parse a provider response. An error status with an error body becomes -20302
   * with the provider's own message (OpenAI: an "error" object, TypeSafe: a
   * "detail"); anything else that is not JSON or not a success is left to
   * uc_ai_error.parse_json_response.
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
    l_param   varchar2(500 char);
    l_detail  varchar2(3000 char);
  begin
    if nvl(l_status, 0) >= 400 then
      begin
        l_json := json_object_t.parse(p_response);
      exception
        when others then -- @dblinter ignore(g-5040): a body that is not JSON is reported by parse_json_response below
          l_json := null;
      end;

      if l_json is not null and l_json.has('error') and l_json.get('error').is_object then
        l_error   := l_json.get_object('error');
        l_message := substr(short_text_of(l_error, 'message'), 1, 3000);
        l_param   := substr(short_text_of(l_error, 'param'), 1, 500);

        if l_message is not null then
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_provider_response
          , p_scope      => p_scope
          , p0           => p_provider
          , p1           => 'HTTP ' || l_status || ': ' || l_message
                            || case when l_param is not null then ' (param ' || l_param || ')' end
          , p_extra      => p_response
          );
        end if;
      elsif l_json is not null and l_json.has('detail') then
        l_detail := detail_message(l_json);

        if l_detail is not null then
          -- a validation list echoes the request input: keep the response out of the log
          uc_ai_error.raise_error(
            p_error_code => uc_ai_error.c_err_provider_response
          , p_scope      => p_scope
          , p0           => p_provider
          , p1           => 'HTTP ' || l_status || ': ' || l_detail
          , p_extra      => case when l_json.get('detail').is_array then null else p_response end
          );
        end if;
      end if;
    end if;

    return uc_ai_error.parse_json_response(p_response, p_provider, p_scope);
  end parse_response;


  -- ---- OpenAI adapter ---------------------------------------------------------

  /*
   * Adds "Criteria for <p_key>:" and the criterion text to the instructions when
   * the boolean criteria have a text for p_key.
   */
  procedure fold_criterion (
    pio_instructions in out nocopy clob
  , p_criteria       in            json_object_t
  , p_key            in            varchar2
  )
  as
    l_text clob;
  begin
    l_text := text_of(p_criteria, p_key);

    if not is_blank(l_text) then
      append_text(pio_instructions, chr(10) || chr(10) || 'Criteria for ' || p_key || ':' || chr(10));
      sys.dbms_lob.append(pio_instructions, l_text);
    end if;
  end fold_criterion;


  /*
   * The choices of a choice question: one {value, description?} per option.
   */
  function openai_choices (
    p_criteria in json_object_t
  ) return json_array_t
  as
    l_keys  json_key_list := p_criteria.get_keys;
    l_items json_array_t := json_array_t();
    l_item  json_object_t;
    l_text  clob;
  begin
    <<choice_loop>>
    for j in 1 .. l_keys.count loop
      l_item := json_object_t();
      l_item.put('value', l_keys(j));
      l_text := text_of(p_criteria, l_keys(j));
      if not is_blank(l_text) then
        l_item.put('description', l_text);
      end if;
      l_items.append(l_item);
    end loop choice_loop;

    return l_items;
  end openai_choices;


  /*
   * The levels of a score question: one {label, description?} per level. The label
   * is the zero-based index, so the index in the answer and the label agree.
   */
  function openai_levels (
    p_criteria in json_array_t
  ) return json_array_t
  as
    l_items json_array_t := json_array_t();
    l_item  json_object_t;
    l_text  clob;
  begin
    <<level_loop>>
    for j in 0 .. p_criteria.get_size - 1 loop
      l_item := json_object_t();
      l_item.put('label', to_char(j));
      if p_criteria.get(j).is_string then
        l_text := p_criteria.get_clob(j);
        if not is_blank(l_text) then
          l_item.put('description', l_text);
        end if;
      end if;
      l_items.append(l_item);
    end loop level_loop;

    return l_items;
  end openai_levels;


  /*
   * The question array of the OpenAI request, in the order of the question ids.
   * boolean is a predicate; a predicate takes only instructions, so the criteria
   * of a boolean question are folded into the instructions text. A choice option
   * and a score level without a description get none.
   */
  function openai_questions (
    p_questions in json_object_t
  ) return json_array_t
  as
    l_ids      json_key_list := p_questions.get_keys;
    l_result   json_array_t := json_array_t();
    l_question json_object_t;
    l_out      json_object_t;
    l_instr    clob;
  begin
    <<question_loop>>
    for i in 1 .. l_ids.count loop
      l_question := p_questions.get_object(l_ids(i));
      l_out      := json_object_t();

      sys.dbms_lob.createtemporary(l_instr, true);
      sys.dbms_lob.append(l_instr, l_question.get_clob('instructions'));

      case short_text_of(l_question, 'type')
        when c_type_boolean then
          l_out.put('type', 'predicate');
          if l_question.has('criteria') and l_question.get('criteria').is_object then
            fold_criterion(l_instr, l_question.get_object('criteria'), 'true');
            fold_criterion(l_instr, l_question.get_object('criteria'), 'false');
          end if;
        when c_type_choice then
          l_out.put('type', 'choice');
          l_out.put('choices', openai_choices(l_question.get_object('criteria')));
        else
          l_out.put('type', 'score');
          l_out.put('levels', openai_levels(l_question.get_array('criteria')));
      end case;

      l_out.put('name', l_ids(i));
      l_out.put('instructions', l_instr);
      l_result.append(l_out);
    end loop question_loop;

    return l_result;
  end openai_questions;


  /*
   * The input of the OpenAI request when there are files: one user message with an
   * input_text part (left out when the state is empty) and one input_image part
   * per file. image_url is a data URL string. Text-only calls send the state as a
   * plain string (see openai_body).
   */
  function openai_input_messages (
    p_state in clob
  , p_files in json_array_t
  ) return json_array_t
  as
    l_parts   json_array_t := json_array_t();
    l_part    json_object_t;
    l_message json_object_t := json_object_t();
    l_input   json_array_t := json_array_t();
    l_file    json_object_t;
    l_url     clob;
  begin
    if not is_blank(p_state) then
      l_part := json_object_t();
      l_part.put('type', 'input_text');
      l_part.put('text', p_state);
      l_parts.append(l_part);
    end if;

    <<file_loop>>
    for i in 0 .. p_files.get_size - 1 loop
      l_file := treat(p_files.get(i) as json_object_t);

      sys.dbms_lob.createtemporary(l_url, true);
      append_text(l_url, 'data:' || normalize_media_type(short_text_of(l_file, 'mediaType')) || ';base64,');
      -- the data URL needs the base64 in one line
      sys.dbms_lob.append(l_url, replace(replace(l_file.get_clob('data'), chr(10)), chr(13)));

      l_part := json_object_t();
      l_part.put('type', 'input_image');
      l_part.put('image_url', l_url);
      l_parts.append(l_part);
    end loop file_loop;

    l_message.put('role', 'user');
    l_message.put('content', l_parts);
    l_input.append(l_message);
    return l_input;
  end openai_input_messages;


  /*
   * The request body. Order: safety_identifier, extra_body, then the reserved keys
   * model, input and questions, so extra_body cannot replace them.
   */
  function openai_body (
    p_state     in clob
  , p_questions in json_object_t
  , p_model     in varchar2
  , p_files     in json_array_t
  , p_options   in json_object_t
  , p_scope     in varchar2
  ) return json_object_t
  as
    l_body       json_object_t := json_object_t();
    l_extra      json_object_t;
    l_extra_keys json_key_list;
  begin
    if p_options is not null then
      if p_options.has('safety_identifier') and p_options.get('safety_identifier').is_string then
        l_body.put('safety_identifier', p_options.get_string('safety_identifier'));
      end if;

      if p_options.has('extra_body') and p_options.get('extra_body').is_object then
        l_extra      := p_options.get_object('extra_body');
        l_extra_keys := l_extra.get_keys;
        <<extra_loop>>
        for i in 1 .. l_extra_keys.count loop
          l_body.put(l_extra_keys(i), l_extra.get(l_extra_keys(i)));
        end loop extra_loop;
      end if;
    end if;

    l_body.put('model', p_model);

    if p_files is null or p_files.get_size = 0 then
      -- a plain string; the state is not blank here (check_state)
      l_body.put('input', p_state);
    else
      l_body.put('input', openai_input_messages(p_state, p_files));
    end if;

    l_body.put('questions', openai_questions(p_questions));
    return l_body;
  end openai_body;


  /*
   * REFUSAL POLICY. A provider can refuse a single question and still answer the
   * others in the same response. A refused question gets the neutral answer
   * {"type": "refused"}; the other answers are mapped as usual and the call does
   * not raise, not even when every question was refused. A refusal still counts
   * as the answer for its question (a missing, extra or duplicate answer is still
   * an error) but skips the type, option, score and probability checks. A refusal
   * without a name cannot be matched to a question and raises -20304 like any
   * answer without a name. To make a refusal fail the call, raise here.
   */
  function is_refusal (
    p_answer in json_object_t
  ) return boolean
  as
  begin
    return short_text_of(p_answer, 'type') = 'refusal';
  end is_refusal;


  function refused_answer return json_object_t
  as
    l_out json_object_t := json_object_t();
  begin
    l_out.put('type', c_type_refused);
    return l_out;
  end refused_answer;


  /*
   * The number at p_key, in 0..1 when p_probability is true. Raises -20304 when
   * it is missing, not a number or out of range.
   */
  function number_of (
    p_obj         in json_object_t
  , p_key         in varchar2
  , p_what        in varchar2
  , p_probability in boolean
  , p_raw         in clob
  , p_scope       in varchar2
  ) return number
  as
    l_number number;
  begin
    if not p_obj.has(p_key) or not p_obj.get(p_key).is_number then
      format_error(p_what || ' has no number in "' || p_key || '"', p_raw, p_scope);
    end if;

    l_number := p_obj.get_number(p_key);

    if p_probability and (l_number < 0 or l_number > 1) then
      format_error(p_what || ': "' || p_key || '" is ' || num_text(l_number) || ', outside 0 to 1', p_raw, p_scope);
    end if;

    return l_number;
  end number_of;


  /*
   * The probabilities array of a choice or score answer as an object. The key of
   * an entry is its value for a choice and its index for a score; p_levels is the
   * number of levels of a score and null for a choice. An entry for an unknown
   * option or level, a repeated entry or a probability outside 0..1 raises -20304.
   */
  function openai_probabilities (
    p_id        in varchar2
  , p_answer    in json_object_t
  , p_criteria  in json_object_t
  , p_levels    in pls_integer
  , p_raw       in clob
  , p_scope     in varchar2
  ) return json_object_t
  as
    l_what   varchar2(200 char) := 'Answer "' || p_id || '"';
    l_in     json_array_t;
    l_entry  json_object_t;
    l_out    json_object_t := json_object_t();
    l_key    varchar2(4000 char);
    l_index  number;
  begin
    if not p_answer.get('probabilities').is_array then
      format_error(l_what || ': probabilities is not an array', p_raw, p_scope);
    end if;

    l_in := p_answer.get_array('probabilities');
    <<entry_loop>>
    for i in 0 .. l_in.get_size - 1 loop
      if not l_in.get(i).is_object then
        format_error(l_what || ': probabilities entry ' || i || ' is not an object', p_raw, p_scope);
      end if;
      l_entry := treat(l_in.get(i) as json_object_t);

      if p_levels is null then
        l_key := short_text_of(l_entry, 'value');
        if l_key is null or not p_criteria.has(l_key) then
          format_error(l_what || ': probabilities entry ' || i || ' is not one of the options', p_raw, p_scope);
        end if;
      else
        l_index := number_of(l_entry, 'value', l_what || ' probabilities entry ' || i, false, p_raw, p_scope);
        if l_index != trunc(l_index) or l_index < 0 or l_index >= p_levels then
          format_error(l_what || ': probabilities entry ' || i || ' has the level ' || num_text(l_index) || ', outside 0 to ' || (p_levels - 1), p_raw, p_scope);
        end if;
        l_key := to_char(l_index);
      end if;

      if l_out.has(l_key) then
        format_error(l_what || ': probabilities lists "' || substr(l_key, 1, 100) || '" twice', p_raw, p_scope);
      end if;

      l_out.put(l_key, number_of(l_entry, 'probability', l_what || ' probabilities entry ' || i, true, p_raw, p_scope));
    end loop entry_loop;

    return l_out;
  end openai_probabilities;


  function openai_boolean (
    p_id     in varchar2
  , p_answer in json_object_t
  , p_raw    in clob
  , p_scope  in varchar2
  ) return json_object_t
  as
    l_out json_object_t := json_object_t();
  begin
    l_out.put('type', c_type_boolean);
    l_out.put('probability', number_of(p_answer, 'probability', 'Answer "' || p_id || '"', true, p_raw, p_scope));
    return l_out;
  end openai_boolean;


  -- @dblinter ignore(g-7440): pio_warnings is the warning list of the call, threaded through the adapter, so in out is intentional
  function openai_choice (
    p_id           in            varchar2
  , p_answer       in            json_object_t
  , p_question     in            json_object_t
  , pio_warnings   in out nocopy json_array_t
  , p_raw          in            clob
  , p_scope        in            varchar2
  ) return json_object_t
  as
    l_out      json_object_t := json_object_t();
    l_criteria json_object_t;
    l_choice   varchar2(4000 char);
    l_probs    json_object_t;
  begin
    l_criteria := p_question.get_object('criteria');
    l_choice   := short_text_of(p_answer, 'choice');

    if l_choice is null or not l_criteria.has(l_choice) then
      format_error('Answer "' || p_id || '": the choice is not one of the options', p_raw, p_scope);
    end if;

    l_out.put('type', c_type_choice);
    l_out.put('choice', l_choice);

    if p_answer.has('probabilities') and not p_answer.get('probabilities').is_null then
      l_probs := openai_probabilities(p_id, p_answer, l_criteria, null, p_raw, p_scope);
      check_sum(p_id, l_probs, pio_warnings);
      l_out.put('probabilities', l_probs);
    end if;

    return l_out;
  end openai_choice;


  -- @dblinter ignore(g-7440): pio_warnings is the warning list of the call, threaded through the adapter, so in out is intentional
  function openai_score (
    p_id           in            varchar2
  , p_answer       in            json_object_t
  , p_question     in            json_object_t
  , pio_warnings   in out nocopy json_array_t
  , p_raw          in            clob
  , p_scope        in            varchar2
  ) return json_object_t
  as
    l_out    json_object_t := json_object_t();
    l_levels pls_integer;
    l_score  number;
    l_probs  json_object_t;
  begin
    l_levels := p_question.get_array('criteria').get_size;
    l_score  := number_of(p_answer, 'score', 'Answer "' || p_id || '"', false, p_raw, p_scope);

    if l_score < 0 or l_score > l_levels - 1 then
      format_error('Answer "' || p_id || '": the score ' || num_text(l_score) || ' is outside 0 to ' || (l_levels - 1), p_raw, p_scope);
    end if;

    l_out.put('type', c_type_score);
    l_out.put('score', l_score);

    if p_answer.has('probabilities') and not p_answer.get('probabilities').is_null then
      l_probs := openai_probabilities(p_id, p_answer, null, l_levels, p_raw, p_scope);
      check_sum(p_id, l_probs, pio_warnings);
      check_mean(p_id, l_score, l_probs, pio_warnings);
      l_out.put('probabilities', l_probs);
    end if;

    return l_out;
  end openai_score;


  /*
   * The neutral result from the mapped answers and the provider response: usage
   * (the neutral keys, and the whole provider object in provider_metadata),
   * confidence, model, warnings and raw.
   */
  function assemble_result (
    p_resp_json    in json_object_t
  , p_answers      in json_object_t
  , p_confidence   in json_object_t
  , p_model        in varchar2
  , p_warnings     in json_array_t
  ) return json_object_t
  as
    l_usage_in json_object_t;
    l_usage    json_object_t := json_object_t();
    l_metadata json_object_t := json_object_t();
    l_result   json_object_t := json_object_t();
  begin
    if p_resp_json.has('usage') and p_resp_json.get('usage').is_object then
      l_usage_in := p_resp_json.get_object('usage');
      copy_number(l_usage_in, 'input_tokens', l_usage);
      copy_number(l_usage_in, 'output_tokens', l_usage);
      copy_number(l_usage_in, 'total_tokens', l_usage);
      l_metadata.put('usage', l_usage_in);
    end if;

    if p_confidence.get_size > 0 then
      l_metadata.put('confidence', p_confidence);
    end if;

    l_result.put('answers', p_answers);
    l_result.put('usage', l_usage);
    l_result.put('model', coalesce(short_text_of(p_resp_json, 'model'), p_model));
    l_result.put('provider_metadata', l_metadata);
    l_result.put('warnings', p_warnings);
    l_result.put('raw', p_resp_json);
    return l_result;
  end assemble_result;


  /*
   * The neutral result from the OpenAI response. A refusal becomes the answer
   * {"type": "refused"}. Raises -20304 when the answers do not match the questions.
   */
  -- @dblinter ignore(g-7440): pio_warnings is the warning list of the call, threaded through the adapter, so in out is intentional
  function openai_to_neutral (
    p_resp_json    in            json_object_t
  , p_resp         in            clob
  , p_questions    in            json_object_t
  , p_model        in            varchar2
  , pio_warnings   in out nocopy json_array_t
  , p_scope        in            varchar2
  ) return json_object_t
  as
    l_ids        json_key_list := p_questions.get_keys;
    l_answers_in json_array_t;
    l_answer     json_object_t;
    l_position   json_object_t := json_object_t();
    l_name       varchar2(4000 char);
    l_question   json_object_t;
    l_type       varchar2(10 char);
    l_expected   varchar2(10 char);
    l_answers    json_object_t := json_object_t();
    l_confidence json_object_t := json_object_t();
  begin
    if not p_resp_json.has('answers') or not p_resp_json.get('answers').is_array then
      format_error('the response has no answers array', p_resp, p_scope);
    end if;
    l_answers_in := p_resp_json.get_array('answers');

    -- every answer belongs to one question and every question has one answer
    <<index_loop>>
    for i in 0 .. l_answers_in.get_size - 1 loop
      if not l_answers_in.get(i).is_object then
        format_error('answer ' || i || ' is not an object', p_resp, p_scope);
      end if;
      l_name := short_text_of(treat(l_answers_in.get(i) as json_object_t), 'name');

      if l_name is null then
        format_error('answer ' || i || ' has no name', p_resp, p_scope);
      end if;
      if not p_questions.has(l_name) then
        format_error('the response answers the unknown question "' || substr(l_name, 1, 100) || '"', p_resp, p_scope);
      end if;
      if l_position.has(l_name) then
        format_error('the response answers the question "' || l_name || '" twice', p_resp, p_scope);
      end if;
      l_position.put(l_name, i);
    end loop index_loop;

    <<question_loop>>
    for i in 1 .. l_ids.count loop
      if not l_position.has(l_ids(i)) then
        format_error('the response has no answer for the question "' || l_ids(i) || '"', p_resp, p_scope);
      end if;

      l_answer   := treat(l_answers_in.get(l_position.get_number(l_ids(i))) as json_object_t);

      -- see is_refusal: no further checks for a refused question
      if is_refusal(l_answer) then
        l_answers.put(l_ids(i), refused_answer);
        continue;
      end if;

      l_question := p_questions.get_object(l_ids(i));
      l_type     := short_text_of(l_question, 'type');
      l_expected := case l_type when c_type_boolean then 'predicate' else l_type end;

      if short_text_of(l_answer, 'type') is null or short_text_of(l_answer, 'type') != l_expected then
        format_error(
          'Answer "' || l_ids(i) || '" has the type ' || coalesce(short_text_of(l_answer, 'type'), 'null')
          || ' but the question is a ' || l_type
        , p_resp, p_scope);
      end if;

      if l_type = c_type_boolean then
        l_answers.put(l_ids(i), openai_boolean(l_ids(i), l_answer, p_resp, p_scope));
      else
        if l_type = c_type_choice then
          l_answers.put(l_ids(i), openai_choice(l_ids(i), l_answer, l_question, pio_warnings, p_resp, p_scope));
        else
          l_answers.put(l_ids(i), openai_score(l_ids(i), l_answer, l_question, pio_warnings, p_resp, p_scope));
        end if;

        if l_answer.has('confidence') and l_answer.get('confidence').is_number then
          l_confidence.put(l_ids(i), l_answer.get_number('confidence'));
        end if;
      end if;
    end loop question_loop;

    return assemble_result(p_resp_json, l_answers, l_confidence, p_model, pio_warnings);
  end openai_to_neutral;


  -- @dblinter ignore(g-7440): pio_warnings is the warning list of the call, threaded through the adapter, so in out is intentional
  function decide_openai (
    p_state        in            clob
  , p_questions    in            json_object_t
  , p_model        in            varchar2
  , p_files        in            json_array_t
  , p_options      in            json_object_t
  , p_settings     in            uc_ai_settings.t_settings
  , pio_warnings   in out nocopy json_array_t
  ) return json_object_t
  as
    l_scope          uc_ai_logger.scope := c_scope_prefix || 'decide_openai';
    l_model          varchar2(255 char);
    l_url            varchar2(4000 char);
    l_body           clob;
    l_web_credential varchar2(255 char);
    l_resp           clob;
    l_resp_json      json_object_t;
    l_question_keys  json_key_list := p_questions.get_keys;
  begin
    l_url   := rtrim(coalesce(p_settings.base_url, c_openai_base_url), '/') || '/decisions';
    l_model := coalesce(p_model, default_model(uc_ai.c_provider_openai));
    l_body  := openai_body(p_state, p_questions, l_model, p_files, p_options, l_scope).to_clob;

    apex_web_service.clear_request_headers;
    apex_web_service.g_request_headers(1).name  := 'Content-Type';
    apex_web_service.g_request_headers(1).value := 'application/json';

    l_web_credential := coalesce(p_settings.apex_web_credential, p_settings.oa_apex_web_credential);

    if l_web_credential is null then
      apex_web_service.g_request_headers(2).name  := 'Authorization';
      apex_web_service.g_request_headers(2).value := 'Bearer ' || uc_ai_get_key(uc_ai.c_provider_openai);
    end if;

    uc_ai_settings.apply_extra_headers(p_settings);

    -- Never log l_body: it holds the state and base64 images
    uc_ai_logger.log(
      'Calling OpenAI Decisions at ' || l_url || '. Web Credential: ' || nvl(l_web_credential, 'null')
    , l_scope
    , 'model=' || l_model
      || ', questions=' || l_question_keys.count
      || ', files=' || case when p_files is null then 0 else p_files.get_size end
      || ', request size=' || sys.dbms_lob.getlength(l_body) || ' characters'
      || ', option keys=' || nvl(option_keys(p_options), 'none')
    );

    l_resp := uc_ai_http.post(
      p_url                  => l_url
    , p_body                 => l_body
    , p_credential_static_id => l_web_credential
    , p_transfer_timeout     => c_transfer_timeout
    );

    l_resp_json := parse_response(l_resp, 'OpenAI', l_scope);

    -- a 200 can still carry an error body
    if l_resp_json.has('error') and not l_resp_json.get('error').is_null then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => 'OpenAI'
      , p1           => case when l_resp_json.get('error').is_object
                             then coalesce(short_text_of(l_resp_json.get_object('error'), 'message'), 'error response')
                             else 'error response' end
      , p_extra      => l_resp
      );
    end if;

    uc_ai_logger.log(
      'OpenAI Decisions response'
    , l_scope
    , 'response length=' || sys.dbms_lob.getlength(l_resp)
    );

    return openai_to_neutral(l_resp_json, l_resp, p_questions, l_model, pio_warnings, l_scope);
  end decide_openai;


  -- ---- TypeSafe jev and OpenRouter adapter -----------------------------------
  -- Both take the same request (model, state, questions with noul, choice and score)
  -- and give the same answers, so one set of functions serves both.

  /*
   * One boolean criterion text for noul.criteria, or null when there is none.
   */
  procedure put_noul_criterion (
    p_criteria in            json_object_t
  , p_key      in            varchar2
  , pio_target in out nocopy json_object_t
  )
  as
    l_text clob;
  begin
    l_text := text_of(p_criteria, p_key);
    if not is_blank(l_text) then
      pio_target.put(p_key, l_text);
    end if;
  end put_noul_criterion;


  /*
   * The criteria object of a choice question: option -> description. jev takes
   * null for an option without a description.
   */
  function typesafe_choice_criteria (
    p_criteria in json_object_t
  ) return json_object_t
  as
    l_keys   json_key_list := p_criteria.get_keys;
    l_result json_object_t := json_object_t();
    l_text   clob;
  begin
    <<choice_loop>>
    for j in 1 .. l_keys.count loop
      l_text := text_of(p_criteria, l_keys(j));
      if is_blank(l_text) then
        l_result.put_null(l_keys(j));
      else
        l_result.put(l_keys(j), l_text);
      end if;
    end loop choice_loop;

    return l_result;
  end typesafe_choice_criteria;


  /*
   * The criteria array of a score question: one description per level, level 0
   * first. jev rejects null for a level (HTTP 422), so a level without a
   * description gets an empty string. append('') would add a JSON null (an empty
   * varchar2 is null in Oracle), so the empty string comes from parsed JSON.
   */
  function typesafe_score_criteria (
    p_criteria in json_array_t
  ) return json_array_t
  as
    l_result json_array_t := json_array_t();
    l_empty  json_element_t;
    l_text   clob;
  begin
    l_empty := json_array_t.parse('[""]').get(0);

    <<level_loop>>
    for j in 0 .. p_criteria.get_size - 1 loop
      l_text := null;
      if p_criteria.get(j).is_string then
        l_text := p_criteria.get_clob(j);
      end if;

      if is_blank(l_text) then
        l_result.append(l_empty);
      else
        l_result.append(l_text);
      end if;
    end loop level_loop;

    return l_result;
  end typesafe_score_criteria;


  /*
   * The questions object of the TypeSafe request, keyed by question id in the
   * order of the neutral questions. boolean is a noul; its criteria are sent as
   * {true, false} with the keys that have a text, and left out when there is none.
   */
  function typesafe_questions (
    p_questions in json_object_t
  ) return json_object_t
  as
    l_ids      json_key_list := p_questions.get_keys;
    l_result   json_object_t := json_object_t();
    l_question json_object_t;
    l_out      json_object_t;
    l_noul     json_object_t;
  begin
    <<question_loop>>
    for i in 1 .. l_ids.count loop
      l_question := p_questions.get_object(l_ids(i));
      l_out      := json_object_t();

      case short_text_of(l_question, 'type')
        when c_type_boolean then
          l_out.put('type', 'noul');
          l_out.put('instructions', l_question.get_clob('instructions'));
          if l_question.has('criteria') and l_question.get('criteria').is_object then
            l_noul := json_object_t();
            put_noul_criterion(l_question.get_object('criteria'), 'true', l_noul);
            put_noul_criterion(l_question.get_object('criteria'), 'false', l_noul);
            if l_noul.get_size > 0 then
              l_out.put('criteria', l_noul);
            end if;
          end if;
        when c_type_choice then
          l_out.put('type', 'choice');
          l_out.put('instructions', l_question.get_clob('instructions'));
          l_out.put('criteria', typesafe_choice_criteria(l_question.get_object('criteria')));
        else
          l_out.put('type', 'score');
          l_out.put('instructions', l_question.get_clob('instructions'));
          l_out.put('criteria', typesafe_score_criteria(l_question.get_array('criteria')));
      end case;

      l_result.put(l_ids(i), l_out);
    end loop question_loop;

    return l_result;
  end typesafe_questions;


  /*
   * The request body. Order: extra_body, then the reserved keys model, state and
   * questions, so extra_body cannot replace them. The state is always a string.
   */
  function typesafe_body (
    p_state     in clob
  , p_questions in json_object_t
  , p_model     in varchar2
  , p_options   in json_object_t
  ) return json_object_t
  as
    l_body       json_object_t := json_object_t();
    l_extra      json_object_t;
    l_extra_keys json_key_list;
  begin
    if p_options is not null
       and p_options.has('extra_body') and p_options.get('extra_body').is_object
    then
      l_extra      := p_options.get_object('extra_body');
      l_extra_keys := l_extra.get_keys;
      <<extra_loop>>
      for i in 1 .. l_extra_keys.count loop
        l_body.put(l_extra_keys(i), l_extra.get(l_extra_keys(i)));
      end loop extra_loop;
    end if;

    l_body.put('model', p_model);
    l_body.put('state', p_state);
    l_body.put('questions', typesafe_questions(p_questions));
    return l_body;
  end typesafe_body;


  /*
   * The probabilities object of a choice or score answer, copied key by key. The
   * key is an option for a choice (p_levels is null) and a level index as text
   * for a score. An unknown key or a probability outside 0..1 raises -20304. The
   * neutral keys are the same as jev's, in the order jev sent them.
   */
  function typesafe_probabilities (
    p_id        in varchar2
  , p_answer    in json_object_t
  , p_criteria  in json_object_t
  , p_levels    in pls_integer
  , p_raw       in clob
  , p_scope     in varchar2
  ) return json_object_t
  as
    l_what  varchar2(200 char) := 'Answer "' || p_id || '"';
    l_in    json_object_t;
    l_keys  json_key_list;
    l_out   json_object_t := json_object_t();
  begin
    if not p_answer.get('probabilities').is_object then
      format_error(l_what || ': probabilities is not an object', p_raw, p_scope);
    end if;

    l_in   := p_answer.get_object('probabilities');
    l_keys := l_in.get_keys;
    <<entry_loop>>
    for i in 1 .. l_keys.count loop
      if p_levels is null then
        if not p_criteria.has(l_keys(i)) then
          format_error(l_what || ': probabilities has "' || substr(l_keys(i), 1, 100) || '", which is not one of the options', p_raw, p_scope);
        end if;
      elsif not regexp_like(l_keys(i), '^(0|[1-9][0-9]{0,2})$') or to_number(l_keys(i)) >= p_levels then
        format_error(l_what || ': probabilities has the level "' || substr(l_keys(i), 1, 100) || '", outside 0 to ' || (p_levels - 1), p_raw, p_scope);
      end if;

      l_out.put(l_keys(i), number_of(l_in, l_keys(i), l_what || ' probabilities "' || substr(l_keys(i), 1, 100) || '"', true, p_raw, p_scope));
    end loop entry_loop;

    return l_out;
  end typesafe_probabilities;


  -- @dblinter ignore(g-7440): pio_warnings is the warning list of the call, threaded through the adapter, so in out is intentional
  function typesafe_choice (
    p_id           in            varchar2
  , p_answer       in            json_object_t
  , p_question     in            json_object_t
  , pio_warnings   in out nocopy json_array_t
  , p_raw          in            clob
  , p_scope        in            varchar2
  ) return json_object_t
  as
    l_out      json_object_t := json_object_t();
    l_criteria json_object_t;
    l_choice   varchar2(4000 char);
    l_probs    json_object_t;
  begin
    l_criteria := p_question.get_object('criteria');
    l_choice   := short_text_of(p_answer, 'choice');

    if l_choice is null or not l_criteria.has(l_choice) then
      format_error('Answer "' || p_id || '": the choice is not one of the options', p_raw, p_scope);
    end if;

    l_out.put('type', c_type_choice);
    l_out.put('choice', l_choice);

    if p_answer.has('probabilities') and not p_answer.get('probabilities').is_null then
      l_probs := typesafe_probabilities(p_id, p_answer, l_criteria, null, p_raw, p_scope);
      check_sum(p_id, l_probs, pio_warnings);
      l_out.put('probabilities', l_probs);
    end if;

    return l_out;
  end typesafe_choice;


  -- @dblinter ignore(g-7440): pio_warnings is the warning list of the call, threaded through the adapter, so in out is intentional
  function typesafe_score (
    p_id           in            varchar2
  , p_answer       in            json_object_t
  , p_question     in            json_object_t
  , pio_warnings   in out nocopy json_array_t
  , p_raw          in            clob
  , p_scope        in            varchar2
  ) return json_object_t
  as
    l_out    json_object_t := json_object_t();
    l_levels pls_integer;
    l_score  number;
    l_probs  json_object_t;
  begin
    l_levels := p_question.get_array('criteria').get_size;
    l_score  := number_of(p_answer, 'score', 'Answer "' || p_id || '"', false, p_raw, p_scope);

    if l_score < 0 or l_score > l_levels - 1 then
      format_error('Answer "' || p_id || '": the score ' || num_text(l_score) || ' is outside 0 to ' || (l_levels - 1), p_raw, p_scope);
    end if;

    l_out.put('type', c_type_score);
    l_out.put('score', l_score);

    if p_answer.has('probabilities') and not p_answer.get('probabilities').is_null then
      l_probs := typesafe_probabilities(p_id, p_answer, null, l_levels, p_raw, p_scope);
      check_sum(p_id, l_probs, pio_warnings);
      check_mean(p_id, l_score, l_probs, pio_warnings);
      l_out.put('probabilities', l_probs);
    end if;

    return l_out;
  end typesafe_score;


  /*
   * The neutral result from the TypeSafe response. noul becomes boolean with the
   * probability in noul. confidence (choice and score only) goes to
   * provider_metadata. jev has no refusal: every question has a typed answer.
   * Raises -20304 when the answers do not match the questions.
   */
  -- @dblinter ignore(g-7440): pio_warnings is the warning list of the call, threaded through the adapter, so in out is intentional
  function typesafe_to_neutral (
    p_resp_json    in            json_object_t
  , p_resp         in            clob
  , p_questions    in            json_object_t
  , p_model        in            varchar2
  , pio_warnings   in out nocopy json_array_t
  , p_scope        in            varchar2
  ) return json_object_t
  as
    l_ids        json_key_list := p_questions.get_keys;
    l_answers_in json_object_t;
    l_names      json_key_list;
    l_answer     json_object_t;
    l_question   json_object_t;
    l_type       varchar2(10 char);
    l_expected   varchar2(10 char);
    l_answers    json_object_t := json_object_t();
    l_confidence json_object_t := json_object_t();
    l_out        json_object_t;
  begin
    if not p_resp_json.has('answers') or not p_resp_json.get('answers').is_object then
      format_error('the response has no answers object', p_resp, p_scope);
    end if;
    l_answers_in := p_resp_json.get_object('answers');

    -- every answer belongs to one question and every question has one answer
    l_names := l_answers_in.get_keys;
    <<name_loop>>
    for i in 1 .. l_names.count loop
      if not p_questions.has(l_names(i)) then
        format_error('the response answers the unknown question "' || substr(l_names(i), 1, 100) || '"', p_resp, p_scope);
      end if;
    end loop name_loop;

    <<question_loop>>
    for i in 1 .. l_ids.count loop
      if not l_answers_in.has(l_ids(i)) then
        format_error('the response has no answer for the question "' || l_ids(i) || '"', p_resp, p_scope);
      end if;
      if not l_answers_in.get(l_ids(i)).is_object then
        format_error('the answer for the question "' || l_ids(i) || '" is not an object', p_resp, p_scope);
      end if;

      l_answer   := l_answers_in.get_object(l_ids(i));
      l_question := p_questions.get_object(l_ids(i));
      l_type     := short_text_of(l_question, 'type');
      l_expected := case l_type when c_type_boolean then 'noul' else l_type end;

      if short_text_of(l_answer, 'type') is null or short_text_of(l_answer, 'type') != l_expected then
        format_error(
          'Answer "' || l_ids(i) || '" has the type ' || coalesce(short_text_of(l_answer, 'type'), 'null')
          || ' but the question is a ' || l_type
        , p_resp, p_scope);
      end if;

      if l_type = c_type_boolean then
        l_out := json_object_t();
        l_out.put('type', c_type_boolean);
        l_out.put('probability', number_of(l_answer, 'noul', 'Answer "' || l_ids(i) || '"', true, p_resp, p_scope));
        l_answers.put(l_ids(i), l_out);
      else
        if l_type = c_type_choice then
          l_answers.put(l_ids(i), typesafe_choice(l_ids(i), l_answer, l_question, pio_warnings, p_resp, p_scope));
        else
          l_answers.put(l_ids(i), typesafe_score(l_ids(i), l_answer, l_question, pio_warnings, p_resp, p_scope));
        end if;

        if l_answer.has('confidence') and l_answer.get('confidence').is_number then
          l_confidence.put(l_ids(i), l_answer.get_number('confidence'));
        end if;
      end if;
    end loop question_loop;

    return assemble_result(p_resp_json, l_answers, l_confidence, p_model, pio_warnings);
  end typesafe_to_neutral;


  -- @dblinter ignore(g-7440): pio_warnings is the warning list of the call, threaded through the adapter, so in out is intentional
  function decide_state_questions (
    p_provider     in            varchar2
  , p_state        in            clob
  , p_questions    in            json_object_t
  , p_model        in            varchar2
  , p_options      in            json_object_t
  , p_settings     in            uc_ai_settings.t_settings
  , pio_warnings   in out nocopy json_array_t
  ) return json_object_t
  as
    l_scope          uc_ai_logger.scope := c_scope_prefix || 'decide_' || p_provider;
    l_label          varchar2(30 char);
    l_model          varchar2(255 char);
    l_url            varchar2(4000 char);
    l_body           clob;
    l_web_credential varchar2(255 char);
    l_resp           clob;
    l_resp_json      json_object_t;
    l_question_keys  json_key_list := p_questions.get_keys;
  begin
    if p_provider = uc_ai.c_provider_openrouter then
      l_label          := 'OpenRouter';
      l_url            := rtrim(coalesce(p_settings.base_url, c_openrouter_base_url), '/') || '/alpha/decisions';
      l_web_credential := coalesce(p_settings.apex_web_credential, p_settings.or_apex_web_credential);
    else
      l_label          := 'TypeSafe';
      l_url            := rtrim(coalesce(p_settings.base_url, c_typesafe_base_url), '/') || '/systemone';
      l_web_credential := coalesce(p_settings.apex_web_credential, p_settings.ts_apex_web_credential);
    end if;

    l_model := coalesce(p_model, default_model(p_provider));
    l_body  := typesafe_body(p_state, p_questions, l_model, p_options).to_clob;

    apex_web_service.clear_request_headers;
    apex_web_service.g_request_headers(1).name  := 'Content-Type';
    apex_web_service.g_request_headers(1).value := 'application/json';

    if l_web_credential is null then
      apex_web_service.g_request_headers(2).name  := 'Authorization';
      apex_web_service.g_request_headers(2).value := 'Bearer ' || uc_ai_get_key(p_provider);
    end if;

    uc_ai_settings.apply_extra_headers(p_settings);

    -- Never log l_body: it holds the state
    uc_ai_logger.log(
      'Calling ' || l_label || ' at ' || l_url || '. Web Credential: ' || nvl(l_web_credential, 'null')
    , l_scope
    , 'model=' || l_model
      || ', questions=' || l_question_keys.count
      || ', request size=' || sys.dbms_lob.getlength(l_body) || ' characters'
      || ', option keys=' || nvl(option_keys(p_options), 'none')
    );

    l_resp := uc_ai_http.post(
      p_url                  => l_url
    , p_body                 => l_body
    , p_credential_static_id => l_web_credential
    , p_transfer_timeout     => c_transfer_timeout
    );

    l_resp_json := parse_response(l_resp, l_label, l_scope);

    -- a 200 can still carry an error body
    if l_resp_json.has('error') and not l_resp_json.get('error').is_null then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_provider_response
      , p_scope      => l_scope
      , p0           => l_label
      , p1           => case when l_resp_json.get('error').is_object
                             then coalesce(short_text_of(l_resp_json.get_object('error'), 'message'), 'error response')
                             else 'error response' end
      , p_extra      => l_resp
      );
    end if;

    uc_ai_logger.log(
      l_label || ' response'
    , l_scope
    , 'response length=' || sys.dbms_lob.getlength(l_resp)
    );

    return typesafe_to_neutral(l_resp_json, l_resp, p_questions, l_model, pio_warnings, l_scope);
  end decide_state_questions;


  -- ---- dispatcher -------------------------------------------------------------

  function decide (
    p_state     in clob
  , p_questions in json_object_t
  , p_provider  in uc_ai.provider_type
  , p_model     in uc_ai.model_type
  , p_files     in json_array_t
  , p_options   in json_object_t
  , p_settings  in uc_ai_settings.t_settings
  ) return json_object_t
  as
    l_scope    uc_ai_logger.scope := c_scope_prefix || 'decide';
    l_limits   t_limits;
    l_warnings json_array_t := json_array_t();
  begin
    -- 1. provider: null, unknown and providers without decision support raise the same error
    if p_provider is null or not is_supported(p_provider) then
      uc_ai_error.raise_error(
        p_error_code => uc_ai_error.c_err_unknown_provider
      , p_scope      => l_scope
      , p_message    => 'Provider %0 has no decision support. Decision providers: '
                        || uc_ai.c_provider_openai || ', ' || uc_ai.c_provider_typesafe || ', ' || uc_ai.c_provider_openrouter
      , p0           => nvl(p_provider, 'null')
      );
    end if;

    l_limits := limits_of(p_provider);

    -- 2. input: questions, state, files and options. No request is sent if one fails.
    check_questions(p_questions, l_limits, l_warnings, l_scope);
    check_state(p_state, p_files, l_scope);
    check_files(p_files, l_limits, l_scope);
    check_options(p_options, p_provider, l_warnings, l_scope);

    -- 3. adapter
    if p_provider in (uc_ai.c_provider_typesafe, uc_ai.c_provider_openrouter) then
      return decide_state_questions(
        p_provider   => p_provider
      , p_state      => p_state
      , p_questions  => p_questions
      , p_model      => p_model
      , p_options    => p_options
      , p_settings   => p_settings
      , pio_warnings => l_warnings
      );
    end if;

    return decide_openai(
      p_state      => p_state
    , p_questions  => p_questions
    , p_model      => p_model
    , p_files      => p_files
    , p_options    => p_options
    , p_settings   => p_settings
    , pio_warnings => l_warnings
    );
  exception
    when others then -- @dblinter ignore(g-5040): logged and re-raised
      -- errors raised by raise_error are logged already
      -- @dblinter ignore(g-5020): must match the whole -20999..-20000 application-error range, no named exception applies
      if sqlcode not between -20999 and -20000 then
        uc_ai_logger.log_error(
          'Decision failed'
        , l_scope
        , sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
        );
      end if;
      raise;
  end decide;

end uc_ai_decisions;
/
