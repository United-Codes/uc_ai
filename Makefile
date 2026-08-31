# =============================================================================
#  UC AI — project commands. Run `make` to list them.
# =============================================================================

# --- Configuration -----------------------------------------------------------
# `?=` means "unless already set", so any of these can be overridden per call:
#   make test SUITE=test_uc_ai_anthropic.basic_recipe
#
# Never put a trailing `# comment` on these lines: make keeps the whitespace
# between the value and the `#` as part of the value, which silently passes a
# padded argument to sql/dblinter. Comments go above the assignment.

# Dev schema (SQLcl saved connection name, so no credentials live in here).
DB_CONN    ?= local-23ai-uc_ai
# Throwaway schema that the install/uninstall tests recreate.
TEST_CONN  ?= local-23ai-uc_testinstall_1
# What `make test` runs: a package, a package.test, or a suitepath.
SUITE      ?= test_uc_ai_toon
# What dbLinter analyses.
LINT_PATH  ?= src
# Baseline branch for `make lint-changed`.
REF_BRANCH ?= development
# Extra dbLinter flags. Empty by default: the committed dblinter.properties plus
# the DBLINTER_USER_NAME / DBLINTER_ACCESS_TOKEN environment variables are enough.
# If a shell does not have those exported, point at a properties file that has
# them:  make lint LINT_OPTS=--options=$$HOME/dbLinter/dblinter.properties
# Do not name this DBLINTER_something: make exports command-line variables into
# the recipe environment, and dbLinter reads every DBLINTER_* var as one of its
# own options, so it would choke on it before the check even starts.
LINT_OPTS ?=

# APEX app export/import. APP_ID picks the app to export; APP is the folder the
# APEXLANG export creates underneath APP_DIR - it is the app alias, lowercased.
APP_ID     ?= 100
APP_DIR    ?= applications
APP        ?= uc-ai-chat

TUT_APP_ID  ?= 777
TUT_APP_DIR ?= examples/sample-apps/tutorials
TUT_APP     ?= uc-ai-tutorials

# Every generated script is rebuilt from these.
SOURCES := $(shell find src -type f \( -name '*.pks' -o -name '*.pkb' -o -name '*.sql' \))
GENERATOR_DEPS := scripts/package_utils.sh

# --- Make behaviour ----------------------------------------------------------
# A bare `make` lists the commands instead of running the first one.
.DEFAULT_GOAL := help
# `docs`, `test` and `check` all collide with a real file or folder in this repo,
# so without this make would say "up to date" and silently do nothing.
.PHONY: help generate test test-free test-install test-uninstall lint lint-changed \
        docs docs-dev app-export app-import check-packages check
# Nothing here benefits from parallelism, and two targets sharing a schema is bad.
.NOTPARALLEL:

# --- Help --------------------------------------------------------------------

help: ## List the available commands
	@echo "UC AI project commands. Override variables like: make test SUITE=test_uc_ai_hook"
	@echo "Dev schema: $(DB_CONN)   Install-test schema: $(TEST_CONN)"
	@echo
	@grep -E '^[a-z][a-z.-]*:.*## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*## "} {printf "  \033[1;36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo

# --- Generated install scripts -----------------------------------------------
# These are real files with real inputs, so make only regenerates what is stale.

install_uc_ai.sql: $(SOURCES) $(GENERATOR_DEPS) scripts/generate_install_script.sh
	bash scripts/generate_install_script.sh

install_uc_ai_complete.sql: $(SOURCES) $(GENERATOR_DEPS) scripts/generate_install_script_complete.sh
	bash scripts/generate_install_script_complete.sh

upgrade_packages.sql: $(SOURCES) $(GENERATOR_DEPS) scripts/generate_upgrade_script.sh
	bash scripts/generate_upgrade_script.sh

uninstall.sql: $(SOURCES) $(GENERATOR_DEPS) scripts/generate_uninstall_script.sh
	bash scripts/generate_uninstall_script.sh

