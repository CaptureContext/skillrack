PRODUCT := skillrack
CONFIGURATION ?= release
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=
SWIFT ?= swift
SWIFT_BUILD_FLAGS ?=
INSTALL ?= install
DISTDIR ?= dist
MACOS_DEPLOYMENT_TARGET ?= 15.0

EXECUTABLE := .build/$(CONFIGURATION)/$(PRODUCT)
INSTALLED_EXECUTABLE := $(DESTDIR)$(BINDIR)/$(PRODUCT)
RELEASE_MACHINE := $(shell uname -m)
RELEASE_ARCH := $(if $(filter arm64,$(RELEASE_MACHINE)),aarch64,$(RELEASE_MACHINE))
RELEASE_EXECUTABLE := .build/release/$(PRODUCT)
RELEASE_ARTIFACT := $(PRODUCT)-$(RELEASE_ARCH)-apple-darwin
UNIVERSAL_RELEASE_ARTIFACT := $(PRODUCT)-universal-apple-darwin
UNIVERSAL_BUILD_SCRIPT := ./Scripts/build-universal.sh

.PHONY: all build test release universal install uninstall clean

all: build

build:
	$(SWIFT) build \
		$(SWIFT_BUILD_FLAGS) \
		--configuration $(CONFIGURATION) \
		--product $(PRODUCT)

test:
	$(SWIFT) test

release:
	$(SWIFT) build \
		$(SWIFT_BUILD_FLAGS) \
		--configuration release \
		--product $(PRODUCT)
	$(INSTALL) -d "$(DISTDIR)"
	$(INSTALL) -m 755 \
		"$(RELEASE_EXECUTABLE)" \
		"$(DISTDIR)/$(RELEASE_ARTIFACT)"
	cd "$(DISTDIR)" && \
		shasum -a 256 "$(RELEASE_ARTIFACT)" \
			> "$(RELEASE_ARTIFACT).sha256"

universal:
	PRODUCT="$(PRODUCT)" \
		CONFIGURATION="release" \
		MACOS_DEPLOYMENT_TARGET="$(MACOS_DEPLOYMENT_TARGET)" \
		OUTPUT_PATH="$(DISTDIR)/$(UNIVERSAL_RELEASE_ARTIFACT)" \
		BUILD_SYSTEM="native" \
		SWIFT="$(SWIFT)" \
		"$(UNIVERSAL_BUILD_SCRIPT)"

install: build
	$(INSTALL) -d "$(DESTDIR)$(BINDIR)"
	$(INSTALL) -m 755 \
		"$(EXECUTABLE)" \
		"$(INSTALLED_EXECUTABLE)"

uninstall:
	$(RM) "$(INSTALLED_EXECUTABLE)"

clean:
	$(SWIFT) package clean
