create or replace package test_uc_ai_ocr_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(OCR wire-level request and response tests (LLM-free))
  --%suitepath(uc_ai)

  -- Every test runs uc_ai.ocr or uc_ai.ocr_text end to end and stops one step
  -- short of the network: uc_ai_http hands the request to uc_ai_test_http_mock,
  -- which records it and answers with a queued body. The Mistral responses in
  -- test/samples/mistral are real ones, recorded from the API. The error bodies
  -- for 429 and 502 and the multi-page response are written out here, because
  -- they need a state nobody can ask the API for.
  --
  -- Except for the one test that names it, no test reads uc_ai_get_key: every
  -- call names an APEX web credential.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- request shape -------------------------------------------------------------
  --%test(Mistral: the request goes to /ocr with the default OCR model)
  procedure mistral_url_and_model;

  --%test(Mistral: a PDF is sent as document_url with a data URL that holds the base64 of the blob)
  procedure mistral_pdf_document_url;

  --%test(Mistral: PNG and WebP are sent as image_url)
  procedure mistral_image_url;

  --%test(A media type with case and parameters is normalized in the data URL)
  procedure media_type_is_normalized;

  --%test(image/jpg is accepted as image/jpeg)
  procedure image_jpg_alias;

  --%test(Options are passed on as they are, including unknown keys and nested values)
  procedure options_pass_through;

  --%test(A very large option value reaches the request unchanged)
  procedure huge_option_value;

  --%test(tables => true sets table_format markdown, an explicit table_format wins, false sets nothing)
  procedure tables_sets_table_format;

  --%test(extra_body is merged, overrides options and cannot replace model or document)
  procedure extra_body_merge;

  --%test(extra_body that is not an object raises before any request)
  procedure extra_body_not_object;

  --%test(The model parameter replaces the default model)
  procedure model_override;

  -- authentication -------------------------------------------------------------
  --%test(With a web credential the request carries the credential and no Authorization header)
  procedure credential_replaces_auth_header;

  --%test(Without a web credential the request carries a Bearer Authorization header)
  procedure bearer_header_without_credential;

  --%test(Extra headers are sent with the OCR request)
  procedure extra_headers_are_sent;

  -- url overload ---------------------------------------------------------------
  --%test(The URL overload builds a document_url body for a PDF URL)
  procedure url_overload_document_url;

  --%test(The URL overload builds an image_url body for image URLs, with or without a query string)
  procedure url_overload_image_url;

  --%test(A data URL with an unsupported media type raises before any request)
  procedure data_url_unsupported_type;

  --%test(A document and a URL together raise before any request)
  procedure document_and_url_conflict;

  -- response mapping -------------------------------------------------------------
  --%test(The neutral result has markdown, pages, usage, model, warnings and raw)
  procedure result_shape;

  --%test(Pixel boxes are mapped to 0..1 by the page dimensions)
  procedure box_is_normalized;

  --%test(A table link in the markdown is replaced by the table content)
  procedure table_link_is_replaced;

  --%test(Pages are joined with a blank line and empty pages are left out)
  procedure pages_are_joined;

  --%test(usage_info that is null or missing leaves usage empty)
  procedure usage_info_null_is_guarded;

  --%test(A page without text gives empty markdown and no error)
  procedure empty_page_is_not_an_error;

  --%test(Page confidence is read from confidence_scores when the provider sends it)
  procedure page_confidence;

  --%test(ocr_text returns the markdown of ocr)
  procedure ocr_text_equals_markdown;

  -- errors -------------------------------------------------------------------------
  --%test(A 429 flat error body raises -20302 with the provider message)
  procedure rate_limit_error;

  --%test(A recorded 400 invalid model error raises -20302 with the provider message)
  procedure invalid_model_error;

  --%test(A 502 HTML body raises -20302)
  procedure html_error_body;

  --%test(A 200 response without pages raises -20302)
  procedure response_without_pages;

  --%test(A 200 response in the flat error shape raises -20302)
  procedure error_object_in_200;

  --%test(An unsupported media type raises -20508 and no request is sent)
  procedure unsupported_media_type;

  --%test(A null media type raises -20508 and no request is sent)
  procedure null_media_type;

  --%test(A null or empty document raises -20503 and no request is sent)
  procedure empty_document;

  --%test(A null or unknown provider raises -20306 and no request is sent)
  procedure null_and_unknown_provider;

  --%test(OCI and Ollama raise -20306 not supported yet and send no request)
  procedure providers_without_adapter;

  -- logging ------------------------------------------------------------------------
  --%test(The request body and the base64 never appear in the log)
  procedure body_is_not_logged;

end test_uc_ai_ocr_wire;
/
