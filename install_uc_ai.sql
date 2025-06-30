-- UC AI Framework Installation Script
-- Run this script to install the complete framework with OpenAI and Anthropic support

PROMPT Installing UC AI Framework Tables...
@@src/tables/install.sql



PROMPT Installing PL/SQL objects
-- first: has types
@@src/packages/uc_ai.pks

-- second: other depend on it
@@src/dependencies/key_function.sql

@@src/packages/uc_ai_tools_api.pks
@@src/packages/uc_ai_anthropic.pks
@@src/packages/uc_ai_openai.pks
@@src/packages/uc_ai_google.pks


@@src/packages/uc_ai_tools_api.pkb
@@src/packages/uc_ai_anthropic.pkb
@@src/packages/uc_ai_openai.pkb
@@src/packages/uc_ai_google.pkb
@@src/packages/uc_ai.pkb

PROMPT Installation Complete!
