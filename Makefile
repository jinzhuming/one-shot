.PHONY: generate build test validate-localization app xcodebuild verify run clean icon

CONFIG ?= debug

generate:
	xcodegen generate
	./scripts/validate-project.sh
	$(MAKE) validate-localization

build:
	swift build -c $(CONFIG)

test:
	swift test

validate-localization:
	swift ./scripts/validate-localization.swift

icon:
	swift "$(CURDIR)/scripts/generate-icon.swift"

app: build
	./scripts/package-app.sh $(CONFIG)

xcodebuild: generate
	DEVELOPER_DIR="$${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcodebuild -project Shot.xcodeproj -scheme Shot -configuration Debug CODE_SIGNING_ALLOWED=NO build

verify: test validate-localization app xcodebuild
	./scripts/verify-project.sh $(CONFIG)

run: app
	open Shot.app

clean:
	rm -rf .build Shot.app Shot.xcodeproj
