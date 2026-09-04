.PHONY: generate build test validate-localization app verify run clean icon

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

verify: test validate-localization app
	./scripts/verify-project.sh $(CONFIG)

run: app
	open Shot.app

clean:
	rm -rf .build Shot.app Shot.xcodeproj
