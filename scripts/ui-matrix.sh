#!/bin/zsh
# Runs the UI tests on many simulators, text sizes, languages, appearances and
# orientations, and the unit tests once per simulator. Writes a report and all
# screenshots to build/ui-matrix/<time>/.
#
#   scripts/ui-matrix.sh                 # standard: 4 devices x 6 variants, about 3 hours
#   scripts/ui-matrix.sh quick           # 1 device x 2 variants, about half an hour
#   scripts/ui-matrix.sh full            # 12 devices x 31 variants, a night or more
#   scripts/ui-matrix.sh standard --only OverviewScreenTests
#   scripts/ui-matrix.sh quick --devices "iPhone SE 27,iPad mini 27"
#   scripts/ui-matrix.sh quick --variants "de:AX5:dark:portrait:0"
#   scripts/ui-matrix.sh --skip-build    # reuse the last build
#   scripts/ui-matrix.sh --workers 2     # 2 clones per device, so 2 devices at a time
#   PS_MAX_SIMULATORS=4 scripts/ui-matrix.sh full   # on a larger machine
#
# A variant is language:text size:appearance:orientation:hidden values, for
# example de:AX5:dark:landscape:0. Text sizes: XS S M L XL XXL XXXL AX1…AX5.
#
# The simulators are created on first use, named "PS <name>", and left in place.
set -euo pipefail

root=${0:A:h:h}
cd "$root"

profile=standard
only=()
custom_devices=""
custom_variants=""
skip_build=0
# Never more than this many simulators run at once, clones included. Four at
# the accessibility text sizes drove a 32 GB Mac to a load of 130 and made
# tests time out for no fault of the app; two keep it responsive. The devices
# are tested in groups of that size, each shut down before the next boots.
max_simulators=${PS_MAX_SIMULATORS:-2}
# Clones of each device that share its tests. 1 means no clones.
workers=${PS_WORKERS:-1}
concurrency=""

while (( $# )); do
    case $1 in
        quick|standard|full) profile=$1 ;;
        --only) only+=("$2"); shift ;;
        --devices) custom_devices=$2; shift ;;
        --variants) custom_variants=$2; shift ;;
        --skip-build) skip_build=1 ;;
        --concurrency) concurrency=$2; shift ;;  # fewer devices at a time than the limit allows
        --workers) workers=$2; shift ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# MARK: Devices: name|device type|runtime

typeset -A device_spec
device_spec=(
    "iPhone SE 27"      "iPhone-SE-3rd-generation|iOS-27-0"
    "iPhone 13 mini 27" "iPhone-13-mini|iOS-27-0"
    "iPhone 15 27"      "iPhone-15|iOS-27-0"
    "iPhone Air 27"     "iPhone-Air|iOS-27-0"
    "iPhone 17 Pro Max 27" "iPhone-17-Pro-Max|iOS-27-0"
    "iPad mini 27"      "iPad-mini-A17-Pro|iOS-27-0"
    "iPad Air 11 27"    "iPad-Air-11-inch-M4|iOS-27-0"
    "iPad Pro 13 27"    "iPad-Pro-13-inch-M5-12GB|iOS-27-0"
    "iPhone 17 Pro 26"  "iPhone-17-Pro|iOS-26-5"
    "iPhone SE 18"      "iPhone-SE-3rd-generation|iOS-18-0"
    "iPad 18"           "iPad-10th-generation|iOS-18-0"
    "iPhone Duo 27.1"   "iPhone-Duo|iOS-27-1"
)

case $profile in
    quick) devices=("iPhone 15 27") ;;
    standard) devices=("iPhone SE 27" "iPhone 15 27" "iPhone 17 Pro Max 27" "iPad mini 27") ;;
    full) devices=(${(k)device_spec}) ;;
esac
[[ -n $custom_devices ]] && devices=("${(@s:,:)custom_devices}")

# MARK: Variants

# The smallest and largest text, both appearances, a long language (German),
# landscape and hidden values. full adds every size and every language.
standard_variants=(
    en:L:light:portrait:0
    en:AX5:dark:portrait:0
    de:XXXL:light:portrait:0
    fr:XS:dark:portrait:0
    en:L:light:landscape:0
    en:L:light:portrait:1
)
case $profile in
    quick) variants=(en:L:light:portrait:0 de:AX5:dark:portrait:0) ;;
    standard) variants=($standard_variants) ;;
    full)
        variants=($standard_variants)
        for size in XS S M XL XXL XXXL AX1 AX2 AX3 AX4; do variants+=(en:$size:light:portrait:0); done
        for lang in de fr es it; do variants+=($lang:L:light:portrait:0 $lang:AX5:dark:portrait:0 $lang:L:dark:landscape:0); done
        variants+=(de:AX5:light:landscape:0 en:AX5:light:landscape:0 es:XXXL:dark:portrait:1)
        ;;
esac
[[ -n $custom_variants ]] && variants=("${(@s:,:)custom_variants}")

per_device=$(( workers > 1 ? workers + 1 : 1 ))
group_size=$(( max_simulators / per_device ))
(( group_size < 1 )) && group_size=1
[[ -n $concurrency ]] && (( concurrency < group_size )) && group_size=$concurrency

stamp=$(date +%Y-%m-%d-%H%M)
out="$root/build/ui-matrix/$stamp"
derived="$root/build/DerivedData"
mkdir -p "$out"
echo "Profile $profile: ${#devices} devices x ${#variants} variants, $group_size device(s) at a time, at most $max_simulators simulators -> $out"

# MARK: Simulators

udid_for() {
    local name="PS $1"
    xcrun simctl list devices -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["name"] == name and d.get("isAvailable", True):
            print(d["udid"]); sys.exit()
' "$name"
}

