#!/usr/bin/env bash
# Build a portable ZenTao 12.5.3 zbox (Apache + PHP + MariaDB) for Linux aarch64.
# Layout matches easysoft/zbox: extract the tarball directly into /opt.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ZENTAOPMS_DIR:-$ROOT/zentaopms}"
ZBOX_SRC="${ZBOX_DIR:-$ROOT/zbox}"
OUT="${OUTPUT_DIR:-$ROOT/dist}"
VERSION="$(tr -d ' \r\n' < "$SRC/VERSION")"
PREFIX=/opt/zbox
BUILD="${BUILD_DIR:-/tmp/zbox-build}"
NPROC="$(nproc 2>/dev/null || echo 2)"

APACHE_VER="${APACHE_VER:-2.4.54}"
APR_VER="${APR_VER:-1.7.4}"
APR_UTIL_VER="${APR_UTIL_VER:-1.6.3}"
PHP_VER="${PHP_VER:-7.4.33}"
MARIA_VER="${MARIA_VER:-10.5.27}"

echo "==> Building zbox aarch64 for ZenTao $VERSION"
echo "    Apache $APACHE_VER  PHP $PHP_VER  MariaDB $MARIA_VER  jobs=$NPROC"
uname -m | grep -E 'aarch64|arm64' >/dev/null || {
  echo "ERROR: this script must run on aarch64 (got $(uname -m))" >&2
  exit 1
}
test -d "$ZBOX_SRC"
test -f "$SRC/VERSION"

mkdir -p "$BUILD" "$OUT" "$PREFIX"/{bin,app/htdocs,auth,data/mysql,etc/php,etc/mysql,etc/apache,logs,run/lib,tmp/php,tmp/apache,tmp/mysql}
chmod -R 777 "$PREFIX/tmp" "$PREFIX/logs"

fetch() {
  local url="$1" dest="$2"
  if [[ -f "$dest" && -s "$dest" ]]; then
    echo "    cached $(basename "$dest")"
    return 0
  fi
  echo "    download $url"
  curl -fL --retry 5 --retry-delay 3 -o "$dest.partial" "$url"
  mv "$dest.partial" "$dest"
}

# ---------------------------------------------------------------------------
# patchelf
# ---------------------------------------------------------------------------
if ! command -v patchelf >/dev/null 2>&1; then
  apt-get install -y patchelf
fi

# ---------------------------------------------------------------------------
# Apache
# ---------------------------------------------------------------------------
if [[ ! -x "$PREFIX/run/apache/httpd" && ! -x "$PREFIX/run/apache/httpd.full" ]]; then
  echo "==> Apache $APACHE_VER"
  cd "$BUILD"
  fetch "https://archive.apache.org/dist/httpd/httpd-${APACHE_VER}.tar.gz" "httpd-${APACHE_VER}.tar.gz"
  fetch "https://archive.apache.org/dist/apr/apr-${APR_VER}.tar.gz" "apr-${APR_VER}.tar.gz"
  fetch "https://archive.apache.org/dist/apr/apr-util-${APR_UTIL_VER}.tar.gz" "apr-util-${APR_UTIL_VER}.tar.gz"
  rm -rf "httpd-${APACHE_VER}"
  tar zxf "httpd-${APACHE_VER}.tar.gz"
  mkdir -p "httpd-${APACHE_VER}/srclib"
  tar zxf "apr-${APR_VER}.tar.gz" -C "httpd-${APACHE_VER}/srclib"
  tar zxf "apr-util-${APR_UTIL_VER}.tar.gz" -C "httpd-${APACHE_VER}/srclib"
  mv "httpd-${APACHE_VER}/srclib/apr-${APR_VER}" "httpd-${APACHE_VER}/srclib/apr"
  mv "httpd-${APACHE_VER}/srclib/apr-util-${APR_UTIL_VER}" "httpd-${APACHE_VER}/srclib/apr-util"
  cd "httpd-${APACHE_VER}"
  ./configure \
    --prefix="$PREFIX/run/apache" \
    --bindir="$PREFIX/run/apache" \
    --sbindir="$PREFIX/run/apache" \
    --sysconfdir="$PREFIX/etc/apache" \
    --libdir="$PREFIX/run/lib" \
    --with-mpm=prefork \
    --enable-mods-shared=all \
    --enable-so \
    --enable-ssl \
    --with-included-apr
  make -j"$NPROC"
  make install
