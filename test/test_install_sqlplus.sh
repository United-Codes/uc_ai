#!/bin/bash

# make sure the script runs from the root folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# clear test install schema
local-23ai.sh clear-schema uc_testinstall_1 -y

# read "DB_PW" from ./test/.env
DB_PW=$(grep DB_PW ./test/.env | cut -d '=' -f2)

if [ -z "$DB_PW" ]; then
  echo "DB_PW is not set in ./test/.env file"
  exit 1
fi

# generate install script
./scripts/generate_install_script_complete.sh

# run install script
sqlplus uc_testinstall_1/"$DB_PW"@localhost/FREEPDB1 <<EOF

@install_uc_ai_complete_with_logger.sql

SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET TRIMSPOOL ON
SET TERMOUT ON

prompt ""
prompt ""
prompt ""
prompt "++++++++++++++++++++++++++++"
prompt "Invalid objects"
prompt "++++++++++++++++++++++++++++"

SELECT OBJECT_NAME FROM user_objects WHERE status = 'INVALID';

exit
EOF