install_ptc_sandbox_complete.sql: $(SOURCES) $(GENERATOR_DEPS) scripts/generate_ptc_sandbox_script.sh scripts/install_ptc_sandbox.sql
	bash scripts/generate_ptc_sandbox_script.sh

# The recorded provider requests and responses, compiled into a package so the
# wire tests can compare against them. Regenerated when a sample changes.
SAMPLES := $(shell find test/samples -type f -name '*.json')

test/uc_ai_test_samples.pkb: $(SAMPLES) scripts/generate_test_samples.sh
	bash scripts/generate_test_samples.sh

generate: install_uc_ai.sql install_uc_ai_complete.sql upgrade_packages.sql uninstall.sql install_ptc_sandbox_complete.sql test/uc_ai_test_samples.pkb ## Regenerate every stale generated file (install scripts, test samples package)

# --- Tests -------------------------------------------------------------------

test-free: ## Run the 416 LLM-free tests (fast, no provider calls, no cost)
	sql -name $(DB_CONN) @scripts/run_tests_free.sql

test: ## Run one suite/package/test - make test SUITE=test_uc_ai_hook (may call a real LLM)
	sql -name $(DB_CONN) @scripts/run_tests.sql $(SUITE)

test-install: generate ## Generate the install scripts and install them into a fresh schema
	bash scripts/test_installs.sh

test-uninstall: ## Install, then run the generated uninstall.sql and list what is left
	bash scripts/test_uninstall_script.sh

# --- Linting -----------------------------------------------------------------

lint: ## Run dbLinter over the PL/SQL sources
	dblinter $(LINT_OPTS) check $(LINT_PATH)

lint-changed: ## Run dbLinter only on lines changed against the baseline branch
	dblinter $(LINT_OPTS) check --newCodeOnly=true --referenceBranch=$(REF_BRANCH) $(LINT_PATH)

# --- Documentation site ------------------------------------------------------

docs: ## Build the docs site (fails on broken internal links)
	cd docs && bun install && bun run build

docs-dev: ## Serve the docs site locally with hot reload
	cd docs && bun run dev

# --- APEX application --------------------------------------------------------

app-export: ## Export the APEX app as APEXLANG into the export folder
	printf 'apex export -applicationid %s -exptype APEXLANG -dir %s -exitwhendone\n' \
	  '$(APP_ID)' '$(APP_DIR)' | sql -name $(DB_CONN)

app-import: ## Import the exported app folder back into the database
	@test -d $(APP_DIR)/$(APP) || { echo "$(APP_DIR)/$(APP) not found - set APP=<folder>"; exit 1; }
	printf 'apex import -input %s\nexit\n' '$(CURDIR)/$(APP_DIR)/$(APP)' | sql -name $(DB_CONN)

tut-app-export:
	printf 'apex export -applicationid %s -exptype APEXLANG -dir %s  -overwrite-files -exitwhendone\n' \
	  '$(TUT_APP_ID)' '$(TUT_APP_DIR)' | sql -name $(DB_CONN)
	@bash scripts/relink_tut_plugin_scripts.sh $(TUT_APP_DIR)/$(TUT_APP)

tut-app-import:
	@test -d $(TUT_APP_DIR)/$(TUT_APP) || { echo "$(TUT_APP_DIR)/$(TUT_APP) not found - set APP=<folder>"; exit 1; }
	printf 'apex import -input %s\nexit\n' '$(CURDIR)/$(TUT_APP_DIR)/$(TUT_APP)' | sql -name $(DB_CONN)

# --- Audits ------------------------------------------------------------------

check-packages: ## Verify every package spec is registered in package_utils.sh
	@missing=0; \
	for f in src/packages/*.pks; do \
	  grep -q "$$(basename "$$f" .pks)" scripts/package_utils.sh || { echo "NOT REGISTERED: $$f"; missing=1; }; \
	done; \
	if [ $$missing -eq 0 ]; then echo "All $$(ls src/packages/*.pks | wc -l | tr -d ' ') package specs are registered."; \
	else echo "Unregistered packages are silently left out of every generated script."; exit 1; fi

check: check-packages lint test-free ## Registration audit + lint + the LLM-free tests
