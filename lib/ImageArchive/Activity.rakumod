unit module ImageArchive::Activity;

use ImageArchive::Archive;
use ImageArchive::Color;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Tagging;
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

sub reindex(Str $target?) is export {
    my @targets;

    if ($target) {
        @targets = resolveFileTarget($target, 'original');
    } else {
        my $root = getPath('root');
        @targets =  walkArchive($root).List;
    }

    for @targets -> $target {
        print "Reindexing {$target}...";
        tagFile($target, {});
        indexFile($target);
        say "done.";
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

# Remove a file from the archive.
sub deportFiles(@files, IO $destinationDir, Bool $dryRun? = False) is export {
    return unless @files;

    my $file = @files.pop;

    my $destinationPath = $destinationDir.add($file.basename);

    if ($destinationPath ~~ :f) {
        die ImageArchive::Exception::PathConflict.new(:path($destinationPath));
    }

    if ($dryRun) {
        wouldHaveDone("Move {relativePath($file)} to {$destinationPath}");
        return;
    }

    deindexFile($file);
    move($file, $destinationPath);
    $destinationPath.IO.chmod(0o644);
    deleteAlts($file);

    my $workspace = findWorkspace($file);
    if ($workspace ~~ :d) {
        moveWorkspace($workspace, $destinationDir, $dryRun);
    }

    pruneEmptyDirsUpward($file.parent);

    deportFiles(@files, $destinationDir, $dryRun);
}


#| Print a mapping of file paths to RGB triples.
sub printColorTable(%fileMap) is export {
    for %fileMap.kv -> $path, @rgb {
        printf(
            "%3s, %3s, %3s | %s\n",
            @rgb,
            $path
        );
    }
}

#| Print the contents of a workspace log.
sub printHistory(@files) is export {
    return unless @files;

    my $file = @files.pop;
    my $workspace = findWorkspace($file);
    my $log = findWorkspaceLog($workspace);

    if ($log ~~ :f) {
        for $log.lines -> $line {
            next unless $line.trim;
            next if $line.starts-with('#');
            $line.subst(/\*+\s/, "").say;
            print "\n" if $line.starts-with('*');
        }
    }

    printHistory(@files);
}

sub printSearchResults(@records) is export {
    my $counter = 0;

    for (@records) -> $result {
        my $index = sprintf("%3d", ++$counter);
        my $series = sprintf('%s-%03d', $result<series>, $result<seriesid>);

        printf(
            "%s | %15s | %s\n",
            colored($index, 'white on_blue'),
            $series,
            $result<path>
        );
    }

    unless ($counter) {
        note 'No matches.';
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

#| Look up average color for one or more files.
sub resolveColorTarget($target) is export {
    my %targets;

    if ($target.IO.f) {
        my $path = relativePath($target);
        %targets{$path} = getAverageColor($target.IO);
    } else {
        my @records = findByStashIndex($target, 'searchresult', 'AverageRGB'.List);

        for @records {
            my $path = relativePath($_[0]);
            %targets{$path} = $_[1].split(',');
        }
    }

    return %targets;
}

#| Convert the arguments of a view command to file paths.
sub resolveFileTarget($target, Str $flavor = 'alternate') is export {

    given $flavor {
        when 'original' {
            if ($target eq 'lastimport') {
                my $lastimport = findByNewestImport();
                return $lastimport[0]<path>.IO;
            }


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

        when 'parent' {
            if ($target.IO.f) {
                return $target.IO.parent.List;
            }

            my @records = findByStashIndex($target, 'searchresult');
            return @records.map({ findFile($_[0]).parent });
        }

    }
}
