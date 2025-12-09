set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

./scripts/generate_uninstall_script.sh
local-23ai.sh test-script-install ./install_uc_ai_complete_with_logger.sql -y

sql -name local-23ai-uc_testinstall_1 << EOF
@uninstall.sql 

SELECT object_type, count(object_name)
from user_objects
group by object_type;

exit;
EOF
