unit module ImageArchive::Activity;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Util;
use ImageArchive::Workspace;

use Terminal::ANSIColor;

=begin pod
This module is for multi-step operations that involve multiple other modules or do things that don't
quite fit in another module. It helps keep the main script lean.
=end pod

# Tally of all walkable files.
sub countFiles() is export {
    my $root = getPath('root');

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

#| Tally of walkable files per month in a given year.
sub countMonths(Int $year) is export {
    for countRecordsByMonth($year) -> $tally {
        my $month = $tally[0] == 0 ?? 'Unknown' !! monthName($tally[0]);
        printf("%10s | %s\n", $month, $tally[1]);
    }
}

#| Tally of walkable files by year.
sub countYears() is export {
    for countRecordsByYear() -> $tally {
        my $year = $tally[0];
        $year = 'Undated' if $year == 0;
        printf("%7s | %s\n", $year, $tally[1]);
    }
}

#| Locate lines in log files matching a regex.
sub searchLogs(Regex $matcher, Str $directory?) is export {
    my SetHash $cache = SetHash.new;

    my IO::Path $root = getPath('root');
    if ($directory) {
        $root = findDirectory($directory);
    }

    for walkArchive($root, /history\.org/) -> $path {
        for $path.lines.grep($matcher) -> $line {
            if $path !(elem) $cache {
                print "\n" if $cache.elems > 0;
                say colored(relativePath($path.dirname), 'cyan underline');
            }

            say $line;
            $cache{$path} = True;
        }
    }
}

#| Delete empty directories down-tree from the starting point.
sub pruneEmptyDirsDownward(Str $directory?) is export {
    my IO::Path $root = getPath('root');

    if ($directory) {
        $root = findDirectory($directory);
    }

    for walkArchiveDirs($root) -> $dir {
        rmdir($dir) unless ($dir.dir);
    }
}

#| Convert the arguments of a view command to file paths.
sub resolveViewTarget($target, Str $flavor = 'alternate') is export {

    given $flavor {
        when 'original' {
            if ($target.IO.f) {
                return findFile($target);
            }

            my @records = findByStashIndex($target, 'searchresult');
            return @records.map({ findFile($_[0]) });
        }

        when 'alternate' {
            my @altSizes = readConfig('alt_sizes').split(' ');

            if ($target.IO.f) {
                my $path = relativePath($target);
                return findAlternate($path, @altSizes.first);
            }

            my @records = findByStashIndex($target, 'searchresult');
            return @records.map({ findAlternate($_[0], @altSizes.first) });
        }
    }
}
