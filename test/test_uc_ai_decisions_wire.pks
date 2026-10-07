create or replace package test_uc_ai_decisions_wire as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Decisions wire-level request and response tests (LLM-free))
  --%suitepath(uc_ai)

  -- Every test runs uc_ai.decide end to end and stops one step short of the
  -- network: uc_ai_http hands the request to uc_ai_test_http_mock, which records
  -- it and answers with a queued body. The OpenAI responses in
  -- test/samples/openai/decisions are real ones, recorded from the Decisions API.
  -- The answers that need a state nobody can ask the API for (a distribution that
  -- does not add up, a wrong answer type, a 429) are written out here.
  --
  -- No test reads uc_ai_get_key: every call names an APEX web credential.

  --%beforeall
  procedure register_mock;

  --%afterall
  procedure unregister_mock;

  --%beforeeach
  procedure reset_state;

  -- request shape -------------------------------------------------------------
  --%test(URL is base/decisions, the default model is gpt-6-luna and the credential is named)
  procedure url_headers_and_default_model;

  --%test(base_url replaces the host and a trailing slash does not double)
  procedure base_url_replaces_host;

  --%test(All three question types become predicate, choice and score questions)
  procedure question_array_shapes;

  --%test(The questions are sent in the order of the question ids)
  procedure question_order_follows_keys;

  --%test(A choice option or level without a description gets no description key)
  procedure optional_descriptions_omitted;

  --%test(Boolean criteria are folded into the predicate instructions)
  procedure predicate_criteria_folded;

  --%test(A text-only call sends the state as a plain string)
  procedure text_state_is_plain_string;

  --%test(Texts longer than 32k reach the request unchanged)
  procedure long_texts_reach_the_request;

  --%test(An image makes input a message array with a data URL)
  procedure image_becomes_message_array;

  --%test(An image without state sends no input_text part)
  procedure image_only_has_no_text_part;

  --%test(Two images, a media type with case and parameters and base64 with line breaks)
  procedure several_images_and_media_types;

  --%test(safety_identifier is sent and extra_body is merged but cannot replace model, input or questions)
  procedure safety_identifier_and_extra_body;

  --%test(An option the provider does not know adds a warning and is not sent)
  procedure unknown_option_warns;

  --%test(A question key the model does not know adds a warning)
  procedure unknown_question_key_warns;

  --%test(A 64 character id, an option with a dot and a 255 option choice are sent as they are)
  procedure edge_ids_and_option_names;

  --%test(A score question with 10 levels works)
  procedure ten_levels_work;

  -- response mapping ------------------------------------------------------------
  --%test(The recorded triage response becomes the neutral result)
  procedure triage_result_is_neutral;

  --%test(The wire name predicate never appears in the neutral result)
  procedure predicate_name_never_in_result;

  --%test(Choice probabilities become an object keyed by option)
  procedure choice_probabilities_object;

  --%test(Score probabilities become an object keyed by the level index)
  procedure score_probabilities_keyed_by_index;

  --%test(confidence lands in provider_metadata and boolean answers have none)
  procedure confidence_in_provider_metadata;

  --%test(usage is mapped and the provider usage object is kept in provider_metadata)
  procedure usage_is_mapped;

  --%test(Model and raw come from the response)
  procedure model_and_raw;

  --%test(Recorded responses with images, 2 levels, 10 levels, 255 options and a score map without warnings)
  procedure recorded_samples_map;

  --%test(An answer without probabilities maps without them and without a warning)
  procedure missing_probabilities_are_fine;

  -- refusal ---------------------------------------------------------------------
  --%test(A refused question gets {type: refused} and the sibling answer is kept)
  procedure refusal_keeps_sibling_answer;

  --%test(A refusal next to a valid answer does not raise and gives no warning)
  procedure refusal_among_valid_answers;

  --%test(When every question is refused the call still succeeds)
  procedure all_questions_refused;

  --%test(A refusal between answers keeps the order, the probabilities and the confidence of the others)
  procedure mixed_refusal_mapping;

  --%test(A refusal counts as the answer of its question: missing, extra and duplicate checks still apply)
  procedure refusal_still_counts_as_answer;

  --%test(A refusal without a name raises -20304)
  procedure refusal_without_name;

  --%test(raw keeps the refusal entry as the provider sent it)
  procedure refusal_raw_is_kept;

  -- provider errors ---------------------------------------------------------------
  --%test(404 model_not_found raises -20302 with the provider message)
  procedure error_unknown_model;

  --%test(400 raises -20302 with message and param)
  procedure error_400_with_param;

  --%test(429 raises -20302)
  procedure error_429;

  --%test(A 502 with an HTML body raises -20302)
  procedure error_502_html;

  --%test(A 200 with an error body raises -20302)
  procedure error_body_on_200;

  -- answers that do not match the questions ----------------------------------------
  --%test(A question without an answer raises -20304)
  procedure answer_missing;

  --%test(An answer for an unknown question raises -20304)
  procedure answer_extra;

  --%test(Two answers for one question raise -20304)
  procedure answer_duplicate;

  --%test(An answer of the wrong type raises -20304)
  procedure answer_wrong_type;

  --%test(A choice that is not an option raises -20304)
  procedure choice_not_an_option;

  --%test(A score outside the levels raises -20304)
  procedure score_out_of_range;

  --%test(A probability outside 0 to 1 raises -20304)
  procedure probability_out_of_range;

  --%test(A probability entry for an unknown option or level raises -20304)
  procedure probability_unknown_entry;

  --%test(A response without an answers array or with a bad answer raises -20304)
  procedure answers_bad_shape;

  -- distribution checks -----------------------------------------------------------------
  --%test(Probabilities that do not sum to 1 give a warning and no error)
  procedure sum_not_one_warns;

  --%test(A sum off by the 2-decimal rounding gives no warning)
  procedure sum_rounding_tolerated;

  --%test(A score that differs from the weighted mean gives a warning and no error)
  procedure mean_mismatch_warns;

  --%test(A score off by the 2-decimal rounding gives no warning)
  procedure mean_rounding_tolerated;

  -- logging ---------------------------------------------------------------------------------
  --%test(The request body, the state and the images are not logged)
  procedure body_is_not_logged;

end test_uc_ai_decisions_wire;
/
