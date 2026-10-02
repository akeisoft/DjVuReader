#!/bin/bash
# Builds DjVuLibre from ThirdParty/DjVuLibre the same way the Xcode target does,
# then builds and runs the C bridge self-test against Tests/Fixtures/sample.djvu.
# Works on macOS (clang) and Linux (gcc/clang); no Xcode project needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DJVU="ThirdParty/DjVuLibre"
OUT="build/bridge-test"
CXX="${CXX:-c++}"
CC="${CC:-cc}"
JOBS="$( (sysctl -n hw.ncpu || nproc) 2>/dev/null || echo 4)"

if [ "$(uname)" = "Darwin" ]; then
    LINK_LIBS="-lc++ -liconv -framework CoreFoundation"
else
    LINK_LIBS="-lstdc++ -lpthread -lm"
fi

mkdir -p "$OUT/libdjvu"
echo "==> Compiling DjVuLibre ($(ls "$DJVU"/libdjvu/*.cpp | wc -l | tr -d ' ') files)"
ls "$DJVU"/libdjvu/*.cpp | xargs -P "$JOBS" -I{} sh -c \
    "$CXX -std=gnu++17 -O2 -w -DHAVE_CONFIG_H=1 -DNDEBUG=1 -I$DJVU/config -c {} -o $OUT/libdjvu/\$(basename {} .cpp).o"
rm -f "$OUT/libdjvulibre.a"
ar rcs "$OUT/libdjvulibre.a" "$OUT"/libdjvu/*.o

echo "==> Compiling the bridge and the test"
"$CC" -std=gnu17 -Wall -Wextra -O2 -I"$DJVU" -c Sources/Engine/DjVuBridge.c -o "$OUT/DjVuBridge.o"
"$CC" -std=gnu17 -Wall -Wextra -O2 -c Tests/BridgeTests/bridge_test.c -o "$OUT/bridge_test.o"
"$CXX" "$OUT/bridge_test.o" "$OUT/DjVuBridge.o" "$OUT/libdjvulibre.a" $LINK_LIBS -o "$OUT/bridge_test"

"$OUT/bridge_test" Tests/Fixtures/sample.djvu "$DJVU/osi"
