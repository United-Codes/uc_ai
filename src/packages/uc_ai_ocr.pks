create or replace package uc_ai_ocr
  authid definer
as
  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  *
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  /*
   * Provider dispatcher and shared helpers for OCR. Applications call
   * uc_ai.ocr / uc_ai.ocr_text; those build the settings record and call ocr()
   * here. Each provider has a private adapter in the body that turns the neutral
   * call into the provider request and the provider response into the neutral
   * result.
   *
   * Neutral result (json_object_t):
   *   markdown  all pages joined with a blank line
   *   pages     [{index (0-based), markdown, blocks?, dimensions?}]
   *             block: {type, text, confidence?, box? {x1,y1,x2,y2 in 0..1}}
   *   usage     {pages?, bytes?, input_tokens?, output_tokens?} (only what the provider reports)
   *   model     the model the provider reports, else the requested model
   *   warnings  [text] non-fatal problems
   *   raw       the provider response as returned
   *
   * The request body holds the whole document in base64. It is never logged.
   */

  /*
   * Run OCR. Pass exactly one of p_document (with p_media_type) or p_url.
   * p_url is supported by Mistral only.
   *
   * Errors before any HTTP call:
   *   -20306  p_provider is null, unknown or has no OCR adapter (yet)
   *   -20508  the media type is null or not supported by the provider
   *   -20503  the document is empty, or an option has the wrong shape
   * -20302 (c_err_provider_response) is raised when the provider reports an error.
   *
   * p_options is passed on as provider options (see docs). Neutral keys:
   * pages, tables. The key extra_body (an object) is merged into the request
   * body; the keys model and document are reserved and always win.
   */
  function ocr (
    p_document   in blob
  , p_url        in varchar2
  , p_media_type in varchar2
  , p_provider   in uc_ai.provider_type
  , p_model      in uc_ai.model_type
  , p_options    in json_object_t
  , p_settings   in uc_ai_settings.t_settings
  ) return json_object_t;

end uc_ai_ocr;
/