typeset -A udid
for device in $devices; do
    spec=${device_spec[$device]:-}
    if [[ -z $spec ]]; then echo "Unknown device: $device (known: ${(k)device_spec})" >&2; exit 2; fi
    id=$(udid_for "$device")
    if [[ -z $id ]]; then
        type=${spec%%|*}; runtime=${spec##*|}
        echo "Creating simulator PS $device ($type, $runtime)"
        if ! id=$(xcrun simctl create "PS $device" "com.apple.CoreSimulator.SimDeviceType.$type" \
            "com.apple.CoreSimulator.SimRuntime.$runtime" 2>&1); then
            echo "  skipped: $id"
            continue
        fi
    fi
    udid[$device]=$id
done

prepare() {
    local id=$1 appearance=$2
    xcrun simctl boot "$id" 2>/dev/null || true
    xcrun simctl bootstatus "$id" -b >/dev/null
    # The software keyboard, not the bar of a connected hardware keyboard.
    xcrun simctl spawn "$id" defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false
    xcrun simctl spawn "$id" defaults write com.apple.keyboard.preferences HardwareKeyboardLastSeen -bool false
    # A fixed clock and full bars, so screenshots compare.
    xcrun simctl status_bar "$id" override --time 9:41 --batteryState charged --batteryLevel 100 \
        --wifiBars 3 --cellularBars 4 --operatorName "" 2>/dev/null || true
    xcrun simctl ui "$id" appearance "$appearance" 2>/dev/null || true
}

# MARK: Build

if (( ! skip_build )); then
    xcodegen generate --quiet
    echo "Building for testing…"
    xcodebuild build-for-testing \
        -project Pingscape.xcodeproj -scheme Pingscape \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$derived" \
        CODE_SIGNING_ALLOWED=NO \
        -quiet > "$out/build.log" 2>&1 || { tail -40 "$out/build.log"; exit 1; }
fi
xctestrun=$(ls -t "$derived"/Build/Products/*.xctestrun | head -1)

if (( ${#udid} == 0 )); then echo "No simulator available" >&2; exit 1; fi

# MARK: Groups of devices

# Everything of ours that runs is shut down first, so the limit holds.
for device in ${(k)device_spec}; do
    id=$(udid_for "$device")
    [[ -n $id ]] && xcrun simctl shutdown "$id" 2>/dev/null || true
done
xcrun simctl --set testing shutdown all 2>/dev/null || true

flow_classes=(NavigationFlowTests PrivacyFlowTests ToolFlowTests LANFlowTests FirstRunFlowTests SettingsFlowTests
    DetailPageFlowTests ToolOptionFlowTests LANAndLiveFlowTests)
parallel=(-parallel-testing-enabled NO)
(( workers > 1 )) && parallel=(-parallel-testing-enabled YES -parallel-testing-worker-count "$workers")

names=(${(k)udid})
group=0
for (( first = 1; first <= ${#names}; first += group_size )); do
    group=$(( group + 1 ))
    members=(${names[first,first+group_size-1]})
    destinations=()
    for device in $members; do destinations+=(-destination "id=${udid[$device]}"); done
    echo "Group $group: ${(j:, :)members}"

    # Unit tests, once per device.
    for device in $members; do prepare "${udid[$device]}" light; done
    echo "  Unit tests…"
    xcodebuild test-without-building -xctestrun "$xctestrun" $destinations \
        -only-testing:PingscapeTests \
        -maximum-concurrent-test-simulator-destinations "$group_size" -collect-test-diagnostics never \
        -resultBundlePath "$out/unit@$group.xcresult" -quiet > "$out/unit@$group.log" 2>&1 || true

    # UI tests, once per variant.
    for variant in $variants; do
        parts=("${(@s/:/)variant}")
        lang=${parts[1]} size=${parts[2]} look=${parts[3]} orientation=${parts[4]} hidden=${parts[5]:-0}
        name="$lang-$size-$look-$orientation$( (( hidden )) && echo -hidden || true)"
        selection=()
        if (( ${#only} )); then
            for test in $only; do selection+=(-only-testing:"PingscapeUITests/$test"); done
        elif [[ $lang != en || $hidden == 1 ]]; then
            # The flows find controls by their English titles and choose hidden
            # values themselves; in the other variants only the screens are checked.
            for class in $flow_classes; do selection+=(-skip-testing:"PingscapeUITests/$class"); done
            selection+=(-only-testing:PingscapeUITests)
        else
            selection+=(-only-testing:PingscapeUITests)
        fi
        for device in $members; do prepare "${udid[$device]}" "$look"; done
        echo "  UI tests $name…"
        TEST_RUNNER_PS_LANGUAGE=$lang TEST_RUNNER_PS_TEXT_SIZE=$size TEST_RUNNER_PS_APPEARANCE=$look \
        TEST_RUNNER_PS_ORIENTATION=$orientation TEST_RUNNER_PS_HIDE_VALUES=$hidden \
        xcodebuild test-without-building -xctestrun "$xctestrun" $destinations $selection \
            -maximum-concurrent-test-simulator-destinations "$group_size" -collect-test-diagnostics never \
            $parallel -test-timeouts-enabled YES -maximum-test-execution-time-allowance 300 \
            -resultBundlePath "$out/$name@$group.xcresult" -quiet > "$out/$name@$group.log" 2>&1 || true
    done

    for device in $members; do xcrun simctl shutdown "${udid[$device]}" 2>/dev/null || true; done
    xcrun simctl --set testing shutdown all 2>/dev/null || true
done

# MARK: Report

python3 "$root/scripts/ui-matrix-report.py" "$out"
