-- Test OCI Authentication with corrected implementation
-- This example shows the fixes based on Oracle's Go implementation

set serveroutput on

declare
  l_credentials fck_oci_auth.t_oci_credentials;
  l_response clob;
  l_private_key clob;
  l_body json_object_t;
begin
--   -- Private key - remove the BEGIN/END lines, keep line breaks
--   l_private_key := 'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDKilu5hjsbLjED
-- hiF3Ri09l+5yakJ0SUmlzJlKLj7I9QcKiJnwsjeMWK21hg5+Jqd1D5z7UHNOcIF6
-- v92WdNCLRppj7uPjHBxUuBh8gLjHxsWK7VCTU9xHLpdTEFe5Ygy2WCF+Ssai5Pzh
-- 9H5aYPjM9s1zTGWOYzsF5E9l3s3Gp/EjYTf2w3D11/eWdYaDl5Xo7x+Pta9pgL+6
-- qbWJD29QzlwZ386cHjxswKvBLSwLjOCE1uaHKVPg2MdawpbFrMQ32T27uczGUBwu
-- fBvH/lFWaGYTPu+E82zJDuy9aQyndgoZXtrw5CPjFTgd2rqry9xX/p7bWg38QWum
-- A2gGbVUjAgMBAAECggEAECwmENVQCOaSUVa3e1+mIyHrj0U+0yw67js9DjhNGRy/
-- mC66JAcG+nTmQfVXWOlbO7Soc0TEQEIphJSna+kd8dEMaOhdV/gZpwYgJmjc2E7d
-- 3S7/3RO4JhLpUF+gsZPLsg+tdPkhjUY9jwlHwY22sB8Q3qD+BvWTc+/8CwVUZwVD
-- lDDyq9G8TwEs0NMU55Hme+tqVoDBbZL2eShC6BIHmJyMdDZATwge8HoSavAIvlpW
-- VtMQLK4BZCGPsKB4VCmQeba3sGbcbgqc3lsRJtDi5hjlOYPU1YgW3c1ccmYrVUtG
-- L7oQZEPlqC1AaBsH6Hex9hMMZbsR7hZyZ9s/ZTAKSQKBgQDnxWZKrWZ/eK1TF2Mu
-- ySewNu8usrQtA+hVDvFTUrgK3PGj9MbT1U1C1wScVwbsrk82unJDxyU4riPMF3Q8
-- t4lbqFW4nTPhalPfbxukZcc+UXCiaMNkDIsOTrbiWNKWhZrHqduMImWu7uKYl82u
-- 7BqyQhlrsM72JOL+aMds+YYaHQKBgQDftrIj5J3BqFbsmt0IZYVe4TZ5c+ulNkUz
-- bxJxXICZf/A8PdEXFnAEK97ZA8k3eBgbhbz8Yni6kuL5sDHh4EGcKG3gpK9D6Owy
-- IiZsCjSkaVA+08TC7Z/fx5P0rxy2Pn57rBzpbXiKkrQ7wfT592H9h8gFMR/s4awv
-- lbL90UwIPwKBgADPUsUuB+6oGErzCPiv4UCfYISUQUbq/ZPWgoddAaGgFgQRpeQ1
-- mZiDMdPuBesrzMEPM7kC6CFjkmJzLofLyGIWm34SpozCF1rvg3Q2mtSf6jnXDd+6
-- n33ETqVJ1CqMevb5o/fAYwSSdx47YY+b6Zf33SjgLEj15gknipLZ6FsNAoGBAIue
-- 9FMeba7dp1KH3IdPBQwQNvVZ+ank0w+ktLf3aXNju8V9Ny/XmxWfY7fBeyWZWEJl
-- F2vU8VBQOERpSNiWI5yYRus7HP+fMTqgwaYQQIaUC7cKZ/TYZT0+zAKb/6lmG36I
-- DotI/UBPCxl4lbIkSQ34XkePP0OSHOqd3VY39+H1AoGBALtCu+sa87aVLpyCjd6b
-- UBhIZ4f05ud28KnFbjK4bNppt0n8bCloe+/AFMgpcnJPrweySGtVKY3KOBcYEfyy
-- zcPu3EC6rrdpSBKiArYGhQM3EpPlAvUWfvqUU2sAuNQ5iML2xM8Nti/Ho0xWf8az
-- 9dcwL+evVYtCLJfNuCFX/kvp';

--   l_credentials := fck_oci_auth.create_credentials(
--     p_tenancy_ocid    => 'ocid1.tenancy.oc1..aaaaaaaavv5zrvrrt437zlhtbjvkzqhjmuwx365cuxg22p7hsbpwtaecuhcq',
--     p_user_ocid       => 'ocid1.user.oc1..aaaaaaaa4yk7nmyehreqkinteuwivvpflw32zdgmpudpiz5uzo6qhtdxg3uq',
--     p_key_fingerprint => '40:a4:eb:0d:34:cb:cf:27:03:09:44:19:fb:3a:7a:f3',
--     p_private_key     => l_private_key,
--     p_region          => 'eu-frankfurt-1'
--   );