fi

# ---------------------------------------------------------------------------
# MariaDB (compile; skip extra engines)
# ---------------------------------------------------------------------------
if [[ ! -x "$PREFIX/run/mysql/bin/mysqld" && ! -x "$PREFIX/run/mysql/mysqld" ]]; then
  echo "==> MariaDB $MARIA_VER"
  cd "$BUILD"
  fetch "https://archive.mariadb.org/mariadb-${MARIA_VER}/source/mariadb-${MARIA_VER}.tar.gz" "mariadb-${MARIA_VER}.tar.gz"
  rm -rf "mariadb-${MARIA_VER}"
  tar zxf "mariadb-${MARIA_VER}.tar.gz"
  cd "mariadb-${MARIA_VER}"
  cmake . \
    -DCMAKE_INSTALL_PREFIX="$PREFIX/run/mysql" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DWITH_DEBUG=0 \
    -DWITH_UNIT_TESTS=0 \
    -DWITH_WSREP=0 \
    -DWITH_EMBEDDED_SERVER=OFF \
    -DWITHOUT_TOKUDB=1 \
    -DPLUGIN_TOKUDB=NO \
    -DPLUGIN_MROONGA=NO \
    -DPLUGIN_ROCKSDB=NO \
    -DPLUGIN_SPIDER=NO \
    -DPLUGIN_OQGRAPH=NO \
    -DPLUGIN_CONNECT=NO \
    -DPLUGIN_COLUMNSTORE=NO \
    -DPLUGIN_PERFSCHEMA=NO \
    -DWITH_INNOBASE_STORAGE_ENGINE=1 \
    -DWITH_ARCHIVE_STORAGE_ENGINE=1 \
    -DWITH_BLACKHOLE_STORAGE_ENGINE=1 \
    -DWITH_MYISAM_STORAGE_ENGINE=1 \
    -DINSTALL_LIBDIR="$PREFIX/run/lib" \
    -DINSTALL_PLUGINDIR="$PREFIX/run/lib/mysql/plugin" \
    -DMYSQL_DATADIR="$PREFIX/data/mysql" \
    -DSYSCONFDIR="$PREFIX/etc/mysql" \
    -DMYSQL_UNIX_ADDR="$PREFIX/tmp/mysql/mysql.sock" \
    -DDEFAULT_CHARSET=utf8 \
    -DDEFAULT_COLLATION=utf8_general_ci \
    -DWITH_SSL=system \
    -DWITH_ZLIB=system
  make -j"$NPROC"
  make install
fi

# ---------------------------------------------------------------------------
# PHP 7.4 (NTS, Apache prefork module)
# ---------------------------------------------------------------------------
if [[ ! -f "$PREFIX/run/apache/modules/libphp7.so" ]]; then
  echo "==> PHP $PHP_VER"
  cd "$BUILD"
  fetch "https://www.php.net/distributions/php-${PHP_VER}.tar.gz" "php-${PHP_VER}.tar.gz"
  rm -rf "php-${PHP_VER}"
  tar zxf "php-${PHP_VER}.tar.gz"
  cd "php-${PHP_VER}"
  export APXS="$PREFIX/run/apache/apxs"
  ./configure \
    --prefix="$PREFIX/run/php" \
    --with-config-file-path="$PREFIX/etc/php" \
    --sysconfdir="$PREFIX/etc/apache" \
    --with-apxs2="$PREFIX/run/apache/apxs" \
    --with-openssl \
    --with-curl \
    --with-zlib \
    --with-bz2 \
    --with-mysqli \
    --with-pdo-mysql \
    --with-zip \
    --enable-gd \
    --with-jpeg \
    --with-freetype \
    --with-pic \
    --enable-mbstring \
    --enable-bcmath \
    --enable-sockets \
    --enable-opcache \
    --without-sqlite3 \
    --without-pdo-sqlite
  make -j"$NPROC"
  make install
fi

