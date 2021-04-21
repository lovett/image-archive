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
        @targets = resolveFileTarget($target);
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
        when 'lastimport' {
            return findNewest(1, 'searchresult');
        }

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

    my $root = getPath('root');
    if ($directory) {
        $root = $root.add($directory);
    }

    my $counter = 0;

    clearStashByKey('searchresult');

    for walkArchive($root, /history\.org/) -> $path {
        for $path.lines.grep($matcher) -> $line {
            if $path !(elem) $cache {
                $counter++;
                my $workspaceMaster = findWorkspaceMaster($path.dirname.IO);
                stashPath($workspaceMaster);

                print "\n" if $cache.elems > 0;

                printf(
                    "%s | %s\n",
                    colored(sprintf("%3d", $counter), 'white on_blue'),
                    relativePath($workspaceMaster)
                )
            }

            say $line.subst(/ ^\W*/, '    | ');
            $cache{$path} = True;
        }
    }
}

# Remove a file from the archive.
sub deportFiles(@files, IO $destinationDir, Bool $dryrun? = False) is export {
    my $file = @files.pop;

    testPathExistsInArchive($file);

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

    if (@files) {
        deportFiles(@files, $destinationDir, $dryrun);
    }
}


#| Print a mapping of file paths to RGB triples.
sub printColorTable(@paths) is export {

    my $colspec = "%-6s | %-11s | %s\n";

    say "";
    printf($colspec, 'Swatch', 'RGB', 'Path');
    say "-" x 72;

    for @paths -> $path {
        my %tags = getTags($path, 'AverageRGB');
        my $rgb = sprintf('%-11s', %tags<AverageRGB> || 'unknown');

        printf(
            $colspec,
            colored('      ', "white on_$rgb"),
            $rgb,
            relativePath($path)
        );
    }

    say "";
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

sub printSearchResults(@results, $flavor) is export {
    my $counter = 0;

    for @results -> $result {
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
            relativePath($result<path>)
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

#| Redo question-and-answer tagging.
sub reprompt(@targets, Bool $dryrun = False) is export {
    for @targets -> $target {
        my %newTags = askQuestions($target);

        tagFile($target, %newTags, $dryrun);
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

#| Locate file paths within the archive.
sub resolveFileTarget($target, Str $flavor = 'original') is export {
    my @paths;

    given $flavor {
        when 'original' {
            when $target eq 'lastimport' {
                for findByNewestImport() -> $record {
                    testPathExistsInArchive($record<path>);
                    @paths.append: $record<path>;
                }
                succeed;
            }

            when $target.IO ~~ :f {
                testPathExistsInArchive($target.IO);
                @paths.append: $target.IO;
                succeed;
            }

            for findByStashIndex($target, 'searchresult') -> $record {
                testPathExistsInArchive($record<path>);
                @paths.append: $record<path>;
            }
        }

        when 'alternate' {
            my $size = readConfig('alt_sizes').split(' ').first;

            when $target eq 'lastimport' {
                for findByNewestImport() -> $record {
                    testPathExistsInArchive($record<path>);
                    @paths.append: findAlternate($record<path>, $size);
                }
                succeed;
            }

            when $target.IO ~~ :f {
                testPathExistsInArchive($target.IO);
                @paths.append: findAlternate($target.IO, $size);
                succeed;
            }

            for findByStashIndex($target, 'searchresult') -> $record {
                testPathExistsInArchive($record<path>);
                @paths.append: findAlternate($record<path>, $size);
            }
        }

        when 'parent' {
            when $target.IO ~~ :f {
                testPathExistsInArchive($target.IO);
                @paths.append: $target.IO.parent;
                succeed;
            }

            for findByStashIndex($target, 'searchresult') -> $path {
                next unless $path;
                testPathExistsInArchive($path[0]);
                next if @paths.grep($path[0].parent);
                @paths.append: $path[0].parent;
            }
        }
    }

    unless @paths {
        die ImageArchive::Exception::PathNotFoundInArchive.new;
    }

    return @paths;
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

            %tags.append(askQuestions($target));
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

# Display one or more files in an external application.
sub viewFiles(@paths) is export {
    my $command = readConfig('view_file');

    unless ($command) {
        die ImageArchive::Exception::MissingConfig.new(:key('view_file'));
    }

    my $proc = run $command, @paths, :err;
    my $err = $proc.err.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }
}

# Display one or more directories in an external application.
sub viewDirectories(@paths) is export {
    my $command = readConfig('view_directory');

    unless ($command) {
        die ImageArchive::Exception::MissingConfig.new(:key('view_directory'));
    }

    my $proc = shell "$command {@paths}", :err;
    my $err = $proc.err.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
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
