# Lang Coach — developer commands
#
# The Xcode project lives in the nested LangCoach/ directory.
# Builds are unsigned (CODE_SIGN_IDENTITY="-") to match the allowed dev workflow.

PROJECT      := LangCoach/LangCoach.xcodeproj
SCHEME       := LangCoach
APP          := LangCoach.app
DERIVED      := build
UNSIGNED     := CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Use a local DerivedData dir so the built app is easy to find.
XCB          := xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
                  -derivedDataPath $(DERIVED) -destination 'platform=macOS'

DEBUG_APP    := $(DERIVED)/Build/Products/Debug/$(APP)
RELEASE_APP  := $(DERIVED)/Build/Products/Release/$(APP)

.DEFAULT_GOAL := help

.PHONY: help build run start restart release open-release stop clean reset



help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

build: ## Build Debug (unsigned)
	$(XCB) -configuration Debug build $(UNSIGNED)

run: build ## Build then launch the app
	open $(DEBUG_APP)

start: run ## Alias for `run`

restart: stop run ## Quit the running app, rebuild, relaunch

release: ## Build Release (unsigned) -> $(RELEASE_APP)
	$(XCB) -configuration Release build $(UNSIGNED)
	@echo "Release app: $(RELEASE_APP)"

open-release: release ## Build Release then launch it
	open $(RELEASE_APP)

stop: ## Quit the running app
	@osascript -e 'quit app "$(SCHEME)"' 2>/dev/null || true

clean: ## Clean Xcode build artifacts
	$(XCB) clean

reset: ## Remove the local DerivedData dir
	rm -rf $(DERIVED)
