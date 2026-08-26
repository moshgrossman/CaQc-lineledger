# Portable (USB) build

A build of LineLedger that runs from a USB stick on any 64-bit Windows PC.
Nothing is installed, no administrator rights are needed, and no network
connection is used. It exists for people who do not have a computer of their
own and work from a machine they cannot change.

Build it with:

```bash
tools/build-usb-bundle.sh
```

The result is `dist/LineLedger-USB-<version>-b<bundle>.zip` (~100 MB). The
`<bundle>` number comes from `usb/BUNDLE-VERSION` and is stamped into the
launcher, so the black window always names the build that is running.

Inside it: the official php.net Windows build of PHP loose in `php/`, an empty
set of books and a second set of practice books in `Data/`, the `.bat` files —
and the application itself as a single `program.tar.gz`.

## How it differs from a server install

| | Server install | Portable build |
|---|---|---|
| Database | MySQL | SQLite file on the stick |
| Queue | worker process | `sync` — jobs run inline |
| Scheduler | cron | not run |
| Mail | SMTP | `log` — nothing is sent |
| Object storage | S3 optional | local only; AWS SDK removed |
| Email verification | required | **not required** (see below) |

## Why the application ships as one packed file

Extracting the first published bundle onto a USB stick took **over half an
hour** on the test machine. That is not the size — 100 MB writes in a couple of
minutes. It is the file count. Windows Explorer's zip extractor creates each
file through the shell, one at a time, and hands every one to the antivirus
filter on the way; on removable media that is a roughly fixed cost per file,
and the bundle was about 17,200 of them.

Two things were done about it.

**The count came down.** A plain production install of this application is
39,134 files; removing the AWS SDK and the tests/docs sweep already took the
bundle to ~17,200. Dropping `laravel/tinker` (with `psy/psysh` and
`nikic/php-parser` behind it) and sweeping package metadata, remaining test
directories and the ~130 locales this bundle will never display brings it to
**13,304** — measured, not estimated. Every deletion is of something never read
at runtime, and the build then boots the application (`artisan route:list`) and
fails if any of it was needed.

**The rest stopped being loose files.** `app/` is packed into one
`program.tar.gz`, so the download holds a little over a hundred entries —
nearly all of them the PHP runtime — instead of seventeen thousand. Explorer copies one big file, which is what a stick is good
at. The launcher unpacks it once with `tar.exe` — part of Windows since 2018,
writing files directly with no shell overhead — then deletes the archive.
`php/` deliberately stays loose so `php.exe` exists before anything is
unpacked; if `tar.exe` is ever missing, PHP unpacks the archive itself through
`PharData`.

`.tar.gz` rather than `.zip` because it is tar's own format: no question of
whether the bundled Windows copy can read it.

## Why opcache is on, and the caches are built on the stick

The first build switched opcache **off**, reasoning that a bundle "starts fresh
each time so the cache would be rebuilt for no benefit". That was wrong, and it
was the single biggest cause of the app feeling slow.

`artisan serve` does not start a process per request. It starts **one**
long-lived server that handles every request until the window is closed.
Without opcache that process re-read and re-compiled several hundred PHP files
off the stick on every page load. Measured locally on an SSD, with everything
else equal, a page went from ~0.36 s to ~0.16 s; on slow removable media the
gap is far wider.

`validate_timestamps=0` is safe here in a way it is not on a server: nothing
edits the application while it runs.

The Blade and route caches are built by the launcher **on the stick**, on first
run, not at build time. Blade's compiled filename is a hash of the view's path
relative to the base path — which uses backslashes on Windows and forward
slashes on Linux, so a cache built here would be silently ignored there and
every one of the ~400 screens would compile again on first use anyway. Building
it on the stick takes about a minute, once, and is verifiably the right cache
for that machine.

## The two deliberate changes

**The AWS SDK is removed at build time**, through `composer remove` rather
than by deleting the directory. The SDK registers a `files` autoload entry, so
deleting it alone leaves the autoloader requiring a file that no longer exists
and the application dies on boot. `league/flysystem-aws-s3-v3` goes with it.
This saves about 250 MB that an offline build could never use.

**`MustVerifyEmail` is dropped from the `User` model in the staged copy.**
LineLedger requires a new user to confirm their email address before the
application will admit them. A portable build has no mail server and no
network, so that message can never arrive and a freshly registered user is
parked on `/email/verify` permanently — the software is unusable. The build
script patches the staged copy only; `app/Models/User.php` in this repository
is untouched. Passwords, two-factor and passkeys are unaffected.

The script verifies both patches applied and fails loudly if upstream changes
shape underneath them, rather than shipping a broken bundle.

## Diagnosing a failure on the stick

The bundle logs at `debug` level to `app/storage/logs/laravel.log`, and
`Show the error log.bat` opens that file in Notepad. This exists because the
app's failure mode on Windows was a bare `500 Server Error` page with nothing
else — the real reason is in that file, and there is no terminal on the stick
to read it with.

## What is not covered

The unpack path, the browser launch and antivirus behaviour are Windows-only
and unproven from here: the build and every check above run on Linux with the
same PHP version that ships inside the bundle. The timings quoted are Linux
measurements — they show the direction, not the number he will see.

The `500 Server Error` seen after "Create organization" on Windows has **not**
been reproduced, on Linux or anywhere else. The changes here are aimed at its
most likely cause (a very slow request on a single-threaded server, with
polling requests queued behind it) and, failing that, at making the next
occurrence say what it actually was.
