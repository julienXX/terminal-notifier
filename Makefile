# terminal-notifier
#
# Builds with the Command Line Tools alone; the Xcode project is optional.

SRC_DIR   := Terminal Notifier
PLIST     := $(SRC_DIR)/Terminal Notifier-Info.plist

NAME      := terminal-notifier
VERSION   := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '$(PLIST)')
BUNDLE_ID := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' '$(PLIST)')

MIN_MACOS := 10.14
ARCHS     := -arch arm64 -arch x86_64
FRAMEWORKS := -framework Cocoa -framework UserNotifications
# Override with `make app WARN=` if a new SDK introduces a warning you cannot
# fix yet.
WARN      ?= -Wall -Werror
CFLAGS    := -fobjc-arc -std=gnu11 -Os $(WARN) -mmacosx-version-min=$(MIN_MACOS)

BUILD_DIR := build
APP       := $(BUILD_DIR)/$(NAME).app
RELEASE_ZIP := $(BUILD_DIR)/$(NAME)-$(VERSION).zip
GEM       := Ruby/pkg/$(NAME)-$(VERSION).gem

# Publishing cannot be undone, so `make release` only prepares. PUBLISH=1 also
# pushes the tag, the GitHub release and the gem.
PUBLISH   ?=
RELEASE_BRANCH ?= master

# /Applications is scanned by LaunchServices, which permissions depend on.
APPDIR    ?= /Applications
PREFIX    ?= /usr/local

# Restricted entitlements need an Apple-issued provisioning profile. Ordinary
# ad-hoc builds must stay runnable without a developer account.
SIGN_IDENTITY ?= -
ENTITLEMENTS ?=
PROVISIONING_PROFILE ?=

ICON      ?=
APP_NAME  ?=

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo 'terminal-notifier $(VERSION)'
	@echo
	@echo 'Targets:'
	@echo '  make app                       build $(APP)'
	@echo '           [SIGN_IDENTITY=...] [ENTITLEMENTS=...] [PROVISIONING_PROFILE=...]'
	@echo '                                 optional provisioned build (see Time Sensitive in README)'
	@echo '  make install                   install to $(APPDIR) and link into $(PREFIX)/bin'
	@echo '  make uninstall                 remove both'
	@echo '  make icon ICON=path/to.png     build a copy with your own icon'
	@echo '           [APP_NAME=my-tool]    (see "Custom icons" in the README)'
	@echo '  make doctor                    check every documented option works'
	@echo '                                 (prompts you for the interactive ones)'
	@echo '  make test                      every automated test'
	@echo '  make test-native               content tests; no GUI or notification permission needed'
	@echo '  make screenshots               regenerate the images in assets/'
	@echo '  make release                   check, build and tag a release'
	@echo '           [PUBLISH=1]           also push the tag, release and gem'
	@echo '  make clean                     remove $(BUILD_DIR)'
	@echo
	@echo 'install may need sudo, depending on $(APPDIR) and $(PREFIX).'

.PHONY: app
app:
	@if [ -n '$(ENTITLEMENTS)' ]; then \
	  test '$(SIGN_IDENTITY)' != '-' && test -f '$(PROVISIONING_PROFILE)' \
	    || { echo 'Restricted entitlements require SIGN_IDENTITY and PROVISIONING_PROFILE.'; exit 1; }; \
	fi
	@echo '==> building $(NAME) $(VERSION) (universal, macOS $(MIN_MACOS)+)'
	@rm -rf '$(APP)'
	@mkdir -p '$(APP)/Contents/MacOS' '$(APP)/Contents/Resources'
	@clang $(CFLAGS) $(ARCHS) $(FRAMEWORKS) \
		-o '$(APP)/Contents/MacOS/$(NAME)' \
		'$(SRC_DIR)/main.m' '$(SRC_DIR)/AppDelegate.m'
	@# Xcode expands these two; doing it by hand keeps the plist identical.
	@sed -e 's/$${EXECUTABLE_NAME}/$(NAME)/' \
	     -e 's/$${PRODUCT_NAME}/$(NAME)/' \
	     '$(PLIST)' > '$(APP)/Contents/Info.plist'
	@printf 'APPL????' > '$(APP)/Contents/PkgInfo'
	@cp Terminal.icns '$(APP)/Contents/Resources/Terminal.icns'
	@cp -R '$(SRC_DIR)/en.lproj' '$(APP)/Contents/Resources/'
	@# Default to ad-hoc signing; a provisioned build embeds its profile first.
	@# Notifications need a signed bundle identity on modern macOS.
	@if [ -n '$(ENTITLEMENTS)' ]; then \
	  cp '$(PROVISIONING_PROFILE)' '$(APP)/Contents/embedded.provisionprofile' && \
	  codesign --force --sign '$(SIGN_IDENTITY)' --entitlements '$(ENTITLEMENTS)' '$(APP)'; \
	else \
	  codesign --force --sign '$(SIGN_IDENTITY)' '$(APP)'; \
	fi
	@echo '==> $(APP)'
	@lipo -info '$(APP)/Contents/MacOS/$(NAME)' | sed 's/^/    /'

