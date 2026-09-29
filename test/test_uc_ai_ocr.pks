create or replace package test_uc_ai_ocr as

  --%suite(OCR tests: live Mistral and OCI calls and provider-neutral checks)
  --%suitepath(uc_ai)

  -- The Mistral tests call the Mistral OCR API with the key of uc_ai_get_key and
  -- cost a few pages of OCR. The OCI tests call OCI Document Understanding with
  -- the web credential OCI_KEY in region eu-frankfurt-1 and the compartment of
  -- get_oci_compratment_id. The wire tests in test_uc_ai_ocr_wire cover the request
  -- and response shapes without a network.

  --%beforeeach
  procedure reset_state;

  -- Mistral, live ----------------------------------------------------------------
  --%test(Mistral: a PDF gives markdown with the table, usage, one page and boxes inside the page)
  procedure mistral_pdf;

  --%test(Mistral: a PDF media type with parameters and upper case works)
  procedure mistral_pdf_media_type_params;

  --%test(Mistral: PNG returns a page and no error)
  procedure mistral_png;

  --%test(Mistral: a WebP returns one page and no error)
  procedure mistral_webp;

  --%test(Mistral: the pages option limits the pages that are processed)
  procedure mistral_pages_option;

  --%test(Mistral: the tables option keeps the table in the markdown and the raw response lists it)
  procedure mistral_tables_option;

  --%test(Mistral: confidence_scores_granularity page gives a page confidence between 0 and 1)
  procedure mistral_confidence_option;

  --%test(Mistral: an option Mistral knows but UC AI does not wrap reaches the API)
  procedure mistral_passthrough_option;

  --%test(Mistral: the second OCR model constant works)
  procedure mistral_model_4_1;

  --%test(Mistral: a bad model name raises -20302 with the provider message)
  procedure mistral_bad_model;

  --%test(Mistral: a public PDF URL is read)
  procedure mistral_url_overload;

  --%test(ocr_text returns the text of the PDF)
  procedure mistral_ocr_text;

  -- OCI Document Understanding, live -----------------------------------------------
  --%test(OCI: a PDF gives markdown with the names, one page, usage.pages 1 and boxes inside the page)
  procedure oci_pdf;

  --%test(OCI: the tables option gives a Markdown table row)
  procedure oci_pdf_tables;

  --%test(OCI: an image without text returns a warning and does not raise)
  procedure oci_png_no_text;

  --%test(OCI: a WebP raises -20508 before the call)
  procedure oci_webp_raises;

  --%test(OCI: the pages option filters the result)
  procedure oci_pages_option;

  --%test(OCI: ocr_text returns the text of the PDF)
  procedure oci_ocr_text;

  -- cross provider ----------------------------------------------------------------
  --%test(Mistral and OCI both read the names of the PDF)
  procedure cross_provider_pdf;

  -- neutral, no network --------------------------------------------------------------
  --%test(A media type that Mistral does not accept raises -20508 before the call)
  procedure unsupported_media_type;

  --%test(A null provider raises -20306)
  procedure null_provider;

end test_uc_ai_ocr;
/
