# Portable (USB) build

A build of LineLedger that runs from a USB stick on any 64-bit Windows PC.
Nothing is installed, no administrator rights are needed, and no network
connection is used. It exists for people who do not have a computer of their
own and work from a machine they cannot change.

Build it with:

```bash
tools/build-usb-bundle.sh
```

The result is `dist/LineLedger-USB-<version>-b<bundle>.zip` (~120 MB). The
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
| Password breach check | online lookup | removed — no network |

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
`program.tar.gz`, so the download holds **96** entries — 77 of them the PHP
runtime — instead of seventeen thousand. Explorer copies one big file, which is what a stick is good
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

## The 500 after "Create organization"

Reported twice from Windows, never reproducible on Linux. His error log named
it:

```
SQLSTATE[HY000]: General error: 14 unable to open database file
  (Connection: sqlite, Database: D:\LineLedger\Data\database.sqlite,
   SQL: insert into "accounts" ... 1200 Undeposited Funds ...)
```

SQLite error 14 is `CANTOPEN` — it could not open **a** file. Not the books
file: it had been writing that for minutes, and the same request had already
inserted the company, the membership and several accounts. What it could not
open is one of the small working files SQLite creates while a write is in
flight — the rollback journal beside the books, or a statement journal in the
system temp folder. The two attempts died on *different* accounts (1200, then
1100), which is the signature of an intermittent file operation, not a
permission or schema problem.

Three things make that likely on this bundle specifically, and each is now
addressed:

| Suspect | What changed |
|---|---|
| The rollback journal is created and deleted for every write, and an antivirus filter holds a handle on each file as it appears | `journal_mode=TRUNCATE` — created once, emptied instead of deleted |
| The page polls itself while a long write holds the database | `busy_timeout=15000` — wait for the lock instead of failing |
| SQLite's scratch file lands in a system temp folder a locked-down PC will not allow | the launcher tests that folder and falls back to one on the stick |
| No room on the stick for any of the above | the launcher warns below 300 MB free |

Upstream wires `busy_timeout`, `journal_mode` and `synchronous` to `null` with
no way to set them, so the build patches the staged `config/database.php` to
read them from the settings file. Unset is still `null`, so a server install
behaves exactly as before.

**It is not confirmed fixed.** None of this was reproducible here, so these are
the most likely causes made unlikely, not a demonstrated repair.

What *is* confirmed: `CreateCompany` wraps the whole thing in
`DB::transaction`, so a failure rolls back completely. A 500 here leaves no
half-created company behind, and retrying is safe.

## The deliberate changes

**The AWS SDK is removed at build time**, through `composer remove` rather
than by deleting the directory. The SDK registers a `files` autoload entry, so
deleting it alone leaves the autoloader requiring a file that no longer exists
and the application dies on boot. `league/flysystem-aws-s3-v3` goes with it.
This saves about 250 MB that an offline build could never use.

**The online password check is removed.** `AppServiceProvider` adds
`->uncompromised()` to the production password rules, which checks every new
password against `api.pwnedpasswords.com`. His log shows the offline bundle
calling it. `README-USB.txt` promises this build never uses the internet, and
that promise wins. Length, mixed case, letters, numbers and symbols all still
apply.

**`MustVerifyEmail` is dropped from the `User` model in the staged copy.**
LineLedger requires a new user to confirm their email address before the
application will admit them. A portable build has no mail server and no
network, so that message can never arrive and a freshly registered user is
parked on `/email/verify` permanently — the software is unusable. The build
script patches the staged copy only; `app/Models/User.php` in this repository
is untouched. Passwords, two-factor and passkeys are unaffected.

Every one of these patches verifies that it applied, and fails the build loudly
if upstream changed shape underneath it, rather than shipping a broken bundle
or a silently dead patch.

## Update packs, and why they exist

Testing happens on a computer paid for by the minute. Unpacking the full
bundle onto the stick takes something like half an hour, so every test cycle
cost half an hour of paid time before a single thing could be tried. That, not
page speed, is the real cost of this project.

So every build publishes two downloads:

- `LineLedger-USB-<version>-b<bundle>.zip` — the full bundle, for a fresh stick.
- `LineLedger-update-to-b<bundle>.zip` — only the files that differ from the
  previous build. Typically kilobytes; a launcher fix is two files.

It works off `manifest.txt`, a checksum of every file that lands on the stick,
published as a Release asset. The next build downloads the previous one, diffs
it, and copies only what changed into the pack. Books are deliberately absent
from the manifest: an update must never overwrite what he has typed.

The pack carries `Apply update.bat`, so applying it is a double-click rather
than a folder-merge done by hand at the machine, and an
`UPDATE-INSTRUCTIONS.txt` generated from the real diff — it cannot claim to
change something the pack does not contain. The human summary in it comes from
`usb/BUNDLE-NOTES.txt`, which is written by hand for each build.

Three things the pack has to get right, each of which would otherwise cost a
cycle or worse:

- **Deleted files.** Trimming removes files; the pack lists them and the
  applier deletes them, or the stick keeps carrying files the build dropped.
- **Compiled screens.** If a template changed, the copies already compiled on
  the stick are cleared, or he tests the old screen and reports no change.
- **New settings.** `Data/env.template` is only read on a stick's *first* run,
  so a new setting would never reach an existing `.env`. `apply-env-updates.php`
  appends keys that are missing and **never** modifies one that exists —
  `APP_KEY` and `DB_DATABASE` are written per machine, and overwriting either
  would log him out of his own books or point the app at the wrong file.

**A build that changes a migration cannot ship as an update at all.** The books
on the stick are created and migrated at build time; nothing migrates them on
the stick. The build detects a changed migration, marks the pack, and
`Apply update.bat` refuses to run — a program expecting a new schema against
old books is worse than no update.

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

The `500 Server Error` after "Create organization" has **not** been reproduced
here — only diagnosed from his log. See the section above for what it was and
what now stands in its way.
