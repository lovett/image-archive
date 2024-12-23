unit package ImageArchive::Command;

use Date::Names;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Util;

#| Tally of walkable files by year.
our sub countByYear() is export {
    my $grandTotal = 0;
    my $format = "%7s | %s\n";

    my $pager = getPager();

    for countRecordsByYear() -> $tally {
        my $year = $tally[0];
        $year = 'Undated' if $year == 0;
        $pager.in.printf($format, $year, $tally[1]);
        $grandTotal += $tally[1];
    }

    $pager.in.printf($format, "TOTAL", $grandTotal);

    $pager.in.close;
}

#| Tally of walkable files per month in a given year.
our sub countByYearAndMonth(Int $year) is export {
    my $pager = getPager();
    my $d = Date::Names.new: :lang("en");
    my $grandTotal = 0;
    my $format = "%10s | %s\n";

    for countRecordsByMonth($year) -> $tally {
        my $month = $tally[0] == 0 ?? 'Unknown' !! $d.mon($tally[0]);
        $pager.in.printf($format, $month, $tally[1]);
        $grandTotal += $tally[1];
    }

    $pager.in.printf($format, "TOTAL", $grandTotal);

    $pager.in.close;
}

#| Tally of all walkable files.
our sub countFiles() is export {
    my $root = appPath('root');

    my $fileCount = 0;
    for walkArchive($root) -> $path {
        $fileCount++;
    }

    my $recordCount = countRecords();

    if ($recordCount eq $fileCount) {
        say pluralize($fileCount, 'file', 'files');
    } else {
        my $fileCountWithLabel = pluralize($fileCount, 'file', 'files');
        my $recordCountWithLabel = pluralize($recordCount, 'database record', 'database records');

        say qq:to/END/;
        ⚠️  Found {$fileCountWithLabel} but {$recordCountWithLabel}.

        This can be fixed by reindexing the archive:
          {$*PROGRAM-NAME.IO.basename} reindex

        To list the missing files:
          {$*PROGRAM-NAME.IO.basename} search:unindexed

        END
    }
}
