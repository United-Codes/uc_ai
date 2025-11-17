create or replace package uc_ai_toon authid current_user as

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
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
