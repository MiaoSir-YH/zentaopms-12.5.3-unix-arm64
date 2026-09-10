#!/usr/bin/env bash
# Package ZenTao PMS 12.5.3 source zip (architecture-independent).
# Mirrors Makefile targets `common` + `package`. External XuanXuan git archive
# is omitted because XUANPATH/XUANVERSION were not committed on this tag;
# in-tree xuanxuan/ overlay is still merged.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ZENTAOPMS_DIR:-$ROOT/zentaopms}"
OUT="${OUTPUT_DIR:-$ROOT/dist}"
VERSION="$(tr -d ' \r\n' < "$SRC/VERSION")"
STAGE="$(mktemp -d /tmp/zentaopms-src.XXXXXX)"
PKG="$STAGE/zentaopms"

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

echo "==> Source tree: $SRC"
echo "==> Version: $VERSION"
test -f "$SRC/VERSION"

mkdir -p "$PKG" "$OUT"

copy_tree() {
  local from="$1" to="$2"
  mkdir -p "$to"
  cp -a "$from"/. "$to"/
}

copy_tree "$SRC/bin"      "$PKG/bin"
copy_tree "$SRC/config"   "$PKG/config"
rm -f "$PKG/config/my.php"
copy_tree "$SRC/db"       "$PKG/db"
copy_tree "$SRC/doc"      "$PKG/doc"
rm -rf "$PKG/doc/phpdoc" "$PKG/doc/doxygen"
copy_tree "$SRC/framework" "$PKG/framework"
copy_tree "$SRC/lib"      "$PKG/lib"
copy_tree "$SRC/module"   "$PKG/module"
copy_tree "$SRC/sdk"      "$PKG/sdk"
copy_tree "$SRC/www"      "$PKG/www"
rm -rf "$PKG/www/data"
mkdir -p "$PKG/www/data/upload" "$PKG/www/data/notify"
mkdir -p "$PKG/tmp/cache" "$PKG/tmp/extension" "$PKG/tmp/log" "$PKG/tmp/model"
cp "$SRC/VERSION" "$PKG/"

if [[ -f "$PKG/www/install.php.tmp" ]]; then
  mv "$PKG/www/install.php.tmp" "$PKG/www/install.php"
fi
if [[ -f "$PKG/www/upgrade.php.tmp" ]]; then
  mv "$PKG/www/upgrade.php.tmp" "$PKG/www/upgrade.php"
fi

# In-tree xuanxuan overlay (IM-related files shipped in this tag).
if [[ -d "$SRC/xuanxuan" ]]; then
  echo "==> Merging in-tree xuanxuan overlay"
  cp -a "$SRC/xuanxuan/config/." "$PKG/config/" 2>/dev/null || true
  cp -a "$SRC/xuanxuan/module/." "$PKG/module/" 2>/dev/null || true
  cp -a "$SRC/xuanxuan/www/."    "$PKG/www/"    2>/dev/null || true
fi

# Combine / minify front-end (YUI optional).
if command -v php >/dev/null 2>&1; then
  mkdir -p "$HOME/bin/yuicompressor/build"
  if [[ ! -f "$HOME/bin/yuicompressor/build/yuicompressor.jar" ]]; then
    curl -fsSL -o "$HOME/bin/yuicompressor/build/yuicompressor.jar" \
      "https://github.com/yui/yuicompressor/releases/download/v2.4.8/yuicompressor-2.4.8.jar" \
      || true
  fi
  mkdir -p "$PKG/tools"
  cp -a "$SRC/tools/." "$PKG/tools/"
  (cd "$PKG/tools" && php ./minifyfront.php) || echo "WARN: minifyfront.php failed, keeping unminified assets"
  rm -rf "$PKG/tools"
else
  echo "WARN: php not found, skipping minify"
fi

# Traditional Chinese from Simplified, if cconv exists.
if command -v php >/dev/null 2>&1 && command -v cconv >/dev/null 2>&1; then
  mkdir -p "$PKG/tools"
  cp "$SRC/tools/cn2tw.php" "$PKG/tools/"
  (cd "$PKG/tools" && php cn2tw.php) || echo "WARN: cn2tw.php failed"
  rm -rf "$PKG/tools"
fi

find "$PKG" -name .gitkeep -exec rm -rf {} + 2>/dev/null || true
find "$PKG" -type d -name tests -exec rm -rf {} + 2>/dev/null || true

# index.html in every directory except www root.
while IFS= read -r -d '' dir; do
  touch "$dir/index.html"
done < <(find "$PKG" -type d -print0)
rm -f "$PKG/www/index.html"

chmod -R 777 "$PKG/tmp" "$PKG/www/data" "$PKG/config"
chmod 777 "$PKG/module" "$PKG/www"
chmod a+rx "$PKG/bin/"* 2>/dev/null || true
mkdir -p "$PKG/config/ext"
for module in "$PKG/module"/*; do
  [[ -d "$module" ]] || continue
  mkdir -p "$module/ext"
done
find "$PKG" -type d -name ext -exec chmod -R 777 {} + 2>/dev/null || true

cat > "$PKG/BUILD_INFO.txt" <<EOF
Product: ZenTao PMS source package
Version: $VERSION
Git tag: zentaopms_12.5.3_20210108
Built:   $(date -u +%Y-%m-%dT%H:%M:%SZ)
Host:    $(uname -a)
Note:    PHP source, architecture-independent.
         External XuanXuan git archive was not available on this tag;
         in-tree xuanxuan overlay was merged.
EOF

(cd "$STAGE" && zip -rq -9 "$OUT/ZenTaoPMS.${VERSION}.zip" zentaopms)
echo "==> Wrote $OUT/ZenTaoPMS.${VERSION}.zip"
ls -lh "$OUT/ZenTaoPMS.${VERSION}.zip"
