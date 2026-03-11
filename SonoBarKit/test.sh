#!/bin/bash
# Run SonoBarKit tests with Swift Testing framework support.
# Required on CommandLineTools-only environments (no Xcode) because
# the Testing framework isn't auto-discovered by swift-tools-version 5.9.
set -euo pipefail
cd "$(dirname "$0")"
swift test \
    -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
    -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
    "$@"
