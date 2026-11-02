#!/bin/zsh
# Builds Nyx, assembles the .app bundle, signs it and (with --install)
# installs it into /Applications.
#
# The bundle is staged in a temporary directory outside ~/Documents: folders synced
# by File Provider gain xattrs (com.apple.provenance etc.) that invalidate codesign.
set -euo pipefail
cd "$(dirname "$0")"

# The icon catalog and the bundle are staged in temp dirs; sweep both however
# the script ends.
ICON_TMP=""
STAGE_TMP=""

cleanup() {
    [[ -n "$ICON_TMP" ]] && rm -rf "$ICON_TMP"
    [[ -n "$STAGE_TMP" ]] && rm -rf "$STAGE_TMP"
    return 0
}
trap cleanup EXIT
# zsh runs the EXIT trap when the script is hung up, but not when it is
# interrupted or terminated; route those through exit so a Ctrl-C partway
# into the build sweeps like any other ending.
trap 'exit 1' INT TERM HUP

# Flags: --dev builds the local-only "Nyx (Developer)" variant (its own
# bundle id, so it coexists with the official app); --install puts it in /Applications.
DEV=0
INSTALL=0
TEST=0
TEST_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dev)     DEV=1 ;;
        --install) INSTALL=1 ;;
        --test)    TEST=1 ;;
        --test-suite=*) TEST=1; TEST_ARGS+=("--suite=${arg#*=}") ;;
        --list-tests) TEST=1; TEST_ARGS+=(--list) ;;
    esac
done

if (( DEV )); then
    APP_NAME="Nyx (Developer)"
    EXECUTABLE="NyxDeveloper"
    APP_BUNDLE_ID="com.nyx.utils.dev"
    BUILD_VARIANT_FLAGS=(-D NYX_DEVELOPMENT)
    APP_OPTIMIZATION_FLAGS=(-Onone)
    BUILD_CONFIGURATION="debug"
else
    APP_NAME="Nyx"
    EXECUTABLE="Nyx"
    APP_BUNDLE_ID="com.nyx.utils"
    BUILD_VARIANT_FLAGS=()
    APP_OPTIMIZATION_FLAGS=(-O)
    BUILD_CONFIGURATION="release"
fi
# Now Playing is read through /usr/bin/perl loading this library; see
# Sources/NowPlayingAdapter. Staged under Contents/Frameworks, signed on its own.
NOW_PLAYING_ADAPTER_ID="$APP_BUNDLE_ID.now-playing"
NOW_PLAYING_ADAPTER="libNyxNowPlaying.dylib"
TARGET="arm64-apple-macosx14.0"
ENTITLEMENTS="Resources/Nyx.entitlements"
LEGACY_IDENTITY="Nyx Utils Signing"

developer_id_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' \
        | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' || true
}

# A find-identity listing also names certificates codesign then rejects (an
# expired one fails the build with errSecInternalComponent), and -v excludes
# every self-signed one; ask codesign itself with a throwaway copy of /bin/echo.
legacy_identity_installed() {
    local probe signed=1
    # A locked keychain still lists its identities but cannot sign with them,
    # and this one is locked after every reboot; unlock it before asking.
    security unlock-keychain -p nyx-signing \
        "$HOME/Library/Keychains/nyx-signing.keychain-db" 2>/dev/null || true
    probe="$(mktemp)"
    cp /bin/echo "$probe"
    /usr/bin/codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$probe" \
        >/dev/null 2>&1 && signed=0
    rm -f "$probe"
    return $signed
}

# Any build that lands in /Applications needs a stable signature, not just the
# Developer one: macOS ties Accessibility and Screen Recording grants to the
# exact binary hash, so an ad-hoc rebuild orphans them while System Settings
# keeps showing them as granted, and no new prompt ever appears. A plain
# --install strands them under the released bundle id, on the app the user
# actually relies on. When no identity is installed, create the stable local one
# up front instead of falling through to ad-hoc — setup-signing.sh is free,
# offline and idempotent. Gating on the install rather than the variant keeps
# this off CI, where ci.yml does not pass --install.
if (( DEV || INSTALL )) && [[ -z "$(developer_id_identity)" ]] \
    && ! legacy_identity_installed; then
    echo "▸ No signing identity installed; creating the stable local one…"
    if ! ./Tools/setup-signing.sh; then
        echo "  ⚠ Tools/setup-signing.sh failed; signing ad-hoc instead." >&2
        echo "    Accessibility and Screen Recording grants will not survive rebuilds:" >&2
        echo "    System Settings will show them as granted while the app is not trusted." >&2
        echo "    After fixing the identity, clear the stale grant once with:" >&2
        echo "      tccutil reset Accessibility $APP_BUNDLE_ID" >&2
    fi
fi

codesign_with_timestamp_retry() {
    local attempt
    for attempt in 1 2 3; do
        if /usr/bin/codesign "$@"; then
            return 0
        fi
        if (( attempt < 3 )); then
            echo "  Developer ID signing failed; retrying ($((attempt + 1))/3)"
            sleep "$attempt"
        fi
    done
    return 1
}

write_swift_output_file_map() {
    local output_file="$1"
    local object_dir="$2"
    shift 2
    local source artifact

    {
        print -r -- "{"
        print -r -- "  \"\": {"
        print -r -- "    \"swift-dependencies\": \"$object_dir/master.swiftdeps\""
        print -r -- "  }"
        for source in "$@"; do
            artifact="${source//\//__}"
            artifact="${artifact%.swift}"
            print -r -- ","
            print -r -- "  \"$source\": {"
            print -r -- "    \"object\": \"$object_dir/$artifact.o\","
            print -r -- "    \"swift-dependencies\": \"$object_dir/$artifact.swiftdeps\""
            print -r -- "  }"
        done
        print -r -- "}"
    } > "$output_file"
}

