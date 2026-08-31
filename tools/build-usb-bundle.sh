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
#                                   [--previous-manifest /path/to/manifest.txt]
#
# Given the previous build's manifest, it also writes an UPDATE PACK: a small
# zip holding only the files that changed, so a stick already carrying
# LineLedger can be brought up to date in a couple of minutes instead of being
# rebuilt from scratch. Testing happens on a paid-by-the-minute computer;
# thirty minutes of unpacking per test cycle is the real cost of this project.
#
set -euo pipefail

# The PHP branch shipped inside the bundle, NOT a full version number.
#
# It used to be pinned to an exact patch release ("8.5.9") with a hand-written
# URL. That broke the build: php.net keeps only the current patch release of a
# branch in the releases directory and moves the previous one to archives/, so
# the pinned URL 404'd the moment 8.5.10 came out. The build now asks php.net
# which patch release is current, and verifies what it downloads against the
# checksum php.net publishes for it.
PHP_BRANCH="8.5"
PHP_FLAVOUR="nts-vs17-x64"
PHP_RELEASES_JSON="https://downloads.php.net/~windows/releases/releases.json"
PHP_RELEASES_BASE="https://downloads.php.net/~windows/releases"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${ROOT}/build/usb"
STAGE="${BUILD}/LineLedger"
DIST="${ROOT}/dist"
PHP_ZIP_LOCAL=""
PREV_MANIFEST=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --php-zip) PHP_ZIP_LOCAL="$2"; shift 2 ;;
        --previous-manifest) PREV_MANIFEST="$2"; shift 2 ;;
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

say "Making SQLite settings reachable from the settings file"
# The 500 after "Create organization" was this, from his error log:
#
#   SQLSTATE[HY000]: General error: 14 unable to open database file
#     (insert into "accounts" ... 1200 Undeposited Funds ...)
#
# SQLite error 14 is CANTOPEN — it could not open A file. Not the books file
# itself, which it had been writing happily for minutes: one of the small
# working files SQLite creates beside it (the rollback journal) or in the
# system temp folder (a statement journal) while a write is in flight. On a
# USB stick, with an antivirus filter watching every create and delete, those
# are exactly the operations that fail intermittently — which is why it died
# on a different account each attempt.
#
# Laravel's SQLite connector already knows how to set the three pragmas that
# make this far less likely, but upstream's config wires them to null with no
# way to set them. This makes them read the settings file, so the portable
# build can turn them on and a server install is unaffected (unset = null =
# exactly today's behaviour).
DB_CONFIG="${STAGE}/app/config/database.php"
for pragma in busy_timeout journal_mode synchronous; do
    if ! grep -q "'${pragma}' => null," "${DB_CONFIG}"; then
        echo "ERROR: config/database.php no longer has '${pragma}' => null." >&2
        echo "       Upstream changed the sqlite connection; re-check this patch." >&2
        exit 1
    fi
    sed -i "s/'${pragma}' => null,/'${pragma}' => env('DB_$(echo "${pragma}" | tr '[:lower:]' '[:upper:]')'),/" "${DB_CONFIG}"
done
"${PHP_BIN}" -l "${DB_CONFIG}" >/dev/null

say "Removing the online password check"
# Registering a user made the machine call out to api.pwnedpasswords.com. It
# is in his log, from the offline bundle:
#
#   cURL error 60: SSL certificate ... for https://api.pwnedpasswords.com/...
#
# Laravel's uncompromised() rule checks a new password against a public
# breach database over the internet. On a machine with no network it stalls
# and then fails; on his it got as far as TLS, which means the books machine
# was talking to the internet — something README-USB.txt promises this build
# never does. The promise wins: the rule goes.
#
# Only that one rule. Length, mixed case, letters, numbers and symbols all
# still apply, so passwords are no weaker in any way a stick full of books
# cares about.
PROVIDER="${STAGE}/app/app/Providers/AppServiceProvider.php"
if ! grep -q '\->uncompromised()' "${PROVIDER}"; then
    echo "ERROR: AppServiceProvider no longer calls ->uncompromised()." >&2
    echo "       Upstream moved the password rules; re-check before shipping," >&2
    echo "       or the offline build will again phone out on every sign-up." >&2
    exit 1
