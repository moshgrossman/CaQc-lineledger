#!/usr/bin/env bash
#
# Build the portable Windows/USB bundle for LineLedger.
#
# Produces dist/LineLedger-USB-<version>.zip containing:
#
#   LineLedger/
#     app/                  the application (vendor + compiled front-end)
#     php/                  official php.net Windows x64 build (NTS)
#     Data/                 .env and database.sqlite — the books
#     Start LineLedger.bat  what the user double-clicks
#     Try the demo.bat      the same, with practice books
#     first-run.php         writes the settings file on first start
#     README-USB.txt        instructions
#
# The bundle needs no installer, no admin rights and no internet.
# See docs/usb-portable.md for the why.
#
# Usage:  tools/build-usb-bundle.sh [--php-zip /path/to/php.zip]
#
set -euo pipefail

PHP_VERSION="8.5.9"
PHP_ZIP_NAME="php-${PHP_VERSION}-nts-Win32-vs17-x64.zip"
PHP_ZIP_URL="https://downloads.php.net/~windows/releases/${PHP_ZIP_NAME}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${ROOT}/build/usb"
STAGE="${BUILD}/LineLedger"
DIST="${ROOT}/dist"
PHP_ZIP_LOCAL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --php-zip) PHP_ZIP_LOCAL="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# The PHP binary used to build. Must match the PHP shipped to Windows so that
# composer's platform check and the generated database agree with the runtime.
PHP_BIN="${PHP_BIN:-php}"

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

say "Cleaning previous build"
rm -rf "${BUILD}"
mkdir -p "${STAGE}/app" "${STAGE}/Data" "${DIST}"

say "Copying application source"
# Only what the app needs at runtime. Notably absent: tests, node_modules,
# .git, the docker/ tree and the developer tooling — none of it ships.
for path in app bootstrap config database public resources routes storage \
            artisan composer.json composer.lock; do
    cp -R "${ROOT}/${path}" "${STAGE}/app/"
done

# Laravel needs these to exist and be writable, but never their contents.
find "${STAGE}/app/storage" -type f \
     ! -name '.gitignore' -delete 2>/dev/null || true
rm -f "${STAGE}/app/database/database.sqlite"

say "Applying the portable-mode patch"
# The one behavioural difference in this build, and it is unavoidable.
#
# LineLedger requires a new user to confirm their email address before the app
# will let them in. This bundle has no internet and no mail server, so that
# email can never arrive: a freshly registered user is parked on /email/verify
# forever and the software is unusable. (Found by testing the built bundle —
# the empty books were completely unreachable.)
#
# So the portable copy drops the MustVerifyEmail contract from the User model.
# Nothing else about authentication changes: passwords, two-factor and passkeys
# all still apply. This edits only the staged copy; the repository's own
# app/Models/User.php is never touched.
USER_MODEL="${STAGE}/app/app/Models/User.php"
before="$(grep -c 'implements MustVerifyEmail' "${USER_MODEL}" || true)"
if [[ "${before}" != "1" ]]; then
    echo "ERROR: app/Models/User.php no longer matches what the portable patch expects." >&2
    echo "       Upstream changed the class declaration. Re-check the patch before shipping." >&2
    exit 1
fi
sed -i 's/implements MustVerifyEmail, /implements /' "${USER_MODEL}"
sed -i '/^use Illuminate\\Contracts\\Auth\\MustVerifyEmail;$/d' "${USER_MODEL}"
grep -q 'MustVerifyEmail' "${USER_MODEL}" && {
    echo "ERROR: portable patch left a reference to MustVerifyEmail behind." >&2
    exit 1
}
"${PHP_BIN}" -l "${USER_MODEL}" >/dev/null

say "Installing PHP dependencies (production only)"
(
    cd "${STAGE}/app"
    COMPOSER_ALLOW_SUPERUSER=1 "${PHP_BIN}" "$(command -v composer)" install \
        --no-dev --no-interaction --prefer-dist --no-progress --no-scripts \
        --optimize-autoloader --classmap-authoritative
)

say "Removing libraries this bundle cannot use"
# The AWS SDK exists only to push attachments and backups to S3. This build is
# deliberately offline and keeps everything on the stick, so ~250 MB of service
# definitions for every AWS product would never be loaded.
#
# It has to be removed through composer, not with rm: the SDK registers a
# "files" autoload entry, so deleting the directory alone leaves the autoloader
# requiring a file that is gone, and the app dies on boot with a fatal error.
# (Found exactly that way — the first build of this script did use rm.)
#
# league/flysystem-aws-s3-v3 goes with it, because it depends on the SDK. The
# s3 disk stays defined in config/filesystems.php and is simply never
# instantiated: this bundle points every disk role at local storage.
#
# The bank-statement PDF reader (smalot/pdfparser) is deliberately KEPT: ~36 MB,
# and it is what reads a bank statement that arrives as a PDF.
(
    cd "${STAGE}/app"
    COMPOSER_ALLOW_SUPERUSER=1 "${PHP_BIN}" "$(command -v composer)" remove \
        league/flysystem-aws-s3-v3 aws/aws-sdk-php \
        --no-interaction --no-scripts --update-no-dev --no-progress \
        --optimize-autoloader --classmap-authoritative
)

# Per-package baggage that never runs. Note that fakerphp is NOT removed:
# LineLedger lists it as a normal dependency (not a dev one) and the demo-books
# seeder builds its sample company through model factories, which need it.
find "${STAGE}/app/vendor" -type d -name .git -prune -exec rm -rf {} + 2>/dev/null || true
find "${STAGE}/app/vendor" -type d \
     \( -iname tests -o -iname test -o -iname docs -o -iname examples \) \
     -prune -exec rm -rf {} + 2>/dev/null || true