# ---------------------------------------------------------------------------
# Slim Apache
# ---------------------------------------------------------------------------
echo "==> Slim Apache"
mkdir -p "$PREFIX/run/newapache/modules" "$PREFIX/etc/newapache"
cd "$PREFIX/run/apache"
cp -a httpd apachectl htpasswd rotatelogs "$PREFIX/run/newapache/" 2>/dev/null || true
# Prefer bundled apachectl from zbox (hardcoded paths).
cp -a "$ZBOX_SRC/apachectl" "$PREFIX/run/newapache/apachectl"
chmod a+x "$PREFIX/run/newapache/apachectl" "$PREFIX/run/newapache/httpd"
cd "$PREFIX/run/apache/modules"
for mod in libphp7.so mod_authn_file.so mod_access_compat.so mod_deflate.so \
           mod_alias.so mod_authn_core.so mod_auth_basic.so mod_authz_core.so \
           mod_authz_host.so mod_authz_user.so mod_autoindex.so mod_dir.so \
           mod_env.so mod_expires.so mod_filter.so mod_log_config.so mod_mime.so \
           mod_rewrite.so mod_setenvif.so mod_unixd.so mod_ssl.so mod_macro.so \
           mod_headers.so mod_socache_shmcb.so; do
  [[ -f "$mod" ]] && cp -a "$mod" "$PREFIX/run/newapache/modules/"
done
cp "$PREFIX/etc/apache/mime.types" "$PREFIX/etc/newapache/"
cp "$ZBOX_SRC/httpd.zentao.conf" "$PREFIX/etc/newapache/httpd.conf"
rm -rf "$PREFIX/run/apache" "$PREFIX/etc/apache"
mv "$PREFIX/run/newapache" "$PREFIX/run/apache"
mv "$PREFIX/etc/newapache" "$PREFIX/etc/apache"

# ---------------------------------------------------------------------------
# Slim PHP
# ---------------------------------------------------------------------------
echo "==> Slim PHP"
mkdir -p "$PREFIX/run/newphp/lib"
cp -a "$PREFIX/run/php/bin/php" "$PREFIX/run/newphp/php"
OPC="$(find "$PREFIX/run/php" -name opcache.so | head -n1 || true)"
if [[ -n "$OPC" ]]; then
  cp -a "$OPC" "$PREFIX/run/newphp/lib/php_opcache.so"
fi
rm -rf "$PREFIX/run/php"
mv "$PREFIX/run/newphp" "$PREFIX/run/php"
# php.ini: drop ionCube (x86 only).
sed '/\[ioncube\]/,+1 s/^/;/' "$ZBOX_SRC/php.ini" > "$PREFIX/etc/php/php.ini"
cp "$ZBOX_SRC/curl-ca-bundle.crt" "$PREFIX/etc/php/curl-ca-bundle.crt"

# ---------------------------------------------------------------------------
# Slim MariaDB + init datadir
# ---------------------------------------------------------------------------
echo "==> Slim MariaDB"
cp -a "$ZBOX_SRC/my.cnf" "$PREFIX/etc/mysql/my.cnf"
if ! grep -q plugin_dir "$PREFIX/etc/mysql/my.cnf"; then
  sed -i '/^\[mysqld\]/a plugin_dir = /opt/zbox/run/lib/mysql/plugin' "$PREFIX/etc/mysql/my.cnf"
fi

MYSQL_BASE="$PREFIX/run/mysql"
if [[ -x "$MYSQL_BASE/bin/mysqld" ]]; then
  MYSQL_BIN="$MYSQL_BASE/bin"
else
  MYSQL_BIN="$MYSQL_BASE"
fi

# Initialize datadir before flattening (scripts/mysql_install_db needs full tree).
if [[ ! -d "$PREFIX/data/mysql/mysql" ]]; then
  echo "==> mysql_install_db"
  if [[ -x "$MYSQL_BASE/scripts/mysql_install_db" ]]; then
    "$MYSQL_BASE/scripts/mysql_install_db" \
      --defaults-file="$PREFIX/etc/mysql/my.cnf" \
      --basedir="$MYSQL_BASE" \
      --datadir="$PREFIX/data/mysql" \
      --user=nobody \
      --force \
      --skip-name-resolve || \
    "$MYSQL_BASE/scripts/mysql_install_db" \
      --defaults-file="$PREFIX/etc/mysql/my.cnf" \
      --basedir="$MYSQL_BASE" \
      --datadir="$PREFIX/data/mysql" \
      --user=nobody
  elif [[ -x "$MYSQL_BIN/mariadb-install-db" ]]; then
    "$MYSQL_BIN/mariadb-install-db" \
      --defaults-file="$PREFIX/etc/mysql/my.cnf" \
      --basedir="$MYSQL_BASE" \
      --datadir="$PREFIX/data/mysql" \
      --user=nobody
  else
    echo "ERROR: mysql_install_db not found" >&2
    exit 1
  fi
