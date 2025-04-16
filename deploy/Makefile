# https://stackoverflow.com/a/18137056/403702
ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REVISION := $(shell $(ROOT_DIR)revision-gen.sh)
NAMESPACE := $(GITHUB_REF)
P2_NAMESPACE := $(shell basename "$(NAMESPACE)")
#${NAMESPACE:C/.*///}
PRONEXT_CDN_URL_TESTING := $(addprefix https://legacy-testing.globalwebindex.com/assets/,$(REVISION))
PRONEXT_CDN_URL_STAGING := $(addprefix https://legacy-staging.globalwebindex.com/assets/,$(REVISION))
PRONEXT_CDN_URL_ALPHA := $(addprefix https://legacy-alpha.globalwebindex.com/assets/,$(REVISION))
PRONEXT_CDN_URL_PRODUCTION := $(addprefix https://legacy.globalwebindex.com/assets/,$(REVISION))
P2_CDN_URL_TESTING := $(addprefix https://app-testing.globalwebindex.com/storage/platform2-crosstabs-assets-testing/assets/,$(REVISION))
P2_CDN_URL_STAGING := $(addprefix https://app-staging.globalwebindex.com/storage/platform2-crosstabs-assets-staging/assets/,$(REVISION))
P2_CDN_URL_ALPHA := $(addprefix https://app-alpha.globalwebindex.com/storage/platform2-crosstabs-assets-staging/assets/,$(REVISION))
P2_CDN_URL_PRODUCTION := $(addprefix https://app.globalwebindex.com/storage/platform2-crosstabs-assets-production/assets/,$(REVISION))
GCS_BUCKET_TESTING := "platform2-crosstabs-assets-testing"
GCS_BUCKET_STAGING := "platform2-crosstabs-assets-staging"
GCS_BUCKET_ALPHA := "platform2-crosstabs-assets-alpha"
GCS_BUCKET_PRODUCTION := "platform2-crosstabs-assets-production"
GCP_PROJECT_TESTING := "core-calculations-t"
GCP_PROJECT_STAGING := "core-calculations-s"
GCP_PROJECT_ALPHA := "core-calculations-a"
GCP_PROJECT_PRODUCTION := "core-calculations-p"

P2_FE_CONFIG_TESTING := "https://fe-configuration-api-testing.in.globalwebindex.com/"
P2_MFE_XB_TESTING := "7831ba23-01f1-4fa7-927e-146096d4da61"

P2_FE_CONFIG_STAGING := "https://fe-configuration-api-staging.in.globalwebindex.com/"
P2_MFE_XB_STAGING := "eadb92c7-b414-4a35-8602-846fc82fbeb2"

P2_FE_CONFIG_ALPHA := "https://fe-configuration-api-alpha.in.globalwebindex.com/"
P2_MFE_XB_ALPHA := "1ec74296-74e2-4205-8728-1a8e6dff998a"

P2_FE_CONFIG_PRODUCTION := "https://fe-configuration-api.in.globalwebindex.com/"
P2_MFE_XB_PRODUCTION := "1ec74296-74e2-4205-8728-1a8e6dff998a"

# override these from the commandline:
# SOURCE_DIR=./dir-to-upload make
# The directory containing the original files
SOURCE_DIR ?= $(ROOT_DIR)../build
# The directory containg the files with the paths replaced to be uploaded. From /pro/deploy/build
BUILD_DIR ?= $(ROOT_DIR)build

P2_FILES = \
  $(BUILD_DIR)/crosstabs.js \
  $(BUILD_DIR)/assets/crosstabs.css

# P2.0 releases

.PHONY: release-and-activate-p2
release-and-activate-p2: config-p2-env activate-p2

.PHONY: release-and-activate-p2-feature-branches
release-and-activate-p2-feature-branches: config-p2-env activate-p2-feature-branch

.PHONY: replace-cdn-url
replace-cdn-url: config-env config-p2-env
	echo
	echo "=== Replacing CDN URL paths with *$(TARGET_ENV)* CDN URLs ==="
	echo "-----------------------------------------------------------"
	replace-paths --source=$(SOURCE_DIR) --destination=$(BUILD_DIR) --prefix=$(PRONEXT_CDN_URL)
	$(ROOT_DIR)../bin/sedi.sh "s|$(PRONEXT_CDN_URL)|$(P2_CDN_URL)|g" $(P2_FILES)

.PHONY: config-p2-env
config-p2-env:
ifeq "$(TARGET_ENV)" "testing"
  P2_FE_CONFIG := $(P2_FE_CONFIG_TESTING)
  P2_MFE_XB := $(P2_MFE_XB_TESTING)
else ifeq "$(TARGET_ENV)" "staging"
  P2_FE_CONFIG := $(P2_FE_CONFIG_STAGING)
  P2_MFE_XB := $(P2_MFE_XB_STAGING)
else ifeq "$(TARGET_ENV)" "alpha"
  P2_FE_CONFIG := $(P2_FE_CONFIG_ALPHA)
  P2_MFE_XB := $(P2_MFE_XB_ALPHA)
else ifeq "$(TARGET_ENV)" "production"
  P2_FE_CONFIG := $(P2_FE_CONFIG_PRODUCTION)
  P2_MFE_XB := $(P2_MFE_XB_PRODUCTION)
else
  $(error "TARGET_ENV is invalid (must be one of: 'testing', 'staging', 'alpha' or 'production') but was '$(TARGET_ENV)'" )
endif

.PHONY: config-env
config-env:
# gcloud and gsutil honor CLOUDSDK_CORE_PROJECT
ifeq "$(TARGET_ENV)" "staging"
  PRONEXT_CDN_URL := $(PRONEXT_CDN_URL_STAGING)
  P2_CDN_URL := $(P2_CDN_URL_STAGING)
  CLOUDSDK_CORE_PROJECT := $(GCP_PROJECT_STAGING)
  GCS_BUCKET := $(GCS_BUCKET_STAGING)
  TARGET_REDIS ?= "staging"
else ifeq "$(TARGET_ENV)" "alpha"
  PRONEXT_CDN_URL := $(PRONEXT_CDN_URL_ALPHA)
  P2_CDN_URL := $(P2_CDN_URL_ALPHA)
  CLOUDSDK_CORE_PROJECT := $(GCP_PROJECT_ALPHA)
  GCS_BUCKET := $(GCS_BUCKET_ALPHA)
  TARGET_REDIS ?= "alpha"
else ifeq "$(TARGET_ENV)" "production"
  PRONEXT_CDN_URL := $(PRONEXT_CDN_URL_PRODUCTION)
  P2_CDN_URL := $(P2_CDN_URL_PRODUCTION)
  CLOUDSDK_CORE_PROJECT := $(GCP_PROJECT_PRODUCTION)
  GCS_BUCKET := $(GCS_BUCKET_PRODUCTION)
  TARGET_REDIS ?= "production"
else ifeq "$(TARGET_ENV)" "testing"
  PRONEXT_CDN_URL := $(PRONEXT_CDN_URL_TESTING)
  P2_CDN_URL := $(P2_CDN_URL_TESTING)
  CDN_URL := $(CDN_URL_TESTING)
  CLOUDSDK_CORE_PROJECT := $(GCP_PROJECT_TESTING)
  GCS_BUCKET := $(GCS_BUCKET_TESTING)
  TARGET_REDIS ?= "testing"
else
  $(error "TARGET_ENV is invalid (must be one of: 'testing', 'alpha', 'staging' or 'production')" )
endif

# activate-p2 stopped working due to the API changes v2/configurations
.PHONY: activate-p2
activate-p2:
	echo
	echo "=== Activating release of Crosstabs in *$(TARGET_ENV)* P2.0 ==="
	echo "---------------------------------------------------------------"
	curl "$(P2_FE_CONFIG)v2/configurations" -H 'Content-Type: application/json' --data-raw '{"microfrontend_id":$(P2_MFE_XB),"commit_id":"$(REVISION)"}'


.PHONY: activate-p2-feature-branch
activate-p2-feature-branch:
	@echo
	@echo "=== Create and activate P2 feature branch '$(NAMESPACE)' converted to '$(P2_NAMESPACE)' for in *$(TARGET_ENV)* ==="
	@echo "------------------------------------------------------------------------------------------------------------------"
	@if test -z "$(P2_NAMESPACE)"; then echo "There has to be feature branch defined"; exit 1; fi
	curl "$(P2_FE_CONFIG)v2/feature_branches_github_actions" --request POST -H 'Content-Type: application/json' --data-raw '{"feature_branch_name": "$(P2_NAMESPACE)", "application_name": "platform2", "microfrontend_name": "crosstabs", "commit_id": "$(REVISION)"}'

