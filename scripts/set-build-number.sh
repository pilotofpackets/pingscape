#!/bin/sh
# Xcode build phase: writes the number of commits on the current branch into
# CFBundleVersion of the built app. The build number rises with every commit and
# needs no bookkeeping. Without git history it keeps CURRENT_PROJECT_VERSION.
set -eu

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

if ! count=$(git -C "${SRCROOT}" rev-list --count HEAD 2>/dev/null); then
    echo "note: no git history, keeping build number ${CURRENT_PROJECT_VERSION}"
    exit 0
fi

if [ "$(git -C "${SRCROOT}" rev-parse --is-shallow-repository)" = "true" ]; then
    echo "warning: shallow clone, the build number ${count} is too low (fetch full history)"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${count}" "${plist}"
