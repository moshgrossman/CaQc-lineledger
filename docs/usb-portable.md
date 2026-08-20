# Portable (USB) build

A build of LineLedger that runs from a USB stick on any 64-bit Windows PC.
Nothing is installed, no administrator rights are needed, and no network
connection is used. It exists for people who do not have a computer of their
own and work from a machine they cannot change.

Build it with:

```bash
tools/build-usb-bundle.sh
```

The result is `dist/LineLedger-USB-<version>.zip` (~133 MB), containing the
application, its libraries, the official php.net Windows build of PHP, an
empty set of books, a second set of practice books, and a `.bat` file to
start it.

## How it differs from a server install

| | Server install | Portable build |
|---|---|---|
| Database | MySQL | SQLite file on the stick |
| Queue | worker process | `sync` — jobs run inline |
| Scheduler | cron | not run |
| Mail | SMTP | `log` — nothing is sent |
| Object storage | S3 optional | local only; AWS SDK removed |
| Email verification | required | **not required** (see below) |

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

## What is not covered

The bundle has not been run on Windows by its author — it was built and
verified on Linux with the same PHP version that ships inside it. The
Windows-specific parts (the `.bat`, the browser launch, antivirus behaviour)
are unproven until someone runs them.