finalize_installed_bundle_after_child() {
    local bundle="$1"
    local adapter="$bundle/Contents/Frameworks/$NOW_PLAYING_ADAPTER"
    local devid
    devid="$(developer_id_identity)"

    echo "▸ Finalizing installed signature…"
    sleep 3
    if [[ -n "$devid" ]]; then
        [[ -f "$adapter" ]] && codesign_with_timestamp_retry --force --strip-disallowed-xattrs \
            --options runtime --timestamp --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$devid" "$adapter"
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$devid" "$bundle"
    elif legacy_identity_installed; then
        [[ -f "$adapter" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$LEGACY_IDENTITY" "$adapter"
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$bundle"
    else
        [[ -f "$adapter" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$NOW_PLAYING_ADAPTER_ID" --sign - "$adapter"
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign - "$bundle"
    fi
    [[ -f "$adapter" ]] && /usr/bin/codesign --verify --strict "$adapter"
    /usr/bin/codesign --verify --deep --strict "$bundle"
    echo "✓ Signature ready: $bundle"
}

if (( INSTALL && ! TEST )) && [[ "${NYX_INSTALL_CHILD:-0}" != "1" ]]; then
    NYX_INSTALL_CHILD=1 "$0" "$@"
    child_status=$?
    if (( child_status != 0 )); then
        exit "$child_status"
    fi
    finalize_installed_bundle_after_child "/Applications/$APP_NAME.app"
    exit 0
fi

# Prefer the macOS 26 SDK when present: the 27 SDK turns SwiftUI property wrappers
# into macros (SwiftUIMacros plugin) that the Command Line Tools cannot load yet.
PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    SDK="$(xcrun --show-sdk-path)"
elif [[ -d "$PINNED_SDK" ]]; then
    SDK="$PINNED_SDK"
else
    SDK="$(xcrun --show-sdk-path)"
fi
SDK_COMPAT_FLAGS=()
VM_STATISTICS_COMPAT_FLAGS=(-I Sources/VMStatisticsCompat)
HID_EVENT_SYSTEM_FLAGS=(-I Sources/HIDEventSystem)
if [[ "$SDK" == "$PINNED_SDK" ]]; then
    # Swift 6.4 can read the SDK 26 interfaces when given their compiler version.
    SDK_COMPAT_FLAGS=(-Xfrontend -interface-compiler-version -Xfrontend 6.3.2)
fi

# The defaults migrations under test need a real UserDefaults suite, and every
# suite leaves an empty plist in ~/Library/Preferences. The tests already clear
# the domains, but cfprefsd writes the emptied file back out around the time the
# process that owned it exits, so only a caller that outlives the run can remove
# them. `PreferenceNamespaceTests` scans every compiled Swift test file against
# these namespaces, which keeps this sweep complete without a second list.
discard_test_preferences() {
    local preferences="${1:-$HOME/Library/Preferences}" name attempt
    local survivors=0 quiet_passes=0
    # cfprefsd can recreate an emptied domain after the first removal. Require
    # two quiet checks, but keep a hard limit so persistent failures still fail CI.
    for attempt in {1..10}; do
        for name in "com.nyx.tests."; do
            rm -f "$preferences"/$name*.plist(N)
        done
        rm -f "$preferences/metrics-tests.plist"
        sleep 0.2
        survivors=$(find "$preferences" -maxdepth 1 \
            \( -name "com.nyx.tests.*.plist" \
               -o -name "metrics-tests.plist" \) 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$survivors" == "0" ]]; then
            quiet_passes=$((quiet_passes + 1))
            if (( quiet_passes == 2 )); then return 0; fi
        else
            quiet_passes=0
        fi
    done
    echo "✗ test preferences did not settle in $preferences ($survivors remaining)" >&2
    return 1
}

# Standalone automated tests: pure contracts plus isolated disk, subprocess,
# keyboard-data and media fixtures. No application windows or device capture.
if (( TEST )); then
    python3 Tests/generate_sources.py
    TEST_OBJECT_DIR="build/objects/tests"
    mkdir -p "$TEST_OBJECT_DIR"
    TEST_SOURCES=(
        Sources/Nyx/Services/Media/MediaSupport.swift
        Sources/Nyx/Core/QuitProtectionSupport.swift
        Sources/Nyx/Core/QuitProtectionStrings.swift
        Sources/Nyx/Core/Defaults.swift
        Sources/Nyx/Core/NotchStrings.swift
        Sources/Nyx/Core/NotchTourStrings.swift
        Sources/Nyx/Core/NotchEditorStrings.swift
        Sources/Nyx/UI/Settings/NotchSettingsTabRow.swift
        Sources/Nyx/Core/NotchActivityStrings.swift
        Sources/Nyx/Services/Notch/NotchTimerSupport.swift
        Sources/Nyx/Services/Notch/NotchAppFullscreen.swift
        Sources/Nyx/Services/Notch/NotchTimerAlert.swift
        Sources/Nyx/UI/Notch/NotchIslandAlert.swift
        Sources/Nyx/Services/Notch/NotchAccessorySupport.swift
        Sources/Nyx/Services/Notch/NotchAccessoryConnectionMonitor.swift
        Sources/Nyx/Services/QuickTools/CameraPreviewSupport.swift
        Sources/Nyx/Core/NotchMusicExtrasStrings.swift
        Sources/Nyx/Core/NotchClipboardSizeStrings.swift
        Sources/Nyx/Services/Notch/NotchLyricsSupport.swift
        Sources/Nyx/Services/Notch/NotchQueueSupport.swift
        Sources/Nyx/Services/Notch/NotchPreferredPlayer.swift
        Sources/Nyx/Core/NotchFilesStrings.swift
        Sources/Nyx/Core/NotchWatchStrings.swift
        Sources/Nyx/Core/NotchCalculatorStrings.swift
        Sources/Nyx/Core/NotchAlarmStrings.swift
        Sources/Nyx/Services/Notch/NotchAlarmSupport.swift
        Sources/Nyx/Core/NotchTeleprompterStrings.swift
        Sources/Nyx/Services/Notch/NotchTeleprompterSupport.swift
        Sources/Nyx/Services/Notch/NotchWatchSupport.swift
        Sources/Nyx/Core/NotchMascotStrings.swift
        Sources/Nyx/Services/Notch/NotchMascotSupport.swift
        Sources/Nyx/Services/CommandBar/CommandBarDropletMotion.swift
        Sources/Nyx/Services/Notch/NotchFileToolsSupport.swift
        Sources/Nyx/Services/Notch/NotchDownloadSupport.swift
        Sources/Nyx/Services/Notch/NotchDownloadProgressObserver.swift
        Sources/Nyx/Core/NotchCalendarStrings.swift
        Sources/Nyx/Core/NotchNotificationStrings.swift
        Sources/Nyx/Core/NotchGestureStrings.swift
        Sources/Nyx/Core/NotchAgentStrings.swift
        Sources/Nyx/Core/CodexAccountStrings.swift
        Sources/Nyx/Core/ClaudeAccountStrings.swift
        Sources/Nyx/Services/Notch/NotchAgentSupport.swift
        Sources/Nyx/Core/NotchLockScreenStrings.swift
        Sources/Nyx/Services/Notch/NotchLockScreenSupport.swift
        Sources/Nyx/Services/AgentUsage/AgentUsageModels.swift
        Sources/Nyx/Services/AgentUsage/AgentPricing.swift
        Sources/Nyx/Services/AgentUsage/AgentLogObject.swift
        Sources/Nyx/Services/AgentUsage/AgentLogParser.swift
        Sources/Nyx/Services/AgentUsage/Harness/AgentHarnessReader.swift
        Sources/Nyx/Services/AgentUsage/Harness/ClaudeReader.swift
        Sources/Nyx/Services/AgentUsage/Harness/CodexReader.swift
        Sources/Nyx/Services/AgentUsage/Harness/OpenCodeReader.swift
        Sources/Nyx/Services/AgentUsage/Harness/CopilotReader.swift
        Sources/Nyx/Services/AgentUsage/Harness/GeminiReader.swift
        Sources/Nyx/Services/AgentUsage/AgentUsageSummary.swift
        Sources/Nyx/Services/AgentUsage/AgentUsageStore.swift
        Sources/Nyx/Services/AgentUsage/AgentUsageArchive.swift
        Sources/Nyx/Services/AgentUsage/AgentClaudeAppUsage.swift
        Sources/Nyx/Services/AgentUsage/AgentCLIConversation.swift
        Sources/Nyx/Services/AgentUsage/AgentClaudeServer.swift
        Sources/Nyx/Services/AgentUsage/ClaudeAccountProfile.swift
        Sources/Nyx/Services/AgentUsage/AgentCodexServer.swift
        Sources/Nyx/Services/AgentUsage/CodexAccountLimits.swift
        Sources/Nyx/Services/AgentUsage/CodexProfileLimitsService.swift
        Sources/Nyx/Services/AgentUsage/AgentOpenCodeReader.swift
        Sources/Nyx/Services/AgentUsage/AgentGeminiSessions.swift
        Sources/Nyx/Services/Notch/NotchGestureSupport.swift
        Sources/Nyx/Services/Notch/NotchSectionPaging.swift
        Sources/Nyx/Services/Notch/NotchSliderEditing.swift
        Sources/Nyx/Services/Notch/NotchNotificationSupport.swift
        Sources/Nyx/Services/Notch/NotchNotificationReaderCore.swift
        Sources/Nyx/Services/Notch/NotchCalendarSupport.swift
        Sources/Nyx/Services/Notch/NotchKeepAwakeSupport.swift
        Sources/Nyx/Services/Notch/NotchSupport.swift
        Sources/Nyx/Services/Notch/NotchAudioLevelSupport.swift
        Sources/Nyx/Services/Notch/NotchVolumeKeyGate.swift
        Sources/Nyx/Services/Notch/NotchMusicSupport.swift
        Sources/Nyx/UI/Notch/NotchDecorativeClock.swift
        Sources/Nyx/Services/Notch/NotchBrowserArtworkSupport.swift
        Sources/Nyx/Services/Notch/NotchSiteIcon.swift
        Sources/Nyx/UI/Notch/NotchEqualizerBars.swift
        Sources/Nyx/UI/Notch/NotchScrollEdgeFade.swift
        Sources/Nyx/UI/Notch/NotchAgentAnimationView.swift
        Sources/Nyx/UI/WindowVisibilityReader.swift
        Sources/Nyx/Services/Notch/NotchMusicAutomationSupport.swift
        Sources/Nyx/Services/Notch/NotchMusicAutomation.swift
        Sources/Nyx/Services/Notch/NotchPlaybackSource.swift
        Sources/Nyx/Services/Notch/NotchPlaybackCommand.swift
        Sources/Nyx/Services/Notch/NotchMusicCommandWriter.swift
        Sources/Nyx/Core/FeatureCatalog.swift
        Sources/Nyx/Core/FeaturePresets.swift
        Sources/Nyx/Core/FeatureHubStrings.swift
        Sources/Nyx/Core/MixerScreenSharingStrings.swift
        Sources/Nyx/Core/ShortcutSettingsStrings.swift
        Sources/Nyx/Core/SwitcherShortcutStrings.swift
        Sources/Nyx/Core/SettingsBackupSupport.swift
        Sources/Nyx/Core/BackupStrings.swift
        Sources/Nyx/Core/SnippetStrings.swift
        Sources/Nyx/Core/AlertSoundStrings.swift
        Sources/Nyx/Core/BrightnessStrings.swift
        Sources/Nyx/Core/MediaImageStrings.swift
        Sources/Nyx/Core/QuickToggleStrings.swift
        Sources/Nyx/Core/ScreenshotStrings.swift
        Sources/Nyx/Core/RecentCaptureStrings.swift
        Sources/Nyx/Core/MenuBarFolderStrings.swift
        Sources/Nyx/Core/RecorderStrings.swift
        Sources/Nyx/Core/CameraPreviewStrings.swift
        Sources/Nyx/Core/WallpaperStrings.swift
        Sources/Nyx/Services/Wallpaper/WallpaperSupport.swift
        Sources/Nyx/UI/MenuPanel/WallpaperThumbnailView.swift
        Sources/Nyx/Core/ScratchpadStrings.swift
        Sources/Nyx/Core/FinderRenameStrings.swift
        Sources/Nyx/Core/CommandBarStrings.swift
        Sources/Nyx/Core/RadialMenuStrings.swift
        Sources/Nyx/Core/MenuBarAppearanceStrings.swift
        Sources/Nyx/Core/AppAppearance.swift
        Sources/Nyx/Core/AppearanceStrings.swift
        Sources/Nyx/Core/GeneralSettingsStrings.swift
        Sources/Nyx/Core/SettingsPageStrings.swift
        Sources/Nyx/Core/BatteryTimeStrings.swift
        Sources/Nyx/Core/CPUCoreStrings.swift
        Sources/Nyx/Core/MonitorLayoutStrings.swift
        Sources/Nyx/Core/KeepAwakeStrings.swift
        Sources/Nyx/Core/BluetoothSleepStrings.swift
        Sources/Nyx/Core/PermissionGuideStrings.swift
        Sources/Nyx/Core/ConnectedDevicesStrings.swift
        Sources/Nyx/Services/Snippets/TextSnippetSupport.swift
        Sources/Nyx/Services/RadialMenu/RadialMenuSupport.swift
        Sources/Nyx/Services/QuickTools/ScratchpadSupport.swift
        Sources/Nyx/Services/QuickTools/ScratchpadStore.swift
        Sources/Nyx/Services/Recorder/RecorderSupport.swift
        Sources/Nyx/Services/Recorder/RecorderSampleTiming.swift
        Sources/Nyx/Services/Recorder/RecorderWriter.swift
        Sources/Nyx/Services/Recorder/RecorderCaptureEngine.swift
        Sources/Nyx/Core/RecorderExportStrings.swift
        Sources/Nyx/Services/Recorder/RecorderComposer.swift
        Sources/Nyx/Services/Recorder/RecorderComposerPlan.swift
        Sources/Nyx/Services/Recorder/RecorderCursorSprite.swift
        Sources/Nyx/Services/Recorder/RecorderTextRenderer.swift
        Sources/Nyx/Services/Recorder/RecorderImageRenderer.swift
        Sources/Nyx/Services/Recorder/RecorderExporter.swift
        Sources/Nyx/Services/Recorder/RecorderGIFClipboard.swift
        Sources/Nyx/Services/Recorder/RecorderGIFWriter.swift
        Sources/Nyx/Services/Recorder/RecorderGIFWorkspace.swift
        Sources/Nyx/Services/Recorder/RecorderComposition.swift
        Sources/Nyx/Services/PrivateFileStore.swift
        Sources/Nyx/Services/Recorder/RecorderTakeStore.swift
        Sources/Nyx/Services/Recorder/RecorderPresetImageStore.swift
        Sources/Nyx/Services/Recorder/RecorderMotion.swift
        Sources/Nyx/Services/Recorder/RecorderPointerTrack.swift
        Sources/Nyx/Services/Recorder/RecorderTypingTrack.swift
        Sources/Nyx/Services/Recorder/RecorderTimeline.swift
        Sources/Nyx/Services/Recorder/RecorderTextOverlay.swift
        Sources/Nyx/Services/Recorder/RecorderImageOverlay.swift
        Sources/Nyx/Services/Recorder/RecorderBlurRegion.swift
        Sources/Nyx/Services/Recorder/RecorderEditDocument.swift
        Sources/Nyx/Core/AppInfo.swift
        Sources/Nyx/Core/GlobalShortcut.swift
        Sources/Nyx/Core/SymbolicHotKeys.swift
        Sources/Nyx/Services/SystemShortcutTakeoverSupport.swift
        Sources/Nyx/Core/Localization.swift
        Sources/Nyx/Core/FeatureStrings.swift
        Sources/Nyx/Core/WhatsAppDownloadStrings.swift
        Sources/Nyx/Core/WhatsAppOrganizerStrings.swift
        Sources/Nyx/Core/URLCleaning.swift
        Sources/Nyx/Services/URLCleanerLinkMetadata.swift
        Sources/Nyx/Services/GeneralPasteboardAccess.swift
        Sources/Nyx/Services/Clipboard/ClipboardHistoryWrite.swift
        Sources/Nyx/Services/Audio/AirPlayRouteManager.swift
        Sources/Nyx/Services/Audio/MixerRoutingSupport.swift
        Sources/Nyx/Services/Audio/MusicLaunchSupport.swift
        Sources/Nyx/Services/Bluetooth/BluetoothSleepSupport.swift
        Sources/Nyx/UI/MenuPanel/MixerPercentNativeTextField.swift
        Sources/Nyx/UI/MenuPanel/MixerAppDragSource.swift
        Sources/Nyx/Services/Audio/BoostLimiter.swift
        Sources/Nyx/Services/Audio/MixerRender.swift
        Sources/Nyx/Services/Audio/PreciseVolumeRollerSupport.swift
        Sources/Nyx/Services/DockPreview/DockPreviewSupport.swift
        Sources/Nyx/Services/DockPreview/DockAutohideHold.swift
        Sources/Nyx/Services/SpacesOrder/SpacesOrderHold.swift
        Sources/Nyx/Services/AppUpdates/AppUpdatesSupport.swift
        Sources/Nyx/Services/AppUpdates/AppUpdateFeedSupport.swift
        Sources/Nyx/Core/AppUpdateStrings.swift
        Sources/Nyx/UI/NonModalAlert.swift
        Sources/Nyx/Services/Clipboard/ClipboardHistorySupport.swift
        Sources/Nyx/Core/ColorValue.swift
        Sources/Nyx/Services/Clipboard/ClipboardAutoClearSupport.swift
        Sources/Nyx/Services/AutoQuit/AutoQuitSupport.swift
        Sources/Nyx/Core/AutoQuitDockAppsStrings.swift
        Sources/Nyx/Services/Shelf/ShelfSupport.swift
        Sources/Nyx/Services/Shelf/ShelfFilePromiseTransfer.swift
        Sources/Nyx/Core/ShelfPromiseDeliveryStrings.swift
        Sources/Nyx/Services/Finder/FinderRenameSupport.swift
        Sources/Nyx/Core/VersionSupport.swift
        Sources/Nyx/Services/InstalledApps.swift
        Sources/Nyx/Services/LaunchAtLoginSupport.swift
        Sources/Nyx/UI/Settings/SettingsSearchSupport.swift
        Sources/Nyx/UI/Settings/SettingsSidebarSupport.swift
        Sources/Nyx/UI/Settings/FeatureVisibilitySupport.swift
        Sources/Nyx/UI/Settings/SettingsWindow.swift
        Sources/Nyx/Core/SettingsNavigationStrings.swift
        Sources/Nyx/App/MenuBarSpacingSupport.swift
        Sources/Nyx/App/MenuBarAllowanceSupport.swift
        Sources/Nyx/App/ReopenRequestSupport.swift
        Sources/Nyx/App/StatusItemAnchorSupport.swift
        Sources/Nyx/Services/DockClick/DockClickSupport.swift
        Sources/Nyx/Services/Finder/CutPasteProgressSupport.swift
        Sources/Nyx/Services/Finder/CutPastePrivilegeSupport.swift
        Sources/Nyx/Services/Finder/FinderPasteImageSupport.swift
        Sources/Nyx/Services/MiddleClick/MiddleClickSupport.swift
        Sources/Nyx/Services/MouseNavigation/MouseNavigationSupport.swift
        Sources/Nyx/Services/MouseNavigation/MouseNavigationKeys.swift
        Sources/Nyx/Services/MouseButtons/MouseButtonShortcutSupport.swift
        Sources/Nyx/Services/MouseButtons/MouseSpacesGestureSupport.swift
        Sources/Nyx/Services/MouseClickDebounce/MouseClickDebounceSupport.swift
        Sources/Nyx/Services/MouseExceptions/MouseAppExceptionSupport.swift
        Sources/Nyx/Services/MouseExceptions/MouseAppExceptions.swift
        Sources/Nyx/Services/WindowServerSupport.swift
        Sources/Nyx/Services/WindowMaximizerSupport.swift
        Sources/Nyx/Core/MouseButtonStrings.swift
        Sources/Nyx/Core/MouseClickDebounceStrings.swift
        Sources/Nyx/Core/MouseExceptionStrings.swift
        Sources/Nyx/Core/ClipboardIgnoredAppsStrings.swift
        Sources/Nyx/Core/ClipboardRetentionStrings.swift
        Sources/Nyx/Core/WindowLayoutIgnoredAppsStrings.swift
        Sources/Nyx/Services/WindowLayout/WindowLayoutIgnoredApps.swift
        Sources/Nyx/Core/WindowPreviewExclusionStrings.swift
        Sources/Nyx/Core/WindowMaximizerExclusionStrings.swift
        Sources/Nyx/Core/DiskExclusionStrings.swift
        Sources/Nyx/Core/SwitcherAppRulesStrings.swift
        Sources/Nyx/Services/QuickTools/QuickToolsSupport.swift
        Sources/Nyx/Services/CommandBar/CommandBarSupport.swift
        Sources/Nyx/Services/CommandBar/CommandBarPreferences.swift
        Sources/Nyx/Services/CommandBar/CommandBarMath.swift
        Sources/Nyx/Services/CommandBar/CommandBarUnits.swift
        Sources/Nyx/Services/CommandBar/CommandBarColors.swift
        Sources/Nyx/Services/CommandBar/CommandBarEmoji.swift
        Sources/Nyx/Services/CommandBar/CommandBarLinks.swift
        Sources/Nyx/Services/CommandBar/CommandBarDates.swift
        Sources/Nyx/Services/CommandBar/CommandBarRowShortcuts.swift
        Sources/Nyx/Services/CommandBar/CommandBarSystemSettingsSupport.swift
        Sources/Nyx/Services/CommandBar/CommandBarFileSearchSupport.swift
        Sources/Nyx/Services/CommandBar/CommandBarQueryMemory.swift
        Sources/Nyx/Services/SpotlightNamesSupport.swift
        Sources/Nyx/Services/QuickTools/MicMuteSupport.swift
        Sources/Nyx/Services/QuickTools/QuickTogglesSupport.swift
        Sources/Nyx/Services/QuickTools/ScreenshotCapturePolicy.swift
        Sources/Nyx/Services/QuickTools/ScreenshotSupport.swift
        Sources/Nyx/Services/QuickTools/ScreenshotCanvasSupport.swift
        Sources/Nyx/UI/Settings/ScreenCaptureToolPicker.swift
        Sources/Nyx/UI/Settings/MonitorToken.swift
        Sources/Nyx/Services/QuickTools/ScreenshotRenderer.swift
        Sources/Nyx/Services/QuickTools/ScreenshotImageLayerRendering.swift
        Sources/Nyx/Services/QuickTools/RecentCaptureStore.swift
        Sources/Nyx/Services/QuickTools/WindowActivationPolicy.swift
        Sources/Nyx/Services/KeyboardDebounce/KeyboardDebounceSupport.swift
        Sources/Nyx/Services/SuperKey/SuperKeySupport.swift
        Sources/Nyx/Services/SuperKey/SuperKeyMappingGuard.swift
        Sources/Nyx/Core/SuperKeyStrings.swift
        Sources/Nyx/Core/InputSourceSelection.swift
        Sources/Nyx/Services/SessionActivity.swift
        Sources/Nyx/Services/SessionActivitySupport.swift
        Sources/Nyx/Services/EventTimestamp.swift
        Sources/Nyx/Services/OwnKeyEvent.swift
        Sources/Nyx/Services/ScrollWheelSupport.swift
        Sources/Nyx/Services/HorizontalWheelScrolling.swift
        Sources/Nyx/Services/SmoothScrollSupport.swift
        Sources/Nyx/Services/MouseAcceleration/MouseAccelerationSupport.swift
        Sources/Nyx/Services/FocusFollowsMouse/FocusFollowsMouseSupport.swift
        Sources/Nyx/Services/AssistiveKeyboard.swift
        Sources/Nyx/Services/Switcher/SwitcherModels.swift
        Sources/Nyx/Services/Switcher/WindowServerCaptureQueue.swift
        Sources/Nyx/Services/Switcher/SwitcherSupport.swift
        Sources/Nyx/Services/Switcher/SpaceHopSupport.swift
        Sources/Nyx/Services/Switcher/WindowUseOrder.swift
        Sources/Nyx/Services/Metrics/MetricFormat.swift
        Sources/Nyx/Services/Metrics/VMStatisticsDecoder.swift
        Sources/Nyx/Services/SystemMonitor/SMCClient.swift
        Sources/Nyx/Services/KeepAwakeAutomationSupport.swift
        Sources/Nyx/Services/SudoersSupport.swift
        Sources/Nyx/Services/Metrics/BatteryTimeSupport.swift
        Sources/Nyx/Services/Metrics/BatteryPowerSupport.swift
        Sources/Nyx/Services/BoundedProcessRunner.swift
        Sources/Nyx/Services/DetachedProcess.swift
        Sources/Nyx/Services/ShellSupport.swift
        Sources/Nyx/Services/Metrics/NetworkProcessSupport.swift
        Sources/Nyx/Services/Metrics/NetworkSampler.swift
        Sources/Nyx/Services/Metrics/NetworkAddressService.swift
        Sources/Nyx/Services/Metrics/SpeedTest.swift
        Sources/Nyx/Services/Metrics/PeripheralBatterySampler.swift
        Sources/Nyx/Services/Metrics/PeripheralBatterySupport.swift
        Sources/Nyx/Services/Metrics/DiskSupport.swift
        Sources/Nyx/Services/Metrics/MonitorSamplingPolicy.swift
        Sources/Nyx/Services/Metrics/USBDeviceSampler.swift
        Sources/Nyx/Services/Metrics/CPUCoreSampler.swift
        Sources/Nyx/Services/Metrics/MaxCapacityProbe.swift
        Sources/Nyx/Services/Metrics/TemperatureSensorSelector.swift
        Sources/Nyx/Services/Metrics/SustainedAlertGate.swift
        Sources/Nyx/Services/WindowLayout/WindowLayoutSupport.swift
        Sources/Nyx/Services/WindowLayout/WindowStageManagerSupport.swift
        Sources/Nyx/Core/WindowStageManagerStrings.swift
        Sources/Nyx/Services/WindowLayout/WindowGestureSupport.swift
        Sources/Nyx/Core/WindowDirectionalStrings.swift
        Sources/Nyx/Core/PointerDisplayStrings.swift
        Sources/Nyx/Core/GraphScaleStrings.swift
        Sources/Nyx/Core/NotchLowBatteryStrings.swift
        Sources/Nyx/Services/CleaningMode/CleaningUnlockCounter.swift
        Sources/Nyx/Services/CleaningMode/CleaningMouseReleaseGate.swift
        Sources/Nyx/Services/Display/ExtraBrightnessSupport.swift
        Sources/Nyx/Services/Display/BrightnessSupport.swift
        Sources/Nyx/Services/Display/LidDimmingSupport.swift
        Sources/Nyx/Services/Cleaner/CleanerSupport.swift
        Sources/Nyx/Services/Cleaner/CleanerPolicy.swift
        Sources/Nyx/Services/Cleaner/CleanerSchedule.swift
        Sources/Nyx/Services/Uninstall/UninstallerSupport.swift
        Sources/Nyx/Services/ManagedDownloads/WhatsAppDownloadSupport.swift
        Sources/Nyx/Core/SecureInputSupport.swift
        Sources/Nyx/Services/Calculator/CalculatorEngine.swift
        Tests/*.swift
        build/generated-tests/*.swift
    )
    TEST_OUTPUT_FILE_MAP="$TEST_OBJECT_DIR/output-file-map.json"
    write_swift_output_file_map "$TEST_OUTPUT_FILE_MAP" "$TEST_OBJECT_DIR" "${TEST_SOURCES[@]}"
    echo "▸ Building & running tests against $(basename "$SDK")…"
    swiftc -Onone -incremental -enable-batch-mode -j "$(sysctl -n hw.logicalcpu)" \
        -module-name NyxTests -output-file-map "$TEST_OUTPUT_FILE_MAP" \
        -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" \
        "${VM_STATISTICS_COMPAT_FLAGS[@]}" "${TEST_SOURCES[@]}" -o build/metrics-tests
    test_status=0
    ./build/metrics-tests "${TEST_ARGS[@]}" || test_status=$?
    if (( ${#TEST_ARGS} == 0 )); then
        ./Tests/PreferenceCleanupTests.sh || test_status=1
        ./Tests/UninstallSpacesTests.sh || test_status=1
        ./Tests/DeveloperInstallIsolationTests.sh || test_status=1
    fi
    discard_test_preferences || test_status=1
    exit $test_status
fi

echo "▸ Compiling ($BUILD_CONFIGURATION) against $(basename "$SDK")…"
APP_SOURCES=(Sources/Nyx/**/*.swift)
if (( ! DEV )); then
    # A release starts from an empty build directory, so nothing an earlier
    # build left behind (an old icon catalog, a staged bundle) can reach it.
    # Only the compiler's incremental records stay: they rebuild whatever
    # changed since, and a fresh checkout has none.
    find build -mindepth 1 -maxdepth 1 ! -name objects -exec rm -rf {} + 2>/dev/null || true
fi
APP_OBJECT_DIR="build/objects/$EXECUTABLE"
mkdir -p build "$APP_OBJECT_DIR"
APP_OUTPUT_FILE_MAP="$APP_OBJECT_DIR/output-file-map.json"
write_swift_output_file_map "$APP_OUTPUT_FILE_MAP" "$APP_OBJECT_DIR" "${APP_SOURCES[@]}"
# Without -j the driver compiles one file at a time, and without batch mode
# each file's compiler parses the whole module again: a clean release took a
# quarter of an hour. Batches share that work and run on every core, and the
# optimization stays per file, as before.
swiftc "${APP_OPTIMIZATION_FLAGS[@]}" -incremental -enable-batch-mode -j "$(sysctl -n hw.logicalcpu)" \
    -output-file-map "$APP_OUTPUT_FILE_MAP" \
    -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${VM_STATISTICS_COMPAT_FLAGS[@]}" "${HID_EVENT_SYSTEM_FLAGS[@]}" \
    "${BUILD_VARIANT_FLAGS[@]}" \
    "${APP_SOURCES[@]}" -o "build/$EXECUTABLE"

echo "▸ Compiling Now Playing adapter…"
swiftc -O -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" -emit-library \
    -module-name NyxNowPlaying \
    Sources/NowPlayingAdapter/NowPlayingAdapter.swift \
    Sources/NowPlayingAdapter/NowPlayingQueue.swift \
    Sources/NowPlayingAdapter/NowPlayingSelection.swift \
    Sources/Nyx/Services/Notch/NotchPlaybackSource.swift \
    Sources/Nyx/Services/Notch/NotchPlaybackCommand.swift \
    -o "build/$NOW_PLAYING_ADAPTER"

echo "▸ Generating app icon…"
swift Tools/MakeIcon.swift build/AppIcon.iconset
xattr -c -r build/AppIcon.iconset build/AppIcon.icns build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png 2>/dev/null || true
ACTOOL_BIN="$(xcrun --find actool 2>/dev/null || true)"
ICON_TMP="$(mktemp -d)"
ADAPTIVE_SKIP=""
if [[ -z "$ACTOOL_BIN" ]]; then
    ADAPTIVE_SKIP="actool not found (adaptive icons need Xcode 26+)"
else
    echo "▸ Compiling adaptive icon catalog…"
    # actool crashes on File Provider-synced paths, so compile a local copy.
    ditto "Resources/Brand/AppIcon.icon" "$ICON_TMP/AppIcon.icon"
    # Xcode 27 beta actool requires the --compile target directory to already exist.
    mkdir -p "$ICON_TMP/catalog"
    if "$ACTOOL_BIN" "$ICON_TMP/AppIcon.icon" \
            --compile "$ICON_TMP/catalog" \
            --app-icon AppIcon \
            --platform macosx \
            --target-device mac \
            --minimum-deployment-target 14.0 \
            --enable-on-demand-resources NO \
            --output-partial-info-plist "$ICON_TMP/partial-info.plist" \
            >"$ICON_TMP/actool.log" 2>&1 && [[ -s "$ICON_TMP/catalog/Assets.car" ]]; then
        mv "$ICON_TMP/catalog/Assets.car" build/Assets.car
    else
        ADAPTIVE_SKIP="actool could not compile the catalog"
    fi
fi
if [[ -n "$ADAPTIVE_SKIP" ]]; then
    cp "$ICON_TMP/actool.log" build/actool-failure.log 2>/dev/null || true
    echo "  adaptive icon skipped: $ADAPTIVE_SKIP (Dock falls back to AppIcon.icns)"
fi
echo "▸ Assembling and signing bundle…"
STAGE_TMP="$(mktemp -d)"
STAGE="$STAGE_TMP/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" \
    "$STAGE/Contents/Library/LaunchDaemons" "$STAGE/Contents/Library/LaunchServices"
cp "build/$EXECUTABLE" "$STAGE/Contents/MacOS/$EXECUTABLE"
mkdir -p "$STAGE/Contents/Frameworks"
cp "build/$NOW_PLAYING_ADAPTER" "$STAGE/Contents/Frameworks/$NOW_PLAYING_ADAPTER"
cp Resources/now-playing.pl "$STAGE/Contents/Resources/now-playing.pl"
cp Resources/agent-prices.json "$STAGE/Contents/Resources/agent-prices.json"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
for lproj in Resources/*.lproj(N); do
    cp -R "$lproj" "$STAGE/Contents/Resources/"
done
if (( DEV )); then
    # A distinct identity so the Developer build installs and runs next to the
    # official app, with its own permissions, preferences and login item.
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $APP_BUNDLE_ID" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE" "$STAGE/Contents/Info.plist"
    # Stamp the source commit + build time so the running dev app shows (in About)
    # exactly which code it was compiled from. Lets you verify it matches HEAD before
    # testing, instead of unknowingly running a stale build. Dev-only; never shipped.
    SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    [[ -n "$(git status --porcelain 2>/dev/null)" ]] && SHA="$SHA-dirty"
    /usr/libexec/PlistBuddy -c "Add :NyxBuildCommit string '$SHA · $(date '+%Y-%m-%d %H:%M')'" "$STAGE/Contents/Info.plist"
    echo "  stamped dev build: $SHA"
fi
printf 'APPL????' > "$STAGE/Contents/PkgInfo"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
if [[ -f build/Assets.car ]]; then
    cp build/Assets.car "$STAGE/Contents/Resources/Assets.car"
fi
if [[ -d Resources/Images ]]; then
    mkdir -p "$STAGE/Contents/Resources/Images"
    cp Resources/Images/* "$STAGE/Contents/Resources/Images/"
fi
xattr -c -r "$STAGE" 2>/dev/null || true

# Signing, in order of preference:
#   1. Developer ID Application — the real, Apple-issued identity used for
#      notarized releases. Signed with the hardened runtime (required for
#      notarization), the app's entitlements and a secure timestamp. Gives a
#      stable, team-based designated requirement, so permissions persist across
#      updates AND Gatekeeper shows no "unverified developer" warning.
#   2. "Nyx Utils Signing" — the legacy stable self-signed identity, kept
#      as a fallback so contributors without a Developer ID still get a constant
#      designated requirement across their local builds.
#   3. Ad-hoc — fresh clone with no identity at all.
DEVID="$(developer_id_identity)"
codesign_app() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$DEVID" "$target"
    elif legacy_identity_installed; then
        codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --sign - "$target"
    fi
}

codesign_now_playing_adapter() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$DEVID" "$target"
    elif legacy_identity_installed; then
        codesign --force --strip-disallowed-xattrs --identifier "$NOW_PLAYING_ADAPTER_ID" \
            --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --identifier "$NOW_PLAYING_ADAPTER_ID" --sign - "$target"
    fi
}

sign_bundle() {
    local bundle="$1"
    local executable="$bundle/Contents/MacOS/$EXECUTABLE"
    local adapter="$bundle/Contents/Frameworks/$NOW_PLAYING_ADAPTER"

    if [[ -n "$DEVID" ]]; then
        echo "  signing with Developer ID (hardened runtime): $DEVID"
    elif legacy_identity_installed; then
        echo "  signing with legacy self-signed identity: $LEGACY_IDENTITY"
    else
        echo "  signing ad-hoc (no identity installed — run Tools/setup-signing.sh)"
    fi
    [[ -f "$adapter" ]] && codesign_now_playing_adapter "$adapter"
    codesign_app "$bundle"

    # If local filesystem metadata invalidates the first signature, sign once
    # more. The installed Developer bundle is signed again after the final copy.
    if ! codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
        echo "  re-signing after filesystem metadata settled"
        xattr -c -r "$bundle" 2>/dev/null || true
        [[ -f "$adapter" ]] && codesign_now_playing_adapter "$adapter"
        codesign_app "$bundle"
    fi
    [[ -f "$executable" ]] && codesign --verify --strict "$executable"
    [[ -f "$adapter" ]] && codesign --verify --strict "$adapter"
    codesign --verify --deep --strict "$bundle"
}

sign_installed_bundle() {
    local bundle="$1"
    wait_for_install_metadata "$bundle"
    sign_bundle "$bundle"
}

sign_bundle "$STAGE"

process_is_running() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pgrep -f "/Contents/MacOS/$proc" >/dev/null 2>&1
    else
        pgrep -x "$proc" >/dev/null 2>&1
    fi
}

stop_process() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pkill -f "/Contents/MacOS/$proc" 2>/dev/null || true
    else
        pkill -x "$proc" 2>/dev/null || true
    fi
    for _ in {1..50}; do
        if ! process_is_running "$proc"; then
            return 0
        fi
        sleep 0.1
    done
    echo "✗ $proc is still running — quit it and retry" >&2
    return 1
}

wait_for_install_metadata() {
    local bundle="$1"
    local missing
    for _ in {1..50}; do
        missing=0
        while IFS= read -r file; do
            if ! xattr -p com.apple.provenance "$file" >/dev/null 2>&1; then
                missing=1
                break
            fi
        done < <(find "$bundle/Contents" -type f ! -path "*/_CodeSignature/*")
        if (( missing == 0 )); then
            return 0
        fi
        sleep 0.1
    done
}

# Installed development builds only need the copy in /Applications. Retaining
# another app in each checkout pollutes application search with stale builds.
if (( DEV )); then
    for old_bundle in "build/stage/$APP_NAME.app" "build/stage.noindex/$APP_NAME.app"; do
        if [[ -d "$old_bundle" ]]; then
            /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
                -u "$PWD/$old_bundle" >/dev/null 2>&1 || true
            rm -rf "$old_bundle"
        fi
    done
fi

if (( !DEV || !INSTALL )); then
    STAGE_DIRECTORY="build/stage"
    (( DEV )) && STAGE_DIRECTORY="build/stage.noindex"
    mkdir -p "$STAGE_DIRECTORY"
    BUILD_STAGE="$STAGE_DIRECTORY/$APP_NAME.app"
    rm -rf "$BUILD_STAGE"
    ditto --noextattr --noqtn "$STAGE" "$BUILD_STAGE"
    xattr -c -r "$BUILD_STAGE" 2>/dev/null || true
    if ! codesign --verify --deep --strict "$BUILD_STAGE" >/dev/null 2>&1; then
        if xattr -lr "$BUILD_STAGE" 2>/dev/null | grep -Eq 'com\.apple\.(FinderInfo|ResourceFork|provenance|fileprovider)'; then
            echo "  staging copy has local filesystem metadata; temp bundle was verified"
        else
            codesign --verify --deep --strict "$BUILD_STAGE"
        fi
    fi
    echo "✓ Bundle ready: $BUILD_STAGE"
fi

if (( INSTALL )); then
    echo "▸ Installing into /Applications…"
    stop_process "$EXECUTABLE"
    # Only an official install replaces the pre-rename official apps. The
    # Developer variant must coexist with them just as it does with Nyx.
    if (( ! DEV )); then
        for legacy in "Nyx Utils:NyxUtils"; do
            name="${legacy%%:*}"; proc="${legacy##*:}"
            if [[ -d "/Applications/$name.app" ]]; then
                stop_process "$proc"
                rm -rf "/Applications/$name.app"
                echo "  (legacy $name.app removed)"
            fi
        done
    fi
    INSTALL_DEST="/Applications/$APP_NAME.app"
    rm -rf "$INSTALL_DEST"
    ditto --noextattr --noqtn "$STAGE" "$INSTALL_DEST"
    sign_installed_bundle "$INSTALL_DEST"
    echo "✓ Installed: $INSTALL_DEST"
fi