--   l_body := json_object_t(q'!{
--   "compartmentId": "ocid1.tenancy.oc1..aaaaaaaavv5zrvrrt437zlhtbjvkzqhjmuwx365cuxg22p7hsbpwtaecuhcq",
--   "servingMode": {
--     "modelId": "cohere.command-a-03-2025",
--     "servingType": "ON_DEMAND"
--   },
--   "chatRequest": {
--     "maxTokens": 600,
--     "temperature": 1,
--     "frequencyPenalty": 0,
--     "presencePenalty": 0,
--     "topP": 0.75,
--     "topK": 0,
--     "isStream": false,
--     "chatHistory": [
    
--     ],
--     "message": "Help. How can I query dual",
--     "apiFormat": "COHERE"
--   }
-- }
-- !');

l_body := json_object_t(q'!{
  "compartmentId": "ocid1.tenancy.oc1..aaaaaaaavv5zrvrrt437zlhtbjvkzqhjmuwx365cuxg22p7hsbpwtaecuhcq",
  "servingMode": {
    "modelId": "meta.llama-3.3-70b-instruct",
    "servingType": "ON_DEMAND"
  },
  "chatRequest": {
    "messages": [
      {
        "role": "USER",
        "content": [
          {
            "type": "TEXT",
            "text": "who are you"
          }
        ]
      }
    ],
    "apiFormat": "GENERIC",
    "maxTokens": 600,
    "isStream": false,
    "numGenerations": 1,
    "frequencyPenalty": 0,
    "presencePenalty": 0,
    "temperature": 1,
    "topP": 1.0,
    "topK": 1
      }
}
!');

-- l_body := json_object_t(q'!{
--   "compartmentId": "ocid1.tenancy.oc1..aaaaaaaavv5zrvrrt437zlhtbjvkzqhjmuwx365cuxg22p7hsbpwtaecuhcq",
--  "servingMode": {
--     "modelId": "cohere.command-a-03-2025",
--     "servingType": "ON_DEMAND"
--   },
--   "chatRequest": {
--     "message": "Tell me something about the company's relational database.",
--     "maxTokens": 600,
--     "isStream": false,
--     "apiFormat": "COHERE",
--     "documents": [
--       {
--         "title": "Oracle",
--         "snippet": "Oracle database services and products offer customers cost-optimized and high-performance versions of Oracle Database, the world's leading converged, multi-model database management system, as well as in-memory, NoSQL and MySQL databases. Oracle Autonomous Database, available on premises via Oracle Cloud@Customer or in the Oracle Cloud Infrastructure, enables customers to simplify relational database environments and reduce management workloads.",
--         "website": "https://www.oracle.com/database"
--       }
--     ],
--     "chatHistory": [
--       {
--         "role": "USER",
--         "message": "Tell me something about Oracle."
--       },
--       {
--         "role": "CHATBOT",
--         "message": "Oracle is one of the largest vendors in the enterprise IT market and the shorthand name of its flagship product. The database software sits at the center of many corporate IT"
--       }
--     ]
--   }
-- }
-- !');
  
  -- Test the GET request to identity service
  -- l_response := fck_oci_auth.make_oci_request(
  --   p_credentials => l_credentials,
  --   p_method      => 'GET',
  --   p_url         => 'https://inference.generativeai.eu-frankfurt-1.oci.oraclecloud.com',
  --   p_body        => l_body
  -- );

  apex_web_service.clear_request_headers;
  apex_web_service.set_request_headers('Content-Type', 'application/json; charset=utf-8');    

  --apex_web_service.set_request_headers('Authorization', 'Bearer eKjyjTw6)LkC5f:Z.ML)');
  -- 5hz2oO)NCa>j)cH6+6pa

  l_response := apex_web_service.make_rest_request(
    p_url         => 'https://inference.generativeai.eu-frankfurt-1.oci.oraclecloud.com/20231130/actions/chat',
    p_http_method => 'POST',
    p_body        => l_body.to_clob
    ,p_credential_static_id => 'TEST3'
  );

  sys.dbms_output.put_line('Response: ' || substr(l_response, 1, 2000));
  sys.dbms_output.put_line('Status Code: ' || apex_web_service.g_status_code);
  sys.dbms_output.put_line('Status Reason: ' || apex_web_service.g_reason_phrase);
  
exception
  when others then
    sys.dbms_output.put_line('Error: ' || sqlerrm);
    sys.dbms_output.put_line('Backtrace: ' || sys.dbms_utility.format_error_backtrace);
end;
/
