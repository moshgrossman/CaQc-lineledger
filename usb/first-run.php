<?php

/**
 * First-run setup for the portable LineLedger bundle.
 *
 * Writes app/.env from Data/env.template, filling in the two things that are
 * only knowable on the machine it is running on: a fresh security key, and the
 * full path to the books file (the drive letter of a USB stick changes from PC
 * to PC).
 *
 * This is a PHP script rather than more lines of .bat on purpose. A generated
 * key is base64, so it contains "+", "/" and "=", and a Windows path contains
 * backslashes — all of which are awkward to substitute safely in batch. PHP
 * does it exactly, and it can be tested off Windows.
 *
 * Run by "Start LineLedger.bat" and never by hand:
 *
 *     php first-run.php <DataDir> <AppDir>
 *
 * Exit codes:  0 written (or already present)   1 something was wrong
 */
declare(strict_types=1);

$fail = static function (string $message): never {
    fwrite(STDERR, $message.PHP_EOL);
    exit(1);
};

$dataDir = $argv[1] ?? '';
$appDir = $argv[2] ?? '';

if ($dataDir === '' || $appDir === '') {
    $fail('Usage: php first-run.php <DataDir> <AppDir>');
}

$template = rtrim($dataDir, '\\/').DIRECTORY_SEPARATOR.'env.template';
$envFile = rtrim($appDir, '\\/').DIRECTORY_SEPARATOR.'.env';
$database = rtrim($dataDir, '\\/').DIRECTORY_SEPARATOR.'database.sqlite';

// Never overwrite an existing settings file. It holds the security key, and a
// key that changes invalidates every session cookie — which is exactly the
// random-logout bug that cost a test cycle on SlowBooks.
if (is_file($envFile)) {
    echo 'Settings already present — leaving them alone.'.PHP_EOL;
    exit(0);
}

if (! is_file($template)) {
    $fail('Missing '.$template.' — unzip the download again, keeping all folders together.');
}

if (! is_file($database)) {
    $fail('Missing '.$database.' — unzip the download again, keeping all folders together.');
}

$contents = file_get_contents($template);

if ($contents === false) {
    $fail('Could not read '.$template);
}

$contents = strtr($contents, [
    '__APP_KEY__' => 'base64:'.base64_encode(random_bytes(32)),
    '__DB_PATH__' => $database,
]);

if (file_put_contents($envFile, $contents) === false) {
    $fail('Could not write '.$envFile.' — the folder may be read-only.');
}

echo 'Settings written.'.PHP_EOL;
exit(0);
