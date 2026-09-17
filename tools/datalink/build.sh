#!/usr/bin/env bash
# Build this SGDK project via the shared builder (../../build.sh): out/cpc-player.bin
exec "$(dirname "$0")/../../build.sh" datalink "$@"
