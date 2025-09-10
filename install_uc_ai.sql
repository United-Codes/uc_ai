-- UC AI Framework Installation Script
-- Run this script to install the complete framework with OpenAI and Anthropic support

PROMPT ===================================================
PROMPT UC AI Framework Installation Starting...
PROMPT ===================================================

PROMPT Installing UC AI Framework Tables...
PROMPT This creates the core database tables for message storage and configuration
@@src/tables/install.sql


PROMPT Installing database triggers...
PROMPT This sets up automatic data validation and logging triggers
@@src/triggers/triggers.sql

PROMPT Installing PL/SQL packages...
PROMPT This includes all AI provider packages and utility functions

PROMPT Installing package specifications (headers)...
PROMPT - Installing core types and constants...
@@src/packages/uc_ai.pks

PROMPT - Installing utility functions...
@@src/dependencies/key_function.sql

PROMPT - Installing API package specifications...
@@src/packages/uc_ai_tools_api.pks
@@src/packages/uc_ai_message_api.pks
@@src/packages/uc_ai_structured_output.pks

PROMPT - Installing AI provider package specifications...
@@src/packages/uc_ai_anthropic.pks
@@src/packages/uc_ai_google.pks
@@src/packages/uc_ai_oci.pks
@@src/packages/uc_ai_ollama.pks
@@src/packages/uc_ai_openai.pks

PROMPT Installing package bodies (implementations)...
PROMPT - Installing API package bodies...
@@src/packages/uc_ai_tools_api.pkb
@@src/packages/uc_ai_message_api.pkb
@@src/packages/uc_ai_structured_output.pkb
PROMPT - Installing AI provider package bodies...
@@src/packages/uc_ai_anthropic.pkb
@@src/packages/uc_ai_google.pkb
@@src/packages/uc_ai_oci.pkb
@@src/packages/uc_ai_ollama.pkb
@@src/packages/uc_ai_openai.pkb
PROMPT - Installing core UC AI package body...
@@src/packages/uc_ai.pkb

PROMPT ===================================================
PROMPT UC AI installation complete!
PROMPT Refer to the documentation for usage instructions: https://www.united-codes.com/products/uc-ai/docs/
PROMPT ===================================================
