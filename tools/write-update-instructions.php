<?php

/**
 * Write UPDATE-INSTRUCTIONS.txt for an update pack.
 *
 * Run by tools/build-usb-bundle.sh:
 *
 *     php write-update-instructions.php <packDir> <buildNumber> <changedList> <notesFile>
 *
 * The point of this file is that every update says, in plain English, exactly
 * what it changes and exactly what to do with it — on a phone, in a notes app,
 * with no Markdown. The file list is generated from the real diff so it cannot
 * drift from what is actually in the pack; the human summary comes from
 * usb/BUNDLE-NOTES.txt, which is written by hand for each build.
 */
declare(strict_types=1);

[$script, $packDir, $build, $changedList, $notesFile] = $argv + [null, '', '', '', ''];

if ($packDir === '' || $build === '' || ! is_file($changedList)) {
    fwrite(STDERR, 'Usage: php write-update-instructions.php <packDir> <build> <changedList> <notesFile>'.PHP_EOL);
    exit(1);
}

$changed = array_values(array_filter(
    array_map('trim', file($changedList, FILE_IGNORE_NEW_LINES) ?: []),
));
$removedFile = $packDir.'/removed.txt';
$removed = is_file($removedFile)
    ? array_values(array_filter(array_map('trim', file($removedFile, FILE_IGNORE_NEW_LINES) ?: [])))
    : [];

$blocked = is_file($packDir.'/full-bundle-required.flag');
$recompiles = is_file($packDir.'/recompile-screens.flag');

/** Plain-English name for the part of the bundle a path belongs to. */
$group = static function (string $path): string {
    return match (true) {
        str_ends_with($path, '.bat') => 'What you double-click',
        $path === 'first-run.php' => 'What you double-click',
        str_starts_with($path, 'php/') => 'PHP settings',
        $path === 'Data/env.template' => 'LineLedger settings',
        str_starts_with($path, 'app/config/') => 'LineLedger settings',
        str_starts_with($path, 'app/resources/') => 'Screens',
        str_starts_with($path, 'app/public/') => 'Screens',
        str_starts_with($path, 'app/app/') => 'Program code',
        str_starts_with($path, 'app/routes/') => 'Program code',
        str_starts_with($path, 'app/database/') => 'Books structure',
        str_starts_with($path, 'app/vendor/') => 'Libraries LineLedger uses',
        str_ends_with($path, '.txt') => 'Instructions',
        default => 'Other',
    };
};

$byGroup = [];
foreach ($changed as $path) {
    $byGroup[$group($path)][] = $path;
}
ksort($byGroup);

$wrap = static fn (string $text): string => wordwrap($text, 60, PHP_EOL, false);

$out = [];
$out[] = 'LINELEDGER UPDATE - BUILD '.$build;
$out[] = '';
$out[] = $blocked
    ? $wrap(
        'Build '.$build.' cannot be delivered as an update. Read the next '
        .'section before doing anything with this file.'
    )
    : $wrap(
        'This brings a stick that already has LineLedger on it up to build '
        .$build.'. It replaces '.count($changed).' file'
        .(count($changed) === 1 ? '' : 's')
        .' and takes a couple of minutes, instead of unpacking everything '
        .'again.'
    );
$out[] = '';
$out[] = 'Your books are not touched. Nothing in the Data folder is';
$out[] = 'read, written or moved.';
$out[] = '';

if ($blocked) {
    $out[] = '';
    $out[] = '-------------------------------------------------------------';
    $out[] = 'STOP - THIS ONE CANNOT BE APPLIED AS AN UPDATE';
    $out[] = '-------------------------------------------------------------';
    $out[] = '';
    $out[] = $wrap(
        'This build changes the structure of the books themselves. The '
        .'books on your stick were built the old way, so a program '
        .'expecting the new structure would not match them.'
    );
    $out[] = '';
    $out[] = $wrap(
        'Use the full download for this build instead. "Apply update.bat" '
        .'will refuse to run, so there is nothing you can get wrong here.'
    );
    $out[] = '';
    $out[] = $wrap(
        'If you have real books on that stick, copy the Data folder '
        .'somewhere safe first and tell me - moving existing books onto a '
        .'new structure is something I have to do, not something to '
        .'improvise at the machine.'
    );
    $out[] = '';
}

