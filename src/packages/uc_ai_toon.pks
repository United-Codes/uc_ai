create or replace package uc_ai_toon authid current_user as

  /**
   * UC AI TOON - TOON Format Encoder
   * 
   * This package provides utilities to convert Oracle JSON objects and arrays
   * into TOON format - a compact, LLM-optimized data serialization format.
   * 
   * TOON Features:
   * - Compact array syntax: [length]: elements
   * - Key-value pairs: key: value
   * - Indentation-based nesting instead of braces
   * - Columnar format for homogeneous object arrays
   * - Full Unicode support
   * - Type preservation (numbers, booleans, strings, null)
   * 
   * @author  Philipp Hartenfeller
   * @created November 2025
   * @version 1.0
   */

  /**
   * Convert a JSON_OBJECT_T to TOON format
   * 
   * @param p_json_object The JSON object to convert
   * @return CLOB containing the TOON representation
   */
  function to_toon(p_json_object in json_object_t) return clob;

  /**
   * Convert a JSON_ARRAY_T to TOON format
   * 
   * @param p_json_array The JSON array to convert
   * @return CLOB containing the TOON representation
   */
  function to_toon(p_json_array in json_array_t) return clob;

  /**
   * Convert a JSON string to TOON format
   * 
   * @param p_json_string The JSON string to convert
   * @return CLOB containing the TOON representation
   */
  function to_toon(p_json_string in clob) return clob;

end uc_ai_toon;
/
