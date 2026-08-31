<?php

/**
 * Bring an existing settings file up to date after an update.
 *
 * A build can introduce a new setting — the SQLite pragmas that fixed the
 * "unable to open database file" 500 were exactly that. Those live in
 * Data/env.template, which is only read the FIRST time LineLedger starts on a
 * stick. A stick that already has app/.env would never see them, and the
 * update would look applied while doing nothing.
 *
 * So: any key present in the template and missing from .env is appended.
 *
 * NOTHING ELSE IS TOUCHED. An existing key keeps its existing value, always.
 * That is not caution for its own sake — APP_KEY and DB_DATABASE are written
 * per machine on first run, and overwriting either would log him out of his
 * own books or point the app at the wrong file.
 *
 *     php apply-env-updates.php <env.template> <.env>
 *
 * Exit codes:  0 done (even if nothing was needed)   1 something was wrong
 */
declare(strict_types=1);

$fail = static function (string $message): never {
    fwrite(STDERR, '      '.$message.PHP_EOL);
    exit(1);
};

$templatePath = $argv[1] ?? '';
$envPath = $argv[2] ?? '';

if ($templatePath === '' || $envPath === '') {
    $fail('Usage: php apply-env-updates.php <env.template> <.env>');
}

if (! is_file($envPath)) {
    // Nothing to bring up to date: LineLedger has never been started here, so
    // first-run.php will write a fresh .env from the new template anyway.
    echo '      No settings file yet — nothing to update.'.PHP_EOL;
    exit(0);
}

if (! is_file($templatePath)) {
    $fail('Missing '.$templatePath);
}

$keysIn = static function (string $path): array {
    $keys = [];
    foreach (file($path, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        if (preg_match('/^\s*([A-Z0-9_]+)\s*=/', $line, $m) === 1) {
            $keys[$m[1]] = $line;
        }
    }

    return $keys;
};

$templateKeys = $keysIn($templatePath);
$envKeys = $keysIn($envPath);

$missing = array_diff_key($templateKeys, $envKeys);

// A placeholder is filled in per machine by first-run.php. If one is somehow
// missing from .env, appending "__APP_KEY__" verbatim would break the app far
// more thoroughly than leaving it out.
$missing = array_filter(
    $missing,
    static fn (string $line): bool => ! str_contains($line, '__'),
);

if ($missing === []) {
    echo '      Settings are already up to date.'.PHP_EOL;
    exit(0);
}

$addition = PHP_EOL.'# Added by an update on '.date('Y-m-d').PHP_EOL
    .implode(PHP_EOL, $missing).PHP_EOL;

if (file_put_contents($envPath, $addition, FILE_APPEND) === false) {
    $fail('Could not write '.$envPath.' — the folder may be read-only.');
}

foreach (array_keys($missing) as $key) {
    echo '      Added setting: '.$key.PHP_EOL;
}

exit(0);