fi

mkdir -p "$PREFIX/run/newmysql/share/english"
cd "$MYSQL_BIN"
for b in my_print_defaults aria_chk mysql mysqld mysqld_safe mariadb mariadbd \
         mysqldump myisamchk mariadb-install-db mysql_install_db; do
  [[ -e "$b" ]] && cp -a "$b" "$PREFIX/run/newmysql/"
done
# zbox.php greps for mariadbd
if [[ ! -e "$PREFIX/run/newmysql/mariadbd" && -e "$PREFIX/run/newmysql/mysqld" ]]; then
  ln -s mysqld "$PREFIX/run/newmysql/mariadbd"
fi
cp -a "$ZBOX_SRC/mysql.server" "$PREFIX/run/newmysql/mysql.server"
chmod a+x "$PREFIX/run/newmysql/mysql.server"
if [[ -f "$MYSQL_BASE/share/english/errmsg.sys" ]]; then
  cp -a "$MYSQL_BASE/share/english/errmsg.sys" "$PREFIX/run/newmysql/share/english/"
elif [[ -f "$MYSQL_BASE/share/mariadb/english/errmsg.sys" ]]; then
  mkdir -p "$PREFIX/run/newmysql/share/mariadb/english"
  cp -a "$MYSQL_BASE/share/mariadb/english/errmsg.sys" "$PREFIX/run/newmysql/share/mariadb/english/"
  mkdir -p "$PREFIX/run/newmysql/share/english"
  cp -a "$MYSQL_BASE/share/mariadb/english/errmsg.sys" "$PREFIX/run/newmysql/share/english/"
fi
# Keep plugins
mkdir -p "$PREFIX/run/lib/mysql/plugin"
if [[ -d "$PREFIX/run/lib/mysql/plugin" ]]; then
  true
fi
if [[ -d "$MYSQL_BASE/lib/plugin" ]]; then
  cp -a "$MYSQL_BASE/lib/plugin/." "$PREFIX/run/lib/mysql/plugin/" || true
fi
rm -rf "$PREFIX/run/mysql"
mv "$PREFIX/run/newmysql" "$PREFIX/run/mysql"
# mysqld_safe looks for bin/
if [[ -f "$PREFIX/run/mysql/mysqld_safe" ]]; then
  sed -i 's|/opt/zbox/run/mysql/bin|/opt/zbox/run/mysql|g' "$PREFIX/run/mysql/mysqld_safe"
fi
rm -rf "$PREFIX/data/mysql/test" || true

# ---------------------------------------------------------------------------
# App files, control scripts, ZenTao source
# ---------------------------------------------------------------------------
echo "==> Install zbox scripts and ZenTao app"
cp -a "$ZBOX_SRC/zbox" "$PREFIX/zbox"
chmod a+x "$PREFIX/zbox"
cp -a "$ZBOX_SRC/zbox.php" "$PREFIX/bin/zbox.php"
cp -a "$ZBOX_SRC/xxd.php" "$PREFIX/bin/xxd.php" 2>/dev/null || true
cp -a "$ZBOX_SRC/README" "$PREFIX/README"
cp -a "$ZBOX_SRC/adminer" "$PREFIX/app/adminer"
cp -a "$ZBOX_SRC/adduser.sh" "$PREFIX/auth/adduser.sh"
chmod a+x "$PREFIX/auth/adduser.sh"
touch "$PREFIX/auth/users"
cp -a "$ZBOX_SRC/index.zentao.php" "$PREFIX/app/htdocs/index.php"

# Package ZenTao into app/zentao (reuse source builder if zip not present).
if [[ ! -d "$PREFIX/app/zentao/www" ]]; then
  if [[ -f "$OUT/ZenTaoPMS.${VERSION}.zip" ]]; then
    unzip -q -o "$OUT/ZenTaoPMS.${VERSION}.zip" -d /tmp/zt-src
    rm -rf "$PREFIX/app/zentao"
    mv /tmp/zt-src/zentaopms "$PREFIX/app/zentao"
  else
    OUTPUT_DIR="$OUT" ZENTAOPMS_DIR="$SRC" bash "$ROOT/scripts/build-source.sh"
    unzip -q -o "$OUT/ZenTaoPMS.${VERSION}.zip" -d /tmp/zt-src
    rm -rf "$PREFIX/app/zentao"
    mv /tmp/zt-src/zentaopms "$PREFIX/app/zentao"
  fi