say "Building the front-end"
(
    cd "${ROOT}"
    npm ci --silent
    npm run build
)
rm -rf "${STAGE}/app/public/build"
cp -R "${ROOT}/public/build" "${STAGE}/app/public/build"

say "Fetching PHP ${PHP_VERSION} for Windows"
mkdir -p "${STAGE}/php"
if [[ -n "${PHP_ZIP_LOCAL}" ]]; then
    cp "${PHP_ZIP_LOCAL}" "${BUILD}/${PHP_ZIP_NAME}"
else
    curl -fsSL "${PHP_ZIP_URL}" -o "${BUILD}/${PHP_ZIP_NAME}"
fi
unzip -q "${BUILD}/${PHP_ZIP_NAME}" -d "${STAGE}/php"
# The debug symbols and the development headers are not needed to run.
rm -rf "${STAGE}/php/dev" "${STAGE}/php"/*.pdb

say "Writing php.ini"
cat > "${STAGE}/php/php.ini" <<'INI'
; php.ini for the portable LineLedger build.
; Only what the application actually needs is enabled.
extension_dir = "ext"

extension=bcmath
extension=curl
extension=fileinfo
extension=gd
extension=intl
extension=mbstring
extension=openssl
extension=pdo_sqlite
extension=sqlite3
extension=zip

; A pay run with a year of history and a PDF render is the heaviest thing
; this app does; 512M leaves generous headroom on any machine.
memory_limit = 512M
max_execution_time = 300

; The books live on removable media, so uploads and posts stay modest.
upload_max_filesize = 32M
post_max_size = 32M

date.timezone = America/Toronto

; No opcache: the app runs from a USB stick and is started fresh each time,
; so the cache would be rebuilt on every run for no benefit.
INI

say "Creating the empty and demo books"
# Both databases are generated here, so the first run on Windows has nothing
# to migrate and starts instantly.
build_db() {
    local target="$1" seed="$2"
    (
        cd "${STAGE}/app"
        rm -f database/database.sqlite
        touch database/database.sqlite
        DB_CONNECTION=sqlite \
        DB_DATABASE="${STAGE}/app/database/database.sqlite" \
        APP_KEY="base64:$(head -c 32 /dev/urandom | base64)" \
        APP_ENV=production \
            "${PHP_BIN}" artisan migrate --force --no-interaction >/dev/null
        if [[ "${seed}" == "demo" ]]; then
            DB_CONNECTION=sqlite \
            DB_DATABASE="${STAGE}/app/database/database.sqlite" \
            APP_KEY="base64:$(head -c 32 /dev/urandom | base64)" \
            APP_ENV=local \
                "${PHP_BIN}" artisan db:seed --class=DemoCompanySeeder \
                    --force --no-interaction >/dev/null
        fi
        # The seeded demo account is marked confirmed for the same reason as the
        # patch above: there is no mail server here to confirm it with.
        DB_CONNECTION=sqlite DB_DATABASE="${STAGE}/app/database/database.sqlite" \
        APP_KEY="base64:$(head -c 32 /dev/urandom | base64)" APP_ENV=production \
            "${PHP_BIN}" artisan tinker --execute="\\App\\Models\\User::query()->whereNull('email_verified_at')->update(['email_verified_at' => now()]);" >/dev/null 2>&1 || true

        mv database/database.sqlite "${target}"
    )
}
build_db "${STAGE}/Data/database.sqlite" empty
build_db "${STAGE}/Data/demo-books.sqlite" demo

say "Writing the .env template"
# The real .env is written by the .bat on first run, because only then is the
# drive letter of the stick known. This template carries every setting that
# does not depend on where the stick is mounted.
cat > "${STAGE}/Data/env.template" <<'ENVT'
APP_NAME=LineLedger
APP_ENV=production
APP_DEBUG=false
APP_URL=http://127.0.0.1:8777

# Written once on first run and never regenerated. A key that changes on every
# start invalidates every session cookie and logs the user out at random.
APP_KEY=__APP_KEY__

DB_CONNECTION=sqlite
DB_DATABASE=__DB_PATH__
DB_FOREIGN_KEYS=true

# Everything runs in-process: no queue worker, no scheduler, no Redis.
QUEUE_CONNECTION=sync
CACHE_STORE=file
SESSION_DRIVER=file
SESSION_LIFETIME=525600

# Offline build: no outbound mail, no error reporting, no bot challenge.
MAIL_MAILER=log
LOG_CHANNEL=single
LOG_LEVEL=warning
BANK_IMPORT_AI_ENABLED=false
ENVT

say "Staging the launcher and instructions"
cp "${ROOT}/usb/Start LineLedger.bat" "${STAGE}/"
cp "${ROOT}/usb/Try the demo.bat"     "${STAGE}/"
cp "${ROOT}/usb/first-run.php"        "${STAGE}/"
cp "${ROOT}/usb/README-USB.txt"       "${STAGE}/"

say "Zipping"
VERSION="$(cat "${ROOT}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo dev)"
ZIP="${DIST}/LineLedger-USB-${VERSION}.zip"
rm -f "${ZIP}"
( cd "${BUILD}" && zip -rq "${ZIP}" LineLedger )

say "Done"
printf '  %s\n  %s\n' "${ZIP}" "$(du -h "${ZIP}" | cut -f1)"