if (is_file($notesFile)) {
    $notes = trim((string) file_get_contents($notesFile));
    if ($notes !== '') {
        $out[] = '';
        $out[] = '-------------------------------------------------------------';
        $out[] = 'WHAT CHANGED IN THIS BUILD';
        $out[] = '-------------------------------------------------------------';
        $out[] = '';
        $out[] = $notes;
        $out[] = '';
    }
}

if (! $blocked) {
    $out[] = '';
    $out[] = '-------------------------------------------------------------';
    $out[] = 'WHAT TO DO - ABOUT TWO MINUTES';
    $out[] = '-------------------------------------------------------------';
    $out[] = '';
    $out[] = '1. Plug the stick in and open the LineLedger folder on it.';
    $out[] = '';
    $out[] = '   It is the folder that has "Start LineLedger.bat" in it.';
    $out[] = '';
    $out[] = '2. Unzip this update INTO that folder.';
    $out[] = '';
    $out[] = '   Not next to it, not into a new folder inside it. When';
    $out[] = '   you are done, "Apply update.bat" sits right beside';
    $out[] = '   "Start LineLedger.bat".';
    $out[] = '';
    $out[] = '   If Windows asks about replacing files, say yes.';
    $out[] = '';
    $out[] = '3. Double-click "Apply update.bat".';
    $out[] = '';
    $out[] = '   A black window opens, says what it is doing, and ends';
    $out[] = '   with "Done". It takes seconds.';
    $out[] = '';
    $out[] = '   If it says it is not the LineLedger folder, the unzip';
    $out[] = '   in step 2 went one folder too deep. Move the files up';
    $out[] = '   one level and run it again.';
    $out[] = '';
    $out[] = '4. Start LineLedger the usual way.';
    $out[] = '';
    $out[] = '   The top line of the black window now says';
    $out[] = '   "(USB build '.$build.')". That is how you know it took.';
    $out[] = '';

    if ($recompiles) {
        $out[] = '   This update changed some screens, so the first start';
        $out[] = '   after it takes about a minute longer while they are';
        $out[] = '   prepared again. Once only.';
        $out[] = '';
    }
}

$out[] = '';
$out[] = '-------------------------------------------------------------';
$out[] = 'EXACTLY WHAT THIS CHANGES';
$out[] = '-------------------------------------------------------------';
$out[] = '';
$out[] = 'Every path below is inside the LineLedger folder on the';
$out[] = 'stick. "Apply update.bat" does all of it for you - this';
$out[] = 'list is here so you can see what it did, and check.';
$out[] = '';

foreach ($byGroup as $name => $paths) {
    sort($paths);
    $out[] = $name.' ('.count($paths).')';
    $out[] = '';

    // A vendor library update is thousands of files nobody can read. Anything
    // he could meaningfully check is listed in full; the rest is counted.
    if (count($paths) > 25) {
        $shown = array_slice($paths, 0, 5);
        foreach ($shown as $path) {
            $out[] = '    '.$path;
        }
        $out[] = '    ... and '.(count($paths) - count($shown)).' more';
    } else {
        foreach ($paths as $path) {
            $out[] = '    '.$path;
        }
    }
    $out[] = '';
}

if ($removed !== []) {
    $out[] = 'Deleted ('.count($removed).')';
    $out[] = '';
    $out[] = 'Files this build no longer uses. "Apply update.bat"';
    $out[] = 'removes them.';
    $out[] = '';
    if (count($removed) > 25) {
        foreach (array_slice($removed, 0, 5) as $path) {
            $out[] = '    '.$path;
        }
        $out[] = '    ... and '.(count($removed) - 5).' more';
    } else {
        foreach ($removed as $path) {
            $out[] = '    '.$path;
        }
    }
    $out[] = '';
}

$out[] = '';
$out[] = '-------------------------------------------------------------';
$out[] = 'IF IT GOES WRONG';
$out[] = '-------------------------------------------------------------';
$out[] = '';
$out[] = $wrap(
    'Nothing here can lose your books: the update never touches the Data '
    .'folder, and if you are ever unsure, copy that folder somewhere safe '
    .'before you start. It takes ten seconds.'
);
$out[] = '';
$out[] = $wrap(
    'If LineLedger will not start after an update, delete the whole '
    .'LineLedger folder from the stick, put the full download back, and '
    .'copy your saved Data folder over the new one. That is always a way '
    .'back.'
);
$out[] = '';

file_put_contents(
    $packDir.'/UPDATE-INSTRUCTIONS.txt',
    implode(PHP_EOL, $out).PHP_EOL,
);

echo '    UPDATE-INSTRUCTIONS.txt written'.PHP_EOL;
