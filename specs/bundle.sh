#!/usr/bin/env bash
# Concatenates the five spec modules into a single file that Quint can parse.
# Quint resolves `import X.*` only within the same source file; this script
# produces that unified file.
#
# Usage:  bash specs/bundle.sh
# Output: specs/galexp.qnt

set -e
OUT="specs/galexp.qnt"

cat specs/types.qnt \
    specs/galaxy.qnt \
    specs/empire.qnt \
    specs/combat.qnt \
    specs/turn.qnt \
    > "$OUT"

echo "Bundled → $OUT"
