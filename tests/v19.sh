#!/bin/bash
set -euo pipefail

: "${TKL_TEST_RESULT:?TKL_TEST_RESULT must name the result file}"
: "${TKL_TEST_APP_PASS:?TKL_TEST_APP_PASS must contain the firstboot XOOPS password}"

APP_ROOT=/var/www/xoops
SOURCE_FILE=/usr/local/share/turnkey-xoops/source
BASE_URL=https://127.0.0.1

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

require_contains() {
    local text=$1
    local expected=$2
    local context=$3
    [[ $text == *"$expected"* ]] || fail "$context did not contain: $expected"
}

source_value() {
    local key=$1
    sed -n "s/^${key}=//p" "$SOURCE_FILE" | head -n 1
}

[[ -r $SOURCE_FILE ]] || fail "XOOPS source provenance is missing"
[[ -x /usr/local/bin/turnkey-xoops-update ]] || fail "XOOPS updater is not executable"

version=$(source_value version)
commit=$(source_value commit)
archive_sha256=$(source_value archive_sha256)
channel=$(source_value channel)
recorded_runtime=$(source_value runtime_version)

[[ $version = 2.7.3 ]] || fail "unexpected XOOPS source version"
[[ $commit = 00fff34c11fd4bee606e734d3bccf52d36fe0fda ]] \
    || fail "unexpected XOOPS source commit"
[[ $archive_sha256 = b49d935116352434a60e5dae93efce356d9e5f360ad92bc72dcc69d7ab82b8cb ]] \
    || fail "unexpected XOOPS archive digest"
[[ $channel = official-xoops-core27-stable ]] || fail "unexpected XOOPS channel"

runtime=$(php -r 'define("XOOPS_ROOT_PATH", dirname($argv[1], 2)); require $argv[1]; echo XOOPS_VERSION;' \
    "$APP_ROOT/include/version.php")
[[ $runtime = "$recorded_runtime" ]] || fail "runtime version differs from provenance"
[[ $runtime == "XOOPS $version"* ]] || fail "runtime version differs from release tag"

[[ $(stat -c '%U:%G:%a' "$APP_ROOT/mainfile.php") = root:www-data:440 ]] \
    || fail "XOOPS mainfile permissions are incorrect"
[[ $(stat -c '%U:%G:%a' /var/local/lib/xoops/data/data/secure.php) = root:www-data:440 ]] \
    || fail "XOOPS database credential permissions are incorrect"

systemctl is-active --quiet apache2 || fail "Apache is not active"
systemctl is-active --quiet mariadb || fail "MariaDB is not active"
apache2ctl configtest 2>&1 | grep -q 'Syntax OK' || fail "Apache configuration is invalid"

home_page=$(curl --insecure -fsSL --max-time 30 "$BASE_URL/")
require_contains "$home_page" "TurnKey XOOPS" "XOOPS HTTPS home page"
require_contains "$home_page" "Welcome to TurnKey XOOPS" "XOOPS welcome block"

