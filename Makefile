.DEFAULT_GOAL = help

NODE_ENV ?= development
TARGET_ENV ?= development
DEBUG_MODE ?= false

# These are the only posible values for ports. Other ports have conflicts with the API.
BUILD_SERVE_PORT = 3900
KERNEL_PORT = 4200

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

.PHONY: serve_build
serve_build: ## Serves the build/ folder in the background.
	@echo "\033[36mServing build folder...\033[0m"
	mkdir -p build && cd build && npx http-server -p $(BUILD_SERVE_PORT) --cors -c-1 &

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
	npx stylelint 'src/**/*.scss'

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
	npx elm-coverage src/ --open

.PHONY: test
test: ## Runs the tests.
	@echo "\033[36mTesting...\033[0m"

.PHONY: start
start: print_env
start: ## Starts the project in development mode.
	@echo "\033[36mStarting project...\033[0m"
	
	