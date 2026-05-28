PROJECT := Helm.xcodeproj
SCHEME := Helm
DESTINATION ?= platform=iOS Simulator,name=iPhone 17,OS=26.5
DEVICE_DESTINATION ?= generic/platform=iOS
DERIVED_DATA_PATH ?= build/DerivedData
# Set DEVICE_ID to your CoreDevice id (xcrun devicectl list devices) to install on a device.
DEVICE_ID ?=
SHELL := /bin/bash

.PHONY: generate build build-device install-device test clean

generate:
	@test -f Signing.xcconfig || cp Signing.xcconfig.example Signing.xcconfig
	xcodegen generate

build: generate
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination "$(DESTINATION)" build | xcbeautify

test: generate
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination "$(DESTINATION)" test | xcbeautify

build-device: generate
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination "$(DEVICE_DESTINATION)" -derivedDataPath "$(DERIVED_DATA_PATH)" build | xcbeautify

install-device: build-device
	@test -n "$(DEVICE_ID)" || { echo "Set DEVICE_ID=<your-device-id> (see: xcrun devicectl list devices)"; exit 1; }
	xcrun devicectl device install app --device $(DEVICE_ID) "$(DERIVED_DATA_PATH)/Build/Products/Debug-iphoneos/Helm.app"

clean:
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean | xcbeautify
