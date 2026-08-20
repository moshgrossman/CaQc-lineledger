# LineLedger — working notes

> Upstream gitignores `CLAUDE.md`, so these notes live here instead. To have a
> session pick them up automatically, create a local (untracked) `CLAUDE.md`
> containing: `See docs/working-notes.md`.

Facts about this codebase that are easy to get wrong, and decisions already
made. Project state lives here; durable rules about how to work live in the
`working-with-moshe` skill.

## What this is

Canadian double-entry bookkeeping with real Quebec payroll — QPP, QPP2, QPIP,
the Quebec-reduced EI rate, T4, T4A, RL-1, PD7A, ROE, and the TPZ-1015.R.14
remittance. Laravel 13 / PHP 8.5 / Livewire.

## Things that are not what the documentation says

- **It runs on SQLite.** The README says MySQL 8 for real use and SQLite for
  CI, but the whole application migrates, seeds and runs on SQLite with no
  database server at all. There is no MySQL-only SQL in the codebase. This is
  what makes the portable build possible.
- **Email verification is mandatory** and blocks every meaningful route. Any
  offline or air-gapped deployment must deal with this or it is unusable. See
  `docs/usb-portable.md`.
- **The AWS SDK cannot be removed with `rm`.** It registers a `files` autoload
  entry; deleting the directory leaves the autoloader requiring a missing file
  and the app fatals on boot. Remove it through composer.
- **`fakerphp` is a runtime dependency, not a dev one.** The demo seeder builds
  its sample company through model factories. Do not strip it from a
  production install.

## Payroll tax constants

`app/Support/Payroll/Constants/` holds federal and provincial tables keyed by
effective date, with 2025, 2026 and 2027 loaded. Quebec values are cited to
Revenu Québec TP-1015.G; the federal side to CRA T4127. The resolver throws
rather than falling back to a stale table — a missing year fails loudly, which
is correct.

**These need review every January.** The code documents which minor credits it
deliberately omits, and notes each omission over-withholds slightly, which is
the safe direction.

Their own caveat, carried here so it is not forgotten: Quebec income-tax
*withholding* has not been verified against WebRAS in their test suite; only
the constants are confirmed. Always check a real paycheque against WebRAS and
PDOC before paying anyone.

## Known defects found here

- **Cheque voucher, Quebec employee:** the itemised deduction list shows only
  EI and federal tax — QPP, QPIP and Quebec income tax are missing. The cheque
  total is correct; the breakdown is not. Reproduced on the demo books:
  gross 2,500.00, deductions 646.91, but the voucher lists only 32.50 + 201.29.
  Not yet reported upstream.

## Licence — read before copying anything out

LineLedger is **AGPLv3**. SlowBooks Pro 2026 is source-available with a
no-commercial-resale clause. **The two are legally incompatible in both
directions**: AGPL forbids adding the no-resale restriction, so LineLedger code
cannot be moved into SlowBooks, and no amount of goodwill from either owner
fixes it without relicensing the whole of SlowBooks.

Tax *facts* — rates, brackets, the CRA and Revenu Québec formulas — are not
copyrightable and may be re-implemented from the government publications. That
must be a clean re-implementation from T4127 and TP-1015.G, not a translation
of this code.

Upstream states it is not seeking external contributions.

## Settled — do not raise these again

Points already acknowledged. Delete them from any risks or caveats section
before writing it. Only genuinely new evidence reopens one, and then it must be
labelled as new evidence.

| Date | Point |
|---|---|
| 2026-08-20 | Sideload / MDM filter exception cost. Known and accepted. |
| 2026-08-20 | No computer, and none will be bought. Do not propose hardware. |
| 2026-08-20 | The single-threaded PHP dev server is fine for one user. |
| 2026-08-20 | Download size is not a constraint — WiFi, 120 GB/month. |
| 2026-08-20 | Termux is acceptable for testing only, never as a dependency. |
