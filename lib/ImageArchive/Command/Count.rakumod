unit module ImageArchive::Command::Count;

use Prettier::Table;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Util;

our proto run(Str $subcommand, |) {*};

multi sub run("years") {
    my $grandTotal = 0;

    my $table = Prettier::Table.new(
        title => "Files by year",
        field-names => <Year Count>,
        align => %(Year => "l", Count => "r")
    );


    for countRecordsByYear() -> $row {
        $table.add-row: $row;
        $grandTotal += $row[1];
    }

    $table.add-row: ["TOTAL", $grandTotal];

    pagedPrint($table);
}

multi sub run("months", Int $year) {
    my $grandTotal = 0;

    my $table = Prettier::Table.new(
        title => "Files by month in $year",
        field-names => <Month Count>,
        align => %(Month => "l", Count => "r")
    );

    for countRecordsByMonth($year) -> $row {
        $table.add-row: $row;
        $grandTotal += $row[1];
    }

    $table.add-row: ["TOTAL", $grandTotal];

    pagedPrint($table);
}

multi sub run("files") {
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
