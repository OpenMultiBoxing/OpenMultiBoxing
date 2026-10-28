#!/bin/bash
# Runs tests/*_test.tcl (or the given ones) with the Tcl/Tk/twapi bundled in a release binary:
# the binary sources a $runner_as found next to it, here tests/runner.tcl.
# OMB_EXE: the binary to use, else the one in tests/bin/, downloaded from the latest release the first time.
# OMB_TEST_APP: the .tcl under test, else ../$name.tcl.
name=OpenMultiBoxing
repo=OpenMultiBoxing/OpenMultiBoxing
exe_glob='OpenMultiBoxing-v*.exe'
# name of its built-in script
runner_as=OpenMultiBoxing.tcl
set -e
dir=$(cd "$(dirname "$0")" && pwd -W)
app=${OMB_TEST_APP:-$dir/../$name.tcl}
exe=${OMB_EXE:-$(ls "$dir"/bin/$exe_glob 2>/dev/null | head -1)}
if [ -z "$exe" ]; then
    url=$(curl -fsS https://api.github.com/repos/$repo/releases/latest |
        grep -o '"browser_download_url": *"[^"]*\.zip"' | grep -o 'https://[^"]*')
    echo "Downloading $url"
    mkdir -p "$dir/bin"
    curl -fsSL -o "$dir/bin/release.zip" "$url"
    unzip -o -q "$dir/bin/release.zip" "$exe_glob" -d "$dir/bin"
    rm "$dir/bin/release.zip"
    exe=$(ls "$dir"/bin/$exe_glob | head -1)
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
