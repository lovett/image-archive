unit module ImageArchive::Activity;

use ImageArchive::Archive;
use ImageArchive::Color;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Hints;
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

#| Bring a file into the archive.
sub import(IO::Path $file, Bool $dryrun = False) is export {
    my $importedFile = importFile($file.IO, $dryrun);
    indexFile($importedFile);
    say "Imported as {$importedFile}";
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

sub search(@terms, Int $limit = 10, Bool $debug = False) is export {
    my $query = @terms.join(' ');

    given $query {
        when 'recent' {
            return findNewest($limit, 'searchresult');
        }

        default {
            return findByTag($query, 'searchresult', $debug);
        }

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
sub deportFiles(@files, IO $destinationDir, Bool $dryrun? = False) is export {
    return unless @files;

    my $file = @files.pop;

    my $destinationPath = $destinationDir.add($file.basename);

    if ($destinationPath ~~ :f) {
        die ImageArchive::Exception::PathConflict.new(:path($destinationPath));
    }

    if ($dryrun) {
        wouldHaveDone("Move {relativePath($file)} to {$destinationPath}");
        return;
    }

    deindexFile($file);
    move($file, $destinationPath);
    $destinationPath.IO.chmod(0o644);
    deleteAlts($file);

    my $workspace = findWorkspace($file);
    if ($workspace ~~ :d) {
        moveWorkspace($workspace, $destinationDir, $dryrun);
    }

    pruneEmptyDirsUpward($file.parent);

    deportFiles(@files, $destinationDir, $dryrun);
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

sub printSearchResults(@records, $flavor) is export {
    my $counter = 0;

    for (@records) -> $result {
        my $col1 = sprintf("%3d", ++$counter);

        my $col2;
        given $flavor {
            when 'series' {
                $col2 = sprintf('%s-%03d', $result<series>, $result<seriesid>);
            }

            when 'score' {
                $col2 = sprintf("%2.2f", $result<score>);
            }
        }

        printf(
            "%s | %15s | %s\n",
            colored($col1, 'white on_blue'),
            $col2,
            $result<path>
        );
    }

    unless ($counter) {
        note 'No matches.';
    }
}

sub printUnindexed() is export {
    my $counter = 0;

    for findUnindexed() -> $path {
        my $index = sprintf("%3d", ++$counter);
        printf(
            "%s | %s\n",
            colored($index, 'white on_red'),
            relativePath($path),
        );
    }

    unless $counter {
        say "No unindexed files.";
    }
}

# Move a file out of the workspace.
sub promoteVersion(IO::Path $file, Bool $dryrun? = False) is export {
    testPathExistsInWorkspace($file);

    my $master = findWorkspaceMaster($file.parent);
    my $newMaster = $master.extension($file.extension);

    if ($dryrun) {
        wouldHaveDone("{$file} becomes {$newMaster}");
        return;
    }

    transferTags($master, $file);
    deleteAlts($master);
    deindexFile($master);
    unlink($master);

    rename($file, $newMaster);
    indexFile($newMaster);
    generateAlts($newMaster);
    $newMaster.chmod(0o400);

    CATCH {
        when ImageArchive::Exception::PathNotFoundInWorkspace {
            note colored($_.message, 'red');
            exit 1;
        }
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

#| Redo question-and-answer tagging.
sub reprompt(@targets, Bool $dryrun = False) is export {
    for @targets -> $target {
        my %tags = askQuestions();

        tagFile($target, %tags, $dryrun);
        next if $dryrun;

        if (isArchiveFile($target)) {
            my $importedFile = importFile($target);
            if ($importedFile) {
                say "Relocated to {$importedFile}";

                my $workspace = findWorkspace($target);
                if ($workspace ~~ :d) {
                    moveWorkspace($workspace, $importedFile.parent);
                }
                pruneEmptyDirsUpward($target.parent);
            }
            indexFile($target);
        }
    }
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

        # Almost the same as original, but does not require target
        # to be inside the archive.
        when 'taggable' {
            if ($target.IO.f) {
                return $target.IO;
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

#| Display a file's tags.
sub showTags(@targets) is export {
    my %aliases = readConfig('aliases');

    for @targets -> $target {
        say readTags($target, %aliases.values);
    }
}

sub tagAndImport(@targets, @keywords, Bool $dryrun = False) is export {
    testKeywords(@keywords);

    my %tags = keywordsToTags(@keywords);

    for @targets -> $target {
        # If the file has id and alias tags, consider it previously tagged
        # and skip context validation.
        my $previouslyTagged = readRawTags($target, ['id', 'alias']).elems == 2;

        unless ($previouslyTagged) {
            my @contexts = activeContexts(@keywords);

            testContexts(@contexts);

            testContextCoverage(@contexts, @keywords);

            %tags.append(askQuestions());
        }

        %tags<alias> = @keywords;

        tagFile($target, %tags, $dryrun);

        if ($dryrun) {
            return;
        }

        if (isArchiveFile($target)) {
            indexFile($target);
            return;
        }

        confirm('Tags written. Import to archive?');
        my $importedFile = importFile($target, $dryrun);
        indexFile($importedFile);

        say "Imported as {$importedFile}";
    }

    CATCH {
        when ImageArchive::Exception::MissingContext {
            note colored($_.message, 'red');
            suggestContextKeywords($_.offenders);
            exit 1;
        }
    }
}

#| Remove tags by alias or value.
sub untagByAlias(@targets, Str $alias, Str $value?, Bool $dryrun = False) is export {
    for @targets -> $target {
        removeAlias($target, $alias, $value, $dryrun);

        if (isArchiveFile($target)) {
            indexFile($target);
        }
    }
}

#| Remove tags by keyword.
sub untagByKeyword(@targets, Str $keyword, Bool $dryrun = False) is export {
    for @targets -> $target {
        removeKeyword($target, $keyword, $dryrun);

        if (isArchiveFile($target)) {
            indexFile($target);
        }
    }

}
