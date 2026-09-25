#!/bin/sh
# Xcode Cloud: the Xcode project isn't checked in, so generate it from project.yml.
set -e
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