.PHONY: install
install: app
	@echo '==> installing to $(APPDIR)'
	rm -rf '$(APPDIR)/$(NAME).app'
	cp -R '$(APP)' '$(APPDIR)/'
	mkdir -p '$(PREFIX)/bin'
	ln -sf '$(APPDIR)/$(NAME).app/Contents/MacOS/$(NAME)' '$(PREFIX)/bin/$(NAME)'
	@echo '==> $(PREFIX)/bin/$(NAME) -> $(APPDIR)/$(NAME).app'

.PHONY: uninstall
uninstall:
	rm -rf '$(APPDIR)/$(NAME).app'
	rm -f '$(PREFIX)/bin/$(NAME)'

# There is no API to override a notification's icon; it comes from the app
# bundle. So a custom icon means a custom bundle, with its own identifier.
.PHONY: icon
icon: app
	@if [ -z '$(ICON)' ]; then \
		echo 'usage: make icon ICON=path/to/image.png [APP_NAME=my-tool]'; exit 1; fi
	@if [ ! -f '$(ICON)' ]; then echo 'no such file: $(ICON)'; exit 1; fi
	@set -e; \
	name='$(APP_NAME)'; \
	if [ -z "$$name" ]; then name=$$(basename '$(ICON)' | sed 's/\.[^.]*$$//'); fi; \
	dest='$(BUILD_DIR)/'"$$name"'.app'; \
	echo "==> building $$dest"; \
	rm -rf "$$dest"; \
	cp -R '$(APP)' "$$dest"; \
	case '$(ICON)' in \
	  *.icns) cp '$(ICON)' "$$dest/Contents/Resources/icon.icns" ;; \
	  *) \
	    set='$(BUILD_DIR)/icon.iconset'; \
	    rm -rf "$$set"; mkdir -p "$$set"; \
	    for size in 16 32 128 256 512; do \
	      sips -z $$size $$size '$(ICON)' --out "$$set/icon_$${size}x$${size}.png" >/dev/null; \
	      double=$$((size * 2)); \
	      sips -z $$double $$double '$(ICON)' --out "$$set/icon_$${size}x$${size}@2x.png" >/dev/null; \
	    done; \
	    iconutil --convert icns "$$set" --output "$$dest/Contents/Resources/icon.icns"; \
	    rm -rf "$$set" ;; \
	esac; \
	rm -f "$$dest/Contents/Resources/Terminal.icns"; \
	/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile icon' "$$dest/Contents/Info.plist"; \
	/usr/libexec/PlistBuddy -c 'Set :CFBundleName '"$$name" "$$dest/Contents/Info.plist"; \
	/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier $(BUNDLE_ID).'"$$name" "$$dest/Contents/Info.plist"; \
	codesign --force --sign - "$$dest"; \
	echo "==> $$dest"; \
	echo "    bundle id  $(BUNDLE_ID).$$name"; \
	echo "    it will ask for notification permission separately the first time"

.PHONY: test-native
test-native:
	@mkdir -p '$(BUILD_DIR)'
	@clang $(CFLAGS) $(FRAMEWORKS) -o '$(BUILD_DIR)/time-sensitive-tests' tests/time-sensitive.m
	@'$(BUILD_DIR)/time-sensitive-tests'

.PHONY: test
test: app test-native
	@tests/doctor.sh --unattended
	@echo
	@echo '==> ruby specs'
	@# Ruby/.ruby-version selects a supported interpreter, but only if a version
	@# manager honours it. Say so plainly rather than failing inside bundler.
	@cd Ruby && ruby -e 'abort "ruby #{RUBY_VERSION} is too old; the gem needs 3.2+.\n" \
	  "Install it (rbenv install $$(cat .ruby-version)) or run with a newer ruby." \
	  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")'
	@cd Ruby && bundle exec rspec
	@echo
	@echo '==> rubocop'
	@cd Ruby && bundle exec rubocop --disable-pending-cops

