#!/bin/zsh
set -euo pipefail

developer_frameworks="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
developer_libraries="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [[ -d "$developer_frameworks/Testing.framework" ]]; then
  exec swift test --jobs 1 \
    -Xswiftc -F -Xswiftc "$developer_frameworks" \
    -Xlinker -rpath -Xlinker "$developer_frameworks" \
    -Xlinker -rpath -Xlinker "$developer_libraries" \
    "$@"
fi

exec swift test --jobs 1 "$@"