fi
chmod -R 777 "$PREFIX/app/zentao/tmp" "$PREFIX/app/zentao/www/data" "$PREFIX/app/zentao/config"
chmod 777 "$PREFIX/app/zentao/www" "$PREFIX/app/zentao/module"

# ---------------------------------------------------------------------------
# Bundle shared libs + patchelf (portable /opt/zbox)
# ---------------------------------------------------------------------------
echo "==> Bundle libraries and patchelf"
LIBDIR="$PREFIX/run/lib"
mkdir -p "$LIBDIR"

INTERP_SRC="$(readelf -l /bin/ls | sed -n 's/.*interpreter: \(.*\)]/\1/p' | head -n1)"
INTERP_SRC="$(readlink -f "$INTERP_SRC")"
INTERP_NAME="ld-linux-aarch64.so.1"
# Must copy the real loader file, not a symlink. A relative symlink under
# /opt/zbox/run/lib would make every binary fail with "not found".
cp -L "$INTERP_SRC" "$LIBDIR/$INTERP_NAME"
chmod 755 "$LIBDIR/$INTERP_NAME"

copy_needed() {
  local file="$1"
  [[ -e "$file" ]] || return 0
  file -L "$file" 2>/dev/null | grep -q ELF || return 0
  ldd "$file" 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" != *"=>"* ]]; then
      continue
    fi
    local real
    real="$(echo "$line" | awk '{print $3}')"
    [[ -z "$real" || "$real" == "not" ]] && continue
    [[ -e "$real" ]] || continue
    local base
    base="$(basename "$real")"
    if [[ ! -f "$LIBDIR/$base" ]]; then
      cp -L "$real" "$LIBDIR/$base"
    fi
  done
}

# Collect ELF files
mapfile -t ELFS < <(find "$PREFIX/run" -type f \( -perm -111 -o -name '*.so*' \) | sort)
for f in "${ELFS[@]}"; do
  copy_needed "$f"
done
# Second pass for libs themselves
mapfile -t LIBS < <(find "$LIBDIR" -type f | sort)
for f in "${LIBS[@]}"; do
  copy_needed "$f"
done

# nss
for nss in /lib/aarch64-linux-gnu/libnss_dns.so.2 \
           /lib/aarch64-linux-gnu/libnss_files.so.2 \
           /lib/aarch64-linux-gnu/libnss_compat.so.2 \
           /lib/aarch64-linux-gnu/libresolv.so.2; do
  if [[ -e "$nss" ]]; then
    cp -L "$nss" "$LIBDIR/$(basename "$nss")" || true
  fi
done

is_loader() {
  local n
  n="$(basename "$1")"
  [[ "$n" == ld-linux* || "$n" == ld-*.so* ]]
}

mapfile -t ALL_ELF < <(find "$PREFIX/run" \( -type f -o -type l \) | sort)
for f in "${ALL_ELF[@]}"; do
  [[ -e "$f" ]] || continue
  is_loader "$f" && continue
  file -L "$f" 2>/dev/null | grep -q ELF || continue
  strip --strip-debug "$f" 2>/dev/null || true
  if readelf -l "$f" 2>/dev/null | grep -q 'Requesting program interpreter'; then
    patchelf --set-interpreter "$LIBDIR/$INTERP_NAME" "$f" 2>/dev/null || true
  fi
  patchelf --set-rpath "$LIBDIR" "$f" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# Symlinks in bin/
# ---------------------------------------------------------------------------
ln -sfn "$PREFIX/run/apache/apachectl" "$PREFIX/bin/apachectl"
ln -sfn "$PREFIX/run/apache/htpasswd"  "$PREFIX/bin/htpasswd"
ln -sfn "$PREFIX/run/apache/httpd"     "$PREFIX/bin/httpd"
ln -sfn "$PREFIX/run/mysql/mysqld_safe" "$PREFIX/bin/mysqld_safe"
ln -sfn "$PREFIX/run/mysql/mysql.server" "$PREFIX/bin/mysql.server"
ln -sfn "$PREFIX/run/mysql/mysql"      "$PREFIX/bin/mysql"
ln -sfn "$PREFIX/run/php/php"          "$PREFIX/bin/php"
chmod -R a+x "$PREFIX/run" "$PREFIX/zbox" "$PREFIX/bin"

