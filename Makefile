.DEFAULT_GOAL = help

ROOT_PATH := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
NODE_ENV ?= development
TARGET_ENV ?= development
TEST_OPTIONS ?= ""
DEBUG_MODE ?= ""

.SILENT: print_env
.PHONY: print_env
print_env:
	@echo "\033[93mNODE_ENV = $(NODE_ENV)\033[0m"
	@echo "\033[93mTARGET_ENV = $(TARGET_ENV)\033[0m"
	@echo "\033[93mDEBUG_MODE = $(DEBUG_MODE)\033[0m"

.PHONY: help
help: ## Prints this prompt.
	@echo "\033[1;31mplatform2-crosstabs Makefile\033[0m\n"
	@echo "Usage: make [target]\n"
	@echo "Available targets:\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: clean
clean: ## Cleans every asset built by Elm, TS, yarn or another stuff.
	@echo "\033[36mCleaning...\033[0m"
	rm -rf ./dist
	rm -rf ./elm-stuff
	rm -rf ./node_modules
	rm -rf ./build
	rm -rf ./.coverage

.PHONY: install
install: ## Installs every dependency needed to build the project. Expects `yarn` to be installed globally.
	@echo "\033[36mInstalling dependencies...\033[0m"
	yarn install

.PHONY: lint
lint: ## Lints the project with elm-review, eslint and stylelint.
	@echo "\033[36mReviewing project...\033[0m"
	npx elm-review src/
	npx stylelint 'src/**/*.scss'

.PHONY: lint_fix
lint_fix: ## Fixes fixable linting errors.
	@echo "\033[36mFixing project...\033[0m"
	npx elm-review src/ --fix-all
	npx stylelint 'src/**/*.scss' --fix

.PHONY: lint_watch
lint_watch: ## Lints the project with elm-review, eslint and stylelint in watch mode.
	@echo "\033[36mReviewing project...\033[0m"
	npx elm-review src/ --watch

.PHONY: format
format: ## Applies formatting to the whole project.
	@echo "\033[36mFormatting project...\033[0m"
	npx prettier -w .

.SILENT: format_validate
.PHONY: format_validate
format_validate: ## Validates formatting of the whole project.
	@echo "\033[36mValidating project formatting...\033[0m"
	npx prettier -c .

.PHONY: test_coverage
test_coverage: ## Tests the coverage of the project codebase.
	@echo "\033[36mTesting coverage...\033[0m"
	cd src/crosstab-builder/XB2 && npx elm-coverage --open && cd -

.PHONY: test
test: ## Runs the tests.
	@echo "\033[36mTesting...\033[0m"
	cd src/crosstab-builder/XB2 && TARGET_ENV=test && find . -name '*.elm' | grep "^./tests" | xargs npx elm-test-rs && cd -

.PHONY: test_watch
test_watch: ## Runs the tests in watch mode.
	@echo "\033[36mTesting in watch mode...\033[0m"
	cd src/crosstab-builder/XB2 && TARGET_ENV=test && find . -name '*.elm' | grep "^./tests" | xargs npx elm-test-rs --watch && cd -

# For start we are expecting `yarn` is installed globally

.PHONY: all
all: yarn.lock

dev_env:
	@echo " - setup DEV env"
	$(eval include dev.env)
	$(eval export)

.PHONY: no_watch_mode
no_watch_mode:
	@echo " - no watch mode build"
	$(eval WATCH_MODE=false)

yarn.lock: node_modules package.json
	$(MAKE clean)
	yarn install --production=false

node_modules:
	mkdir -p $@

.PHONY: clean_all
clean_all: clean
	rm -fr node_modules

.PHONY: check_unused_scss_files
check_unused_scss_files:
	@echo "Check unused SCSS files"
	@./bin/check_unused_scss_files.sh

# Tests

.SILENT: test_xb2
.PHONY: test_xb2
test_xb2:
	echo "Run crosstab-builder 2.0 tests"
	cd src/crosstab-builder/XB2 && TARGET_ENV=test && find . -name '*.elm' | grep "^./tests" | xargs npx elm-test-rs $(TEST_OPTIONS) && cd -

.SILENT: test_xb
.PHONY: test_xb
test_xb: test_xb2

# All tests running

.PHONY: test
test: override TEST_OPTIONS = ""
test: test_xb

# Coverage

.SILENT: cover_share
.PHONY: cover_share
cover_share:
	echo "Checking coverage of _share"
	cd src/_share && elm-coverage --open && cd -

.SILENT: cover_xb2
.PHONY: cover_xb2
cover_xb2:
	echo "Checking coverage of crosstab-builder 2.0"
	cd src/crosstab-builder/XB2 && elm-coverage --open && cd -

.SILENT: cover_xb
.PHONY: cover_xb
cover_xb: cover_xb2

# All coverage check running

.PHONY: cover
cover: override TEST_OPTIONS = ""
cover: cover_xb

# Build end development

PORT ?= 3900

.PHONY: start
start:
	npx webpack serve --hot --port 3000 --host 0.0.0.0

.PHONY: p2_serve_build_files_server
p2_serve_build_files_server:
	mkdir -p build && cd build && npx http-server -p $(PORT) --cors -c-1 &

.PHONY: p2_serve_build_files_server_no_background
p2_serve_build_files_server_no_background:
	mkdir -p build && cd build && npx http-server -p $(PORT) --cors -c-1

.PHONY: start_crosstabs_for_P2
start_crosstabs_for_P2: dev_env p2_serve_build_files_server build_xb2

.PHONY: start_for_P2
start_for_P2: dev_env no_watch_mode build_tv2 build_xb2 p2_serve_build_files_server_no_background

.PHONY: build
build: print_env
build: ## Builds the project in watch mode.
	@echo "\033[36mBuilding project...\033[0m"
	npx webpack --progress --config src/crosstab-builder/XB2/webpack.config.js

.PHONY: build_xb2
build_xb2:
	npx webpack --progress --config src/crosstab-builder/XB2/webpack.config.js

.PHONY: build_for_p20
build_for_p20: build_xb2