adminer_page=$(curl --insecure -fsSL --max-time 30 https://127.0.0.1:12322/)
require_contains "$adminer_page" "Adminer" "Adminer HTTPS endpoint"

cookie=$(mktemp)
pass_file=$(mktemp)
trap 'rm -f "$cookie" "$pass_file"' EXIT
chmod 0600 "$cookie" "$pass_file"
printf '%s' "$TKL_TEST_APP_PASS" > "$pass_file"
curl_args=(--insecure -fsS --max-time 30 -c "$cookie" -b "$cookie")

curl "${curl_args[@]}" "$BASE_URL/user.php" -o /dev/null
curl "${curl_args[@]}" "$BASE_URL/user.php" \
    --data-urlencode 'uname=admin' \
    --data-urlencode "pass@$pass_file" \
    --data-urlencode 'op=login' \
    -o /dev/null

admin_page=$(curl "${curl_args[@]}" "$BASE_URL/admin.php")
require_contains "$admin_page" "Control Panel" "XOOPS administrator login"

block_form=$(curl "${curl_args[@]}" \
    "$BASE_URL/modules/system/admin.php?fct=blocksadmin&op=add")
require_contains "$block_form" "Blocks Administration" "XOOPS block administration"
token=$(sed -n \
    "s/.*name=['\"]XOOPS_TOKEN_REQUEST['\"][^>]*value=['\"]\([^'\"]*\)['\"].*/\1/p" \
    <<<"$block_form" | head -n 1)
[[ -n $token ]] || fail "XOOPS block form did not contain a request token"

fixture_title='TurnKey XOOPS acceptance block'
fixture_content='XOOPS content create and read verified'
curl "${curl_args[@]}" "$BASE_URL/modules/system/admin.php" \
    --data-urlencode "XOOPS_TOKEN_REQUEST=$token" \
    --data-urlencode 'fct=blocksadmin' \
    --data-urlencode 'op=save' \
    --data-urlencode 'bid=0' \
    --data-urlencode 'block_type=C' \
    --data-urlencode 'mid=0' \
    --data-urlencode 'func_num=0' \
    --data-urlencode 'func_file=' \
    --data-urlencode 'show_func=' \
    --data-urlencode 'edit_func=' \
    --data-urlencode 'template=' \
    --data-urlencode 'dirname=' \
    --data-urlencode 'name=' \
    --data-urlencode 'side=0' \
    --data-urlencode 'weight=0' \
    --data-urlencode 'visible=1' \
    --data-urlencode 'modules[]=-1' \
    --data-urlencode 'groups[]=1' \
    --data-urlencode 'groups[]=2' \
    --data-urlencode 'groups[]=3' \
    --data-urlencode "title=$fixture_title" \
    --data-urlencode "content_block=$fixture_content" \
    --data-urlencode 'c_type=H' \
    --data-urlencode 'bcachetime=0' \
    -o /dev/null

public_fixture=$(curl --insecure -fsSL --max-time 30 "$BASE_URL/?v19-acceptance=1")
require_contains "$public_fixture" "$fixture_title" "public XOOPS content"
require_contains "$public_fixture" "$fixture_content" "public XOOPS content"

db_fixture=$(mysql --batch --skip-column-names "$DB_NAME" --execute="
    SELECT CONCAT(title, '|', content)
    FROM xoops_newblocks
    WHERE title='$fixture_title'
    ORDER BY bid DESC LIMIT 1;")
[[ $db_fixture = "$fixture_title|$fixture_content" ]] \
    || fail "XOOPS database did not retain the created content"

password_scheme=$(mysql --batch --skip-column-names "$DB_NAME" --execute="
    SELECT LEFT(pass, 1) FROM xoops_users WHERE uname='admin';")
[[ $password_scheme = '$' ]] || fail "firstboot did not store a modern admin password hash"

check_output=$(turnkey-xoops-update --check)
latest=$(awk -F= '$1 == "latest" { print $2 }' <<<"$check_output")
candidate=$(awk -F= '$1 == "candidate" { print $2 }' <<<"$check_output")
tag=$(awk -F= '$1 == "tag" { print $2 }' <<<"$check_output")
[[ $latest =~ ^2\.7\.[0-9]+$ ]] || fail "updater returned an invalid stable version"
[[ $candidate =~ ^[0-9a-f]{40}$ ]] || fail "updater returned an invalid commit"
[[ $tag = "v$latest" ]] || fail "updater tag and version differ"
require_contains "$check_output" "channel=official-xoops-core27-stable" "XOOPS updater"

apply_plan=$(turnkey-xoops-update --apply --dry-run)
require_contains "$apply_plan" "mode=apply-dry-run" "XOOPS updater plan"
require_contains "$apply_plan" "target=$latest" "XOOPS updater plan"
require_contains "$apply_plan" "candidate=$candidate" "XOOPS updater plan"
require_contains "$apply_plan" "verified=official-xoops-release-tag" "XOOPS updater plan"
require_contains "$apply_plan" "upgrade_path=/upgrade/" "XOOPS updater plan"

echo "PASS: XOOPS HTTPS admin login, custom block create/read, MariaDB, and updater"
echo "version=$version runtime=$runtime commit=$commit"
cat > "$TKL_TEST_RESULT" <<EOF
package_source=official XOOPS Core 2.7.3 at $commit
installed_version=XOOPS release $version, runtime $runtime
runtime_checks=HTTPS admin login, custom block create and public read, MariaDB, Adminer, and firstboot credentials passed
updater_command=turnkey-xoops-update --check; turnkey-xoops-update --apply --dry-run
updater_result=target v$latest at verified official release commit $candidate
updater_channel=official XOOPS Core 2.7 stable
integrity_evidence=XOOPS source archive SHA256 $archive_sha256 bound to commit $commit
EOF