# ---------------------------------------------------------------------------
# Init mysql password
# ---------------------------------------------------------------------------
echo "==> Set MariaDB root password"
getent group nogroup >/dev/null || groupadd nogroup
id nobody >/dev/null 2>&1 || useradd -g nogroup nobody
chown -R nobody "$PREFIX/data/mysql"
chmod -R 777 "$PREFIX/tmp" "$PREFIX/logs"

"$PREFIX/run/mysql/mysql.server" start --defaults-file="$PREFIX/etc/mysql/my.cnf" || true
sleep 5
MYSQL="$PREFIX/run/mysql/mysql"
if "$MYSQL" --defaults-file="$PREFIX/etc/mysql/my.cnf" -uroot -e "SELECT 1" >/dev/null 2>&1; then
  "$MYSQL" --defaults-file="$PREFIX/etc/mysql/my.cnf" -uroot < "$ZBOX_SRC/createuser.sql" || \
  "$MYSQL" --defaults-file="$PREFIX/etc/mysql/my.cnf" -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '123456'; CREATE USER IF NOT EXISTS 'zentao'@'localhost' IDENTIFIED BY '123456'; GRANT ALL ON zentao.* TO 'zentao'@'localhost'; FLUSH PRIVILEGES;"
elif "$MYSQL" --defaults-file="$PREFIX/etc/mysql/my.cnf" -uroot -p123456 -e "SELECT 1" >/dev/null 2>&1; then
  echo "    root password already set"
else
  echo "WARN: could not connect to MariaDB to set password"
  ls -l "$PREFIX/logs" || true
  cat "$PREFIX/logs/mysql_error.log" || true
fi
"$PREFIX/run/mysql/mysql.server" stop || true
sleep 2

# ---------------------------------------------------------------------------
# BUILD_INFO + tarball
# ---------------------------------------------------------------------------
{
  echo "Product: ZenTao PMS one-click zbox"
  echo "Version: $VERSION"
  echo "Arch:    aarch64 (ARM64)"
  echo "OS ABI:  Linux (built on Ubuntu 20.04 glibc)"
  echo "Apache:  $APACHE_VER"
  echo "PHP:     $PHP_VER"
  echo "MariaDB: $MARIA_VER"
  echo "Git tag: zentaopms_12.5.3_20210108"
  echo "Built:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Host:    $(uname -a)"
  echo
  echo "Install: tar -C /opt -xzf ZenTaoPMS.${VERSION}.zbox_arm64.tar.gz"
  echo "         (must extract directly into /opt)"
  echo "Start:   /opt/zbox/zbox start"
  echo "URL:     http://<host>/zentao/"
  echo "MySQL:   root / 123456"
  echo
  echo "Not included: ionCube (x86), xxd IM daemon (x86)."
} > "$PREFIX/BUILD_INFO.txt"

echo "==> Smoke binaries"
ls -l "$LIBDIR/$INTERP_NAME" "$PREFIX/run/php/php" "$PREFIX/run/apache/httpd"
file "$PREFIX/run/apache/httpd" "$PREFIX/run/php/php" "$PREFIX/run/mysql/mysqld"
readelf -l "$PREFIX/run/php/php" | grep interpreter || true
"$PREFIX/run/php/php" -v
"$PREFIX/run/apache/httpd" -v
"$PREFIX/run/mysql/mysqld" --version || "$PREFIX/run/mysql/mariadbd" --version

echo "==> Pack tarball"
# Drop build caches from prefix if any
rm -rf "$PREFIX/run/include" "$PREFIX/run/var" "$PREFIX/run/lib/pkgconfig" || true
tar -C /opt -czf "$OUT/ZenTaoPMS.${VERSION}.zbox_arm64.tar.gz" zbox
ls -lh "$OUT/ZenTaoPMS.${VERSION}.zbox_arm64.tar.gz"
echo "==> Done"
