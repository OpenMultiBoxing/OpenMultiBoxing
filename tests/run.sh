#!/bin/bash
# Runs tests/*_test.tcl (or the given ones) with the Tcl/Tk/twapi bundled in a release binary:
# the binary sources a $runner_as found next to it, here tests/runner.tcl.
# OMB_EXE: the binary to use, else the latest release's, cached in tests/bin/ (the cached one when offline).
# OMB_TEST_APP: the .tcl under test, else ../$name.tcl. GITHUB_TOKEN, if set, for the latest release lookup.
name=OpenMultiBoxing
repo=OpenMultiBoxing/OpenMultiBoxing
exe_glob='OpenMultiBoxing-v*.exe'
# name of its built-in script
runner_as=OpenMultiBoxing.tcl
set -e
dir=$(cd "$(dirname "$0")" && pwd -W)
app=${OMB_TEST_APP:-$dir/../$name.tcl}
exe=$OMB_EXE
# another app's binary would start that app for real
if [ -n "$exe" ] && [[ "$(basename "$exe")" != $exe_glob ]]; then
    echo "Ignoring OMB_EXE=$exe (not $exe_glob)"
    exe=
fi
if [ -z "$exe" ]; then
    # authenticated in CI: the anonymous API rate limit is shared by the runners
    auth=()
    [ -n "$GITHUB_TOKEN" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    url=$(curl -fsS "${auth[@]}" https://api.github.com/repos/$repo/releases/latest |
        grep -o '"browser_download_url": *"[^"]*\.zip"' | grep -o 'https://[^"]*') || url=
    exe=$(ls "$dir"/bin/$exe_glob 2>/dev/null | head -1)
    # the zip and its binary have the same name: download when the cached one isn't the latest
    if [ -n "$url" ] && [ "$(basename "$exe" .exe)" != "$(basename "$url" .zip)" ]; then
        echo "Downloading $url"
        mkdir -p "$dir/bin"
        curl -fsSL -o "$dir/bin/release.zip" "$url"
        rm -f "$dir"/bin/$exe_glob
        unzip -o -q "$dir/bin/release.zip" "$exe_glob" -d "$dir/bin"
        rm "$dir/bin/release.zip"
        exe=$(ls "$dir"/bin/$exe_glob 2>/dev/null | head -1)
    fi
    if [ -z "$exe" ]; then
        echo "No $exe_glob binary (offline, or removed by the antivirus?)"
        exit 1
    fi
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$exe" "$work/"
cp "$dir/runner.tcl" "$work/$runner_as"
tests=("$@")
[ ${#tests[@]} -eq 0 ] && tests=("$dir"/*_test.tcl)
rc=0
for t in "${tests[@]}"; do
    OMB_TEST_APP=$app OMB_TEST_SCRIPT=$t OMB_TEST_OUT=$work/out.txt timeout 60 "$work/$(basename "$exe")" || rc=1
    cat "$work/out.txt"
done
exit $rc
