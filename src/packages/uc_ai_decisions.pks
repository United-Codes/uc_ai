create or replace package uc_ai_decisions
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
   * EXPERIMENTAL. Provider dispatcher and shared logic for typed decisions.
   * Applications call uc_ai.decide; it builds the settings record and calls
   * decide() here. The provider API behind it is in beta, so the shape of the
   * result can still change. Each provider has a private adapter in the body that
   * turns the neutral call into the provider request and the provider response
   * into the neutral result. Providers: openai (Decisions API, POST /decisions) and
   * typesafe (TypeSafe jev, POST /systemone; text and png/jpeg images, no refusals) and
   * openrouter (OpenRouter Decisions, POST /alpha/decisions; text only, no refusals).
   *
   * One shared state (text and optional images) and several named questions. Each
   * question has a type and gets a typed answer with probabilities.
   *
   * Questions (json_object_t, keyed by question id; the order of the keys is the
   * order of the questions):
   *   id            ^[A-Za-z][A-Za-z0-9_]{0,63}$
   *   type          boolean | choice | score
   *   instructions  string, required
   *   criteria      choice:  object, option -> description (at least 2 options)
   *                 score:   array of level descriptions (at least 2 levels)
   *                          level 0 is the first element
   *                 boolean: optional object {"true": "...", "false": "..."}
   *
   * Neutral result (json_object_t):
   *   answers            {id: answer}
   *     boolean          {type, probability}
   *     choice           {type, choice, probabilities? {option: p}}
   *     score            {type, score, probabilities? {"0": p, "1": p, ...}}
   *     refused          {type: "refused"}  the provider refused this question
   *   A refused question has no choice, score or probability. The other questions
   *   in the same response are answered as usual, and the call does not raise,
   *   not even when every question is refused. Callers must check type before
   *   they read choice, score or probability.
   *   usage              {input_tokens?, output_tokens?, total_tokens?}
   *   model              the model the provider reports, else the requested model
   *   provider_metadata  {confidence? {id: n}, usage? (the provider usage object)}
   *                      confidence is a vendor statistic, not the probability of
   *                      the selected option
   *   warnings           [text] non-fatal problems
   *   raw                the provider response as returned
   *
   * Checks before any HTTP call (a failure costs no request):
   *   -20306  p_provider is null, unknown or has no decision support
   *   -20503  the questions, the state or an option are malformed: bad id, unknown
   *           type, no instructions, a choice with fewer than 2 options, a score
   *           with fewer than 2 levels, an empty state without files
   *   -20508  the provider cannot take it: more choices or levels than the
   *           provider allows (limits table in the body), an image media type the
   *           provider does not accept, any file for a provider that takes text
   *           only (openrouter)
   *
   * After the response:
   *   -20302  the provider reported an error (HTTP status 400 or more, or an error body)
   *   -20304  the answers do not match the questions: a missing, extra or
   *           duplicate answer, an answer without a name (also a refusal without
   *           a name), a wrong answer type, a choice that is not an option, a
   *           score outside the levels, a probability outside 0..1. A refused
   *           answer skips the type, option, score and probability checks, but
   *           still counts as the answer for its question.
   *   Distribution checks (probabilities do not sum to 1, a score that differs from
   *   the probability-weighted mean) add a text to warnings and do not raise. The
   *   tolerance is 1e-6 plus half a unit of the 2-decimal rounding (0.005) for
   *   each rounded value that goes into the sum or the mean.
   *
   * p_options: safety_identifier (OpenAI only; string, sent as it is) and extra_body
   * (object, merged into the request; the keys model, input (OpenAI) or state
   * (TypeSafe) and questions always win). Every other key is ignored and adds a
   * text to warnings.
   *
   * OpenRouter takes the same request and gives the same answers as TypeSafe, so
   * everything below for TypeSafe also holds for OpenRouter. Its alpha endpoint is
   * <base_url>/alpha/decisions with the default base URL https://openrouter.ai/api.
   *
   * TypeSafe images: each file goes into the assets object of the request under a
   * generated reference, and the reference is written at the end of the state (one
   * line per image). The request carries the header TypeSafe-Danger-Zone-Images.
   * The pixel limits (256 to 1568 px per side, 16 MiB) are left to jev.
   *
   * TypeSafe: the boolean question is a noul question and its criteria are sent
   * as they are (true and false texts); jev answers every question, so the answer
   * type refused does not occur. confidence is in provider_metadata for choice
   * and score answers. An error body (detail) raises -20302 with the vendor
   * message and the field path, never the echoed input.
   *
   * The request body can hold base64 images and user text. It is never logged.
   */
  function decide (
    p_state     in clob
  , p_questions in json_object_t
  , p_provider  in uc_ai.provider_type
  , p_model     in uc_ai.model_type
  , p_files     in json_array_t
  , p_options   in json_object_t
  , p_settings  in uc_ai_settings.t_settings
  ) return json_object_t;

end uc_ai_decisions;
/
