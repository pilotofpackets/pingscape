#!/bin/sh
# Xcode build phase of the app: fails the build when an embedded extension has a
# different CFBundleVersion than the app. App Store Connect rejects such an upload.
set -eu

app="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
app_number=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${app}")
status=0
for plist in "${TARGET_BUILD_DIR}/${PLUGINS_FOLDER_PATH}"/*.appex/Info.plist; do
    [ -e "${plist}" ] || continue
    number=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${plist}")
    if [ "${number}" != "${app_number}" ]; then
        echo "error: $(basename "$(dirname "${plist}")") has build number ${number}, the app has ${app_number}"
        status=1
    fi
done
exit ${status}