.PHONY: doctor
doctor: app
	@tests/doctor.sh

# Needs Screen Recording permission for the terminal you run it from.
.PHONY: screenshots
screenshots: app
	@tools/screenshots.sh

.PHONY: release
release:
	@echo '==> checking'
	@test -z "$$(git status --porcelain)" \
	  || { echo 'working tree is not clean'; exit 1; }
	@test "$$(git rev-parse --abbrev-ref HEAD)" = '$(RELEASE_BRANCH)' \
	  || { echo "not on $(RELEASE_BRANCH) (on $$(git rev-parse --abbrev-ref HEAD))"; exit 1; }
	@git fetch --quiet origin
	@test "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/$(RELEASE_BRANCH))" \
	  || { echo 'HEAD and origin/$(RELEASE_BRANCH) differ; push or pull first'; exit 1; }
	@# The plist and the gem carry the version separately. They must agree, or
	@# the tag, the zip and the gem end up describing different builds.
	@gemv=$$(sed -n "s/.*VERSION = '\(.*\)'.*/\1/p" Ruby/lib/terminal-notifier/version.rb); \
	  test "$$gemv" = '$(VERSION)' \
	  || { echo "version mismatch: plist $(VERSION), gem $$gemv"; exit 1; }
	@# `make release` tags, so `make release PUBLISH=1` finds a tag already
	@# there. Accept it, but only when it names the commit being released.
	@if git rev-parse -q --verify 'refs/tags/$(VERSION)' >/dev/null; then \
	    test "$$(git rev-parse '$(VERSION)^{commit}')" = "$$(git rev-parse HEAD)" \
	      || { echo "tag $(VERSION) points at $$(git rev-parse --short '$(VERSION)^{commit}'), not HEAD"; \
	           echo 'move it with: git tag -f -a $(VERSION) -m $(VERSION)'; exit 1; }; \
	  fi
	@echo '    version      $(VERSION)'
	@echo '    branch       $(RELEASE_BRANCH) in sync with origin'
	@echo '    tree         clean'
	@echo
	@echo '==> testing'
	@$(MAKE) --no-print-directory test
	@echo
	@echo '==> building the release artifacts'
	@$(MAKE) --no-print-directory app
	@rm -f '$(RELEASE_ZIP)'
	@# Same shape as every previous release: the app bundle and the README.
	@cp README.markdown '$(BUILD_DIR)/README.markdown'
	@cd '$(BUILD_DIR)' && zip -q -r -y '$(NAME)-$(VERSION).zip' '$(NAME).app' README.markdown
	@rm -f '$(BUILD_DIR)/README.markdown'
	@echo "    $(RELEASE_ZIP)  ($$(du -h '$(RELEASE_ZIP)' | cut -f1))"
	@cd Ruby && bundle exec rake build >/dev/null
	@echo "    $(GEM)"
	@# A gem without the binary is useless, and easy to ship by accident.
	@tar -xOf '$(GEM)' data.tar.gz | tar -tzf - | grep -q 'MacOS/$(NAME)' \
	  || { echo 'the gem has no binary in it'; exit 1; }
	@echo '    gem contains the binary'
	@echo
	@git rev-parse -q --verify 'refs/tags/$(VERSION)' >/dev/null \
	  || git tag -a '$(VERSION)' -m '$(VERSION)'
	@echo "==> tagged $(VERSION) (local only)"
ifeq ($(PUBLISH),)
	@echo
	@echo 'Nothing has been published. To publish:'
	@echo '    make release PUBLISH=1'
	@echo 'or by hand:'
	@echo '    git push origin $(VERSION)'
	@echo '    gh release create $(VERSION) $(RELEASE_ZIP) --title $(VERSION)'
	@echo '    gem push $(GEM)'
	@echo
	@echo 'To undo the tag:  git tag -d $(VERSION)'
else
	@echo
	@echo '==> publishing'
	git push origin '$(VERSION)'
	gh release create '$(VERSION)' '$(RELEASE_ZIP)' --title '$(VERSION)' --generate-notes
	gem push '$(GEM)'
	@echo '==> published $(VERSION)'
endif

.PHONY: clean
clean:
	rm -rf '$(BUILD_DIR)'