fi
sed -i '/->uncompromised()$/d' "${PROVIDER}"
grep -q '\->uncompromised()' "${PROVIDER}" && {
    echo "ERROR: the password rule is still there." >&2; exit 1; }
"${PHP_BIN}" -l "${PROVIDER}" >/dev/null

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
#
# laravel/tinker goes too. It is an interactive PHP console for a developer at a
# terminal — there is no terminal here, and the one build-time use of it has
# been rewritten as plain SQL. It drags in psy/psysh and nikic/php-parser:
# ~1,450 files that would otherwise be created one by one on the USB stick.
(
    cd "${STAGE}/app"
    COMPOSER_ALLOW_SUPERUSER=1 "${PHP_BIN}" "$(command -v composer)" remove \
        league/flysystem-aws-s3-v3 aws/aws-sdk-php laravel/tinker \
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

say "Trimming the file count"
# WHY THIS STEP EXISTS, and why it is worth the risk of deleting things:
#
# Unzipping the bundle onto a USB stick took over half an hour on the test
# machine. That is not the zip's size — 96 MB writes in a couple of minutes.
# It is the COUNT. Windows creates each file separately: allocate, write the
# directory entry, flush, hand it to the antivirus filter, move on. On removable
# media that is roughly a fixed cost per file, so 20,000 files cost 20,000 times
# it no matter how small they are.
#
# Measured on this repository, a production install is ~39,000 files. Removing
# the AWS SDK takes out ~11,300 of them and the tests/docs sweep above another
# ~9,400, which still leaves ~18,000 shipping to the stick. Everything below is
# a file that is never read while the application is running.
#
# Nothing here is guessed: the boot check at the end of this step actually runs
# the application, and the build FAILS if any of these deletions broke it.

count_files() { find "$1" -type f 2>/dev/null | wc -l | tr -d ' '; }
before_trim="$(count_files "${STAGE}/app")"

# 1. Package metadata and developer configuration. Read by humans and by CI,
#    never by PHP at runtime.
find "${STAGE}/app/vendor" -type f \
     \( -iname '*.md' -o -iname '*.rst' \
        -o -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'AUTHORS*' \
        -o -iname 'CHANGELOG*' -o -iname 'UPGRAD*' -o -iname 'SECURITY*' \
        -o -iname '.editorconfig' -o -iname '.gitattributes' \
        -o -iname '.gitignore' -o -iname '*.dist' \
        -o -iname 'phpunit.xml*' -o -iname 'phpstan*' -o -iname 'psalm*' \
        -o -iname 'infection*' -o -iname '.php-cs-fixer*' -o -iname 'Makefile' \) \
     -delete 2>/dev/null || true
find "${STAGE}/app/vendor" -type d \
     \( -name '.github' -o -name '.circleci' -o -name 'benchmarks' \
        -o -name 'Tests' -o -name 'Test' -o -name 'fixtures' -o -name 'Fixtures' \) \
     -prune -exec rm -rf {} + 2>/dev/null || true

# 2. Translations for languages this bundle will never display. LineLedger runs
#    here in English for a Quebec business, so English and French stay and the
#    other ~130 locales go. Carbon alone ships over a thousand of these.
#
#    Locale files are named like "en.php", "fr_CA.json", "validators.de.xlf" —
#    the sweep keeps anything whose language part is en or fr and deletes the
#    rest, and only ever inside a directory that is clearly a language store.
prune_locales() {
    local dir="$1"
    [[ -d "${dir}" ]] || return 0
    find "${dir}" -type f \
         \( -name '*.php' -o -name '*.json' -o -name '*.xlf' -o -name '*.yaml' \) \
         ! -iname 'en*' ! -iname 'fr*' \
         ! -iname '*.en.*' ! -iname '*.fr.*' \
         -delete 2>/dev/null || true
}
prune_locales "${STAGE}/app/vendor/nesbot/carbon/src/Carbon/Lang"
while IFS= read -r -d '' d; do prune_locales "${d}"; done \
    < <(find "${STAGE}/app/vendor" -type d \
             \( -name 'translations' -o -name 'lang' -o -name 'Lang' \) -print0)

# 3. Empty directories left behind by the sweeps. They cost a directory entry
#    each on the stick for nothing.
find "${STAGE}/app/vendor" -type d -empty -delete 2>/dev/null || true

after_trim="$(count_files "${STAGE}/app")"
printf '    %s files before, %s after (%s removed)\n' \
       "${before_trim}" "${after_trim}" "$((before_trim - after_trim))"

say "Checking the application still boots after trimming"
# The whole point: prove it, do not hope. If any deletion above took something
# the app actually needs, this fails the build here rather than on his stick.
(
    cd "${STAGE}/app"
    DB_CONNECTION=sqlite DB_DATABASE=":memory:" \
    APP_KEY="base64:$(head -c 32 /dev/urandom | base64)" APP_ENV=production \
        "${PHP_BIN}" artisan route:list --json >/dev/null
)

say "Removing the country-switcher banner"
# The login screen carries a guest banner: "You're viewing the US site. Want the
# CA version instead?" with a "Go to Canada" button. On a normal deployment it
# moves people between the two hosted sites. In this bundle it is a trap: the
# button navigates out of the local app to books.lineledger.ca, which on the
# test machine returned "503 Service Unavailable" — and offline it can never be
# anything else.
#
# It renders from one line in the guest auth layout, so one line is removed.
AUTH_LAYOUT="${STAGE}/app/resources/views/layouts/auth/simple.blade.php"
if ! grep -q '<x-geo-banner />' "${AUTH_LAYOUT}"; then
    echo "ERROR: the geo banner include was not found in the auth layout." >&2
    echo "       Upstream moved or renamed it; re-check before shipping, or the" >&2
    echo "       offline build will again offer a button that leaves the app." >&2
    exit 1
fi
sed -i '/<x-geo-banner \/>/d' "${AUTH_LAYOUT}"
grep -q '<x-geo-banner />' "${AUTH_LAYOUT}" && { echo "ERROR: banner still present." >&2; exit 1; }

say "Normalising component filenames"
# Livewire's generator prefixes single-file components with a high-voltage
# emoji (see config/livewire.php, make_command.emoji). It is decorative:
# Livewire strips it when resolving a component name, so "⚡index.blade.php"
# and "index.blade.php" are the same component. 280 view files carry it.
#
# The sweep covers vendor as well: Livewire ships two of these as test
# fixtures, which never render, but leaving them would mean the bundle still
# contains filenames an unzip tool could mangle.
#
# It is stripped here because this bundle travels as a .zip onto Windows, and
# any unzip tool that mishandles non-ASCII filenames will rename those files.
# The app then fails in a confusing way: the login page works, the password is
# accepted, and every screen after it dies with "Unable to find component".
# Reproduced exactly that way while verifying the first published Release.
#
# Done in the staged copy only. Renaming them in the repository would fork 280
# files from upstream over pure cosmetics, and every future sync would conflict
# on all of them; doing it at build time keeps working as upstream adds more.
renamed=0
while IFS= read -r -d '' f; do
    dir="$(dirname "${f}")"
    base="$(basename "${f}")"
    mv "${f}" "${dir}/${base#⚡}"
    renamed=$((renamed + 1))
done < <(find "${STAGE}/app" -name '⚡*' -print0)

# Fail loudly rather than silently shipping the risk again: zero matches means
# upstream changed the convention and this step has quietly become dead code.
if [[ "${renamed}" -eq 0 ]]; then
    echo "ERROR: no emoji-prefixed component files were found to rename." >&2
    echo "       Upstream has changed the naming convention, so this step is" >&2
    echo "       now dead code and the Windows filename risk needs re-checking." >&2
    exit 1
fi
printf '    %s component files renamed\n' "${renamed}"

say "Building the front-end"
# Built inside the staged copy, not the repository root, because
# resources/css/app.css imports vendor/livewire/flux/dist/flux.css — so the
# build only resolves where composer has actually installed vendor/. The stage
# is that place; a clean checkout's root is not.
#
# (CI caught this: the first version built at the root and failed with
# "Can't resolve '../../vendor/livewire/flux/dist/flux.css'". It passed locally
# only because that working copy happened to have a vendor/ directory left
# over from an earlier install.)
cp "${ROOT}/package.json" "${ROOT}/package-lock.json" "${ROOT}/vite.config.js" "${STAGE}/app/"
(
    cd "${STAGE}/app"
    npm ci --silent
    npm run build
)
# node_modules is a build-time dependency only; it must not reach the stick.
rm -rf "${STAGE}/app/node_modules"
rm -f "${STAGE}/app/package.json" "${STAGE}/app/package-lock.json" "${STAGE}/app/vite.config.js"

say "Fetching PHP ${PHP_BRANCH} for Windows"
mkdir -p "${STAGE}/php"
if [[ -n "${PHP_ZIP_LOCAL}" ]]; then
    PHP_ZIP_NAME="$(basename "${PHP_ZIP_LOCAL}")"
    cp "${PHP_ZIP_LOCAL}" "${BUILD}/${PHP_ZIP_NAME}"
    printf '    using the local copy %s\n' "${PHP_ZIP_NAME}"
else
    # Ask php.net what the current build of this branch is, rather than
    # guessing a filename that stops existing when the next patch ships.
    curl -fsSL "${PHP_RELEASES_JSON}" -o "${BUILD}/releases.json"

    read -r PHP_ZIP_NAME PHP_ZIP_SHA256 < <(
        "${PHP_BIN}" -r '
            $j = json_decode(file_get_contents($argv[1]), true);
            $b = $argv[2]; $f = $argv[3];
            if (! isset($j[$b][$f]["zip"]["path"])) {
                fwrite(STDERR, "php.net lists no ".$f." build for PHP ".$b."\n");
                exit(1);
            }
            echo $j[$b][$f]["zip"]["path"], " ",
                 ($j[$b][$f]["zip"]["sha256"] ?? ""), "\n";
        ' "${BUILD}/releases.json" "${PHP_BRANCH}" "${PHP_FLAVOUR}"
    )
    printf '    php.net currently ships %s\n' "${PHP_ZIP_NAME}"

    # The current release lives in the releases directory; anything older has
    # been moved to archives/. Try both, so a build kicked off while php.net is
    # mid-rotation still finds the file it was just told about.
    if ! curl -fsSL "${PHP_RELEASES_BASE}/${PHP_ZIP_NAME}" -o "${BUILD}/${PHP_ZIP_NAME}"; then
        curl -fsSL "${PHP_RELEASES_BASE}/archives/${PHP_ZIP_NAME}" -o "${BUILD}/${PHP_ZIP_NAME}"
    fi

    # Verify it against the checksum php.net publishes. This bundle is handed to
    # someone who runs it with no network and no way to check it himself, so a
    # silently truncated or substituted download must never reach the stick.
    if [[ -n "${PHP_ZIP_SHA256}" ]]; then
        echo "${PHP_ZIP_SHA256}  ${BUILD}/${PHP_ZIP_NAME}" | sha256sum -c - >/dev/null
        printf '    checksum verified\n'
    else
        echo "ERROR: php.net published no checksum for ${PHP_ZIP_NAME}." >&2
        exit 1
    fi
fi
unzip -q "${BUILD}/${PHP_ZIP_NAME}" -d "${STAGE}/php"
# The debug symbols and the development headers are not needed to run.
rm -rf "${STAGE}/php/dev" "${STAGE}/php"/*.pdb

say "Writing php.ini"
cat > "${STAGE}/php/php.ini" <<'INI'
; php.ini for the portable LineLedger build.
; Only what the application actually needs is enabled.
extension_dir = "ext"

; bcmath is NOT listed: on Windows it is compiled into php8.dll rather than
; shipped as ext\php_bcmath.dll, so "extension=bcmath" only produces a startup
; warning — the first thing the user sees. Verified against the shipped build:
; php8.dll exports bcadd/bcsub/bcmul/bcdiv/bcscale/bcpow, so the functions are
; present either way. Every extension below DOES have a matching DLL.
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

; Opcache. This was previously switched OFF here, with the reasoning that the
; bundle "starts fresh each time so the cache would be rebuilt for no benefit".
; That reasoning was wrong, and it is the single biggest cause of the app being
; slow on a stick.
;
; The bundle does not run one PHP process per request. "artisan serve" starts
; ONE long-lived server process that then handles every request until the black
; window is closed. Without opcache that process re-reads and re-compiles
; several hundred PHP files off the USB stick on EVERY page load. With opcache
; it compiles each file once, keeps the compiled form in memory, and every later
; request skips the stick entirely.
;
; Verified: with these settings the built-in server reports opcache_enabled
; true, and its hit counter climbs with each request.
opcache.enable=1
; The built-in server runs under the "cli-server" SAPI. Modern PHP enables
; opcache there regardless of this setting, but the one-off artisan commands the
; launcher runs (view:cache) are plain CLI and do benefit, so it is on.
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
; The app is ~5,000 PHP files after trimming; this leaves room to grow.
opcache.max_accelerated_files=20000
; Never re-check a file's timestamp. Safe here in a way it is not on a server:
; nothing on the stick edits the application while it runs, and every launch
; starts a fresh process anyway.
opcache.validate_timestamps=0
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
        #
        # Done with a direct SQL update rather than "artisan tinker" for two
        # reasons: tinker drags in psy/psysh and nikic/php-parser (~1,450 files
        # that would otherwise have to ship to the stick), and the old call
        # ended in "|| true", so if it ever failed the bundle shipped with an
        # unconfirmed demo account and nobody would have known.
        "${PHP_BIN}" -r '
            $db = new PDO("sqlite:".$argv[1]);
            $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $n = $db->exec("UPDATE users SET email_verified_at = CURRENT_TIMESTAMP
                            WHERE email_verified_at IS NULL");
            fwrite(STDERR, "    ".$n." account(s) marked confirmed\n");
        ' "${STAGE}/app/database/database.sqlite"

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

# A Quebec business. Region drives the legal-document links; without it the app
# derives region from the hostname and settles on the US site.
APP_REGION=CA

# Written once on first run and never regenerated. A key that changes on every
# start invalidates every session cookie and logs the user out at random.
APP_KEY=__APP_KEY__

DB_CONNECTION=sqlite
DB_DATABASE=__DB_PATH__
DB_FOREIGN_KEYS=true

# Written for a USB stick, not a server. See "Making SQLite settings reachable"
# in tools/build-usb-bundle.sh for the error these answer.
#
# TRUNCATE: SQLite's default is to CREATE the rollback journal beside the books
# at the start of every write and DELETE it at the end. On removable media,
# with an antivirus filter holding a handle on each file as it appears, that
# churn is where "unable to open database file" comes from. TRUNCATE creates
# the file once and empties it instead of deleting it — same crash safety, a
# fraction of the file operations.
DB_JOURNAL_MODE=TRUNCATE
# Wait up to 15 seconds for a lock rather than failing instantly. The page
# polls itself every few seconds and the built-in server handles one request at
# a time, so a long write does have things queued behind it.
DB_BUSY_TIMEOUT=15000
# Still flushes at every transaction; skips the extra flush at each checkpoint.
# The safety that matters on a stick — surviving being yanked — is unchanged.
DB_SYNCHRONOUS=NORMAL

# Everything runs in-process: no queue worker, no scheduler, no Redis.
QUEUE_CONNECTION=sync
CACHE_STORE=file
SESSION_DRIVER=file
SESSION_LIFETIME=525600

# Offline build: no outbound mail, no error reporting, no bot challenge.
MAIL_MAILER=log
LOG_CHANNEL=single
# debug, not warning. When the app fails it shows a bare "500 Server Error" and
# nothing else; the log is the only place the real reason is written, and at
# "warning" most of the useful detail never reaches it. There is no privacy cost
# — the file never leaves the stick — and "Show the error log.bat" opens it.
LOG_LEVEL=debug
BANK_IMPORT_AI_ENABLED=false
ENVT

say "Staging the launcher and instructions"
cp "${ROOT}/usb/Start LineLedger.bat" "${STAGE}/"
cp "${ROOT}/usb/Try the demo.bat"     "${STAGE}/"
cp "${ROOT}/usb/first-run.php"        "${STAGE}/"
cp "${ROOT}/usb/README-USB.txt"       "${STAGE}/"
cp "${ROOT}/usb/Show the error log.bat" "${STAGE}/"

# Stamp the build number into the launcher, so the black window always names
# the build that is running. Guessing which build is on a stick has cost a test
# cycle before.
BUNDLE_VERSION="$(cat "${ROOT}/usb/BUNDLE-VERSION" | tr -d '[:space:]')"
if ! grep -q '__BUNDLE_VERSION__' "${STAGE}/Start LineLedger.bat"; then
    echo "ERROR: the launcher has no __BUNDLE_VERSION__ placeholder to stamp." >&2
    exit 1
fi
sed -i "s/__BUNDLE_VERSION__/${BUNDLE_VERSION}/" "${STAGE}/Start LineLedger.bat"

say "Clearing build-machine caches"
# Anything Laravel generated while this script ran (it boots the app to migrate
# and to check the trim) is thrown away. The caches that matter are built on the
# stick itself by the launcher, where the paths are the machine's own.
rm -rf "${STAGE}/app/bootstrap/cache"/*.php
find "${STAGE}/app/storage/framework/views" -name '*.php' -delete 2>/dev/null || true

say "Listing what is on the stick"
# A checksum of every file that lands on the stick, kept as a Release asset.
# The NEXT build downloads it and can then say exactly what changed — which is
# what makes a small update pack possible instead of a full re-unpack.
#
# The books themselves are deliberately absent: an update must never overwrite
# what he has typed.
MANIFEST="${DIST}/manifest.txt"
(
    cd "${STAGE}"
    find . -type f ! -name '*.sqlite' -printf '%P\n' | LC_ALL=C sort | \
        while IFS= read -r f; do
            printf '%s  %s\n' "$(sha256sum "${f}" | cut -d' ' -f1)" "${f}"
        done
) > "${MANIFEST}"
printf '    %s files listed\n' "$(wc -l < "${MANIFEST}")"

if [[ -n "${PREV_MANIFEST}" && -s "${PREV_MANIFEST}" ]]; then
    say "Building the update pack"
    # Everything that differs from the previous build, and nothing else.
    PACK="${BUILD}/update"
    rm -rf "${PACK}"
    mkdir -p "${PACK}/files"

    # Old and new as "path<tab>checksum" lookups.
    #
    # sed rather than awk on purpose: awk's field splitting would rebuild the
    # line and quietly mangle "Start LineLedger.bat" and every other path with
    # a space in it. (It did exactly that on the first run of this.)
    to_tsv() {
        sed -E 's/^([0-9a-f]{64})  (.*)$/\2\t\1/' "$1" | LC_ALL=C sort
    }
    to_tsv "${PREV_MANIFEST}" > "${BUILD}/old.tsv"
    to_tsv "${MANIFEST}"      > "${BUILD}/new.tsv"

    # Changed or added: in the new list with a different checksum, or not in
    # the old list at all.
    LC_ALL=C join -t$'\t' -j1 -v1 "${BUILD}/new.tsv" "${BUILD}/old.tsv" \
        | cut -f1 > "${BUILD}/changed.txt"
    LC_ALL=C join -t$'\t' -j1 "${BUILD}/new.tsv" "${BUILD}/old.tsv" \
        | awk -F'\t' '$2 != $3 {print $1}' >> "${BUILD}/changed.txt"
    LC_ALL=C sort -u -o "${BUILD}/changed.txt" "${BUILD}/changed.txt"

    # Gone: in the old list, absent from the new one.
    LC_ALL=C join -t$'\t' -j1 -v1 "${BUILD}/old.tsv" "${BUILD}/new.tsv" \
        | cut -f1 > "${PACK}/removed.txt"

    changed_count="$(wc -l < "${BUILD}/changed.txt")"
    removed_count="$(wc -l < "${PACK}/removed.txt")"
    printf '    %s changed or new, %s removed\n' "${changed_count}" "${removed_count}"

    while IFS= read -r f; do
        [[ -n "${f}" ]] || continue
        mkdir -p "${PACK}/files/$(dirname "${f}")"
        cp "${STAGE}/${f}" "${PACK}/files/${f}"
    done < "${BUILD}/changed.txt"

    # Two things the applier has to know about, because getting either wrong
    # would cost him a test cycle or his books.
    #
    # 1. Compiled screens. If any template changed, the ones already compiled
    #    on the stick have to go, or he tests the old screen and reports that
    #    nothing changed.
    if grep -qE '^app/resources/views/|\.blade\.php$' "${BUILD}/changed.txt"; then
        echo yes > "${PACK}/recompile-screens.flag"
    fi
    # 2. The books' structure. The stick's books are built and migrated HERE, at
    #    build time — nothing migrates them on the stick. So a build that
    #    changes a migration cannot be delivered as an update at all, and the
    #    pack has to say so rather than half-apply and corrupt his books.
    if grep -q '^app/database/migrations/' "${BUILD}/changed.txt" \
       || grep -q '^app/database/migrations/' "${PACK}/removed.txt"; then
        echo yes > "${PACK}/full-bundle-required.flag"
    fi

    cp "${ROOT}/usb/Apply update.bat"      "${PACK}/"
    cp "${ROOT}/usb/apply-env-updates.php" "${PACK}/"
    "${PHP_BIN}" "${ROOT}/tools/write-update-instructions.php" \
        "${PACK}" "${BUNDLE_VERSION}" "${BUILD}/changed.txt" \
        "${ROOT}/usb/BUNDLE-NOTES.txt"

    UPDATE_ZIP="${DIST}/LineLedger-update-to-b${BUNDLE_VERSION}.zip"
    rm -f "${UPDATE_ZIP}"
    ( cd "${PACK}" && zip -rq "${UPDATE_ZIP}" . )
    printf '    %s (%s)\n' "${UPDATE_ZIP##*/}" "$(du -h "${UPDATE_ZIP}" | cut -f1)"
