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
   * p_url is supported by Mistral only; the other providers raise -20508.
   *
   * Errors before any HTTP call:
   *   -20306  p_provider is null, unknown or has no OCR support (the message lists mistral, oci, ollama)
   *   -20508  the media type is null or not supported by the provider
   *   -20503  the document is empty, or an option has the wrong shape
   *   -20502  OCI without uc_ai_oci.g_compartment_id, Ollama without p_model
   * -20302 (c_err_provider_response) is raised when the provider reports an error.
   * OCI raises it also when the response has an error and no page.
   *
   * p_options is passed on as provider options (see docs). Neutral keys:
   * pages, tables. The key extra_body (an object) is merged into the request
   * body; the keys model and document are reserved and always win.
   *
   * OCI Document Understanding: p_model is ignored. tables => true adds the
   * TABLE_EXTRACTION feature; the keys language, documentType and features are
   * passed on (a features array replaces the default; features that is not an
   * array raises -20503); pages (0-based) filters the result. The keys
   * compartmentId and document are reserved. The URL comes from
   * uc_ai_oci.g_region; uc_ai.g_base_url does not apply. Oracle documents a limit
   * for synchronous calls; UC AI checks only the size: a document of more than
   * 8 MB of raw bytes raises -20503. It does not check the page count.
   *
   * Ollama: a vision model reads one image over /api/chat. p_model is required
   * (-20502 when null); PDF and other types raise -20508, as PL/SQL cannot make an
   * image of a PDF page. Use an opaque image: Ollama flattens an alpha channel on
   * black without an error. The result has one page (index 0) with the text of the
   * model, no blocks and no dimensions; a Markdown code fence around the whole
   * answer is removed. usage has input_tokens and output_tokens. The prompt asks
   * for Markdown and for the single word UNREADABLE when the image has no text;
   * that reply gives empty markdown and a warning. An empty reply gives empty
   * markdown and a warning. message.thinking is ignored (it stays in raw).
   * Options: prompt (replaces the default prompt), append_unreadable_hint (false
   * leaves the UNREADABLE line out), system (system message), options, keep_alive
   * and think (passed on). pages accepts [0] only (another page raises -20508);
   * tables is accepted and ignored, the default prompt asks for tables.
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