else
    say "No previous manifest — full bundle only"
    printf '    Nothing to compare against, so no update pack this time.\n'
fi

say "Packing the program into one file"
# THIS IS THE FIX FOR "THE UNZIP TOOK OVER HALF AN HOUR".
#
# Windows Explorer's built-in zip extractor is the slowest way to write many
# small files that exists on the machine: it goes through the shell one file at
# a time, and every one of them is handed to the antivirus filter on the way.
# Onto a USB stick that is minutes per thousand files.
#
# So the download no longer contains thousands of loose files. The whole
# application goes into ONE file, program.tar.gz, and the download holds about
# a hundred entries instead of fifteen thousand — nearly all of them the PHP
# runtime, which stays loose so that php.exe is available before anything is
# unpacked. Explorer's job becomes copying one big file, which is the thing a
# USB stick is actually good at.
#
# Unpacking happens ONCE, on the stick, done by the launcher with tar.exe —
# part of Windows since 2018, and it writes files directly with no shell and no
# per-file overhead. .tar.gz rather than .zip on purpose: it is tar's own
# format, so there is no question of whether the Windows copy can read it, and
# php.exe can unpack it too if tar is somehow missing.
#
# -h dereferences symlinks, so the archive holds real files even if a future
# dependency ships one — Windows cannot be relied on to recreate a link.
( cd "${STAGE}" && tar -czhf program.tar.gz app && rm -rf app )
printf '    program.tar.gz is %s\n' "$(du -h "${STAGE}/program.tar.gz" | cut -f1)"

say "Zipping"
VERSION="$(cat "${ROOT}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo dev)"
BUNDLE="$(cat "${ROOT}/usb/BUNDLE-VERSION" 2>/dev/null | tr -d '[:space:]' || echo 0)"
ZIP="${DIST}/LineLedger-USB-${VERSION}-b${BUNDLE}.zip"
rm -f "${ZIP}"
( cd "${BUILD}" && zip -rq "${ZIP}" LineLedger )

say "Done"
printf '  %s\n  %s\n  %s entries in the download\n' \
       "${ZIP}" "$(du -h "${ZIP}" | cut -f1)" "$(unzip -l "${ZIP}" | tail -1 | awk '{print $2}')"
