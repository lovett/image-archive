unit module ImageArchive::Activity;

use Terminal::ANSIColor;

use ImageArchive::Archive;
use ImageArchive::Color;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Tagging;
use ImageArchive::Util;
use ImageArchive::Workspace;

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
    my $pager = getPager();

    for countRecordsByMonth($year) -> $tally {
        my $month = $tally[0] == 0 ?? 'Unknown' !! monthName($tally[0]);
        $pager.in.printf("%10s | %s\n", $month, $tally[1]);
    }

    $pager.in.close;
}

#| Tally of walkable files by year.
sub countYears() is export {
    my $pager = getPager();

    for countRecordsByYear() -> $tally {
        my $year = $tally[0];
        $year = 'Undated' if $year == 0;
        $pager.in.printf("%7s | %s\n", $year, $tally[1]);
    }

    $pager.in.close;
}

#| Add a JobRef tag, which is a keyword describing a project or workflow.
sub groupFiles(@targets, Str $name, Bool $dryrun = False) is export {
    # Skipping Id and URL for the moment and only using Name.
    my %tags = group => "\{Name=$name\}";

    for @targets -> $target {
        tagFile($target, %tags, $dryrun);

        next if $dryrun;

        if (isArchiveFile($target)) {
            indexFile($target);
        }
    }
}

sub replaceFilePreservingName(IO::Path $original, IO::Path $substitue, Bool $dryrun = False) is export {
    testPathExistsInArchive($original);

    my $replacement = $substitue.dirname().IO.add($original.basename).extension($substitue.extension);

    if ($dryrun) {
        wouldHaveDone("Rename $substitue to $replacement");
        wouldHaveDone("Replace $original with $replacement");
        exit;
    }

    rename($substitue, $replacement);

    replaceFile($original, $replacement);

    CATCH {
        when ImageArchive::Exception::PathNotFoundInWorkspace {
            note colored($_.message, 'red');
            exit 1;
        }
    }
}

sub replaceFile(IO::Path $original, IO::Path $replacement) is export {
    transferTags($original, $replacement);
    deleteAlts($original);
    deindexFile($original);
    unlink($original);
    importFile($replacement);
}

#| Locate lines in log files matching a regex.
sub searchLogs(Regex $matcher, Str $directory?) is export {
    my SetHash $cache = SetHash.new;
    my $pager = getPager();

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

                $pager.in.print: "\n" if $cache.elems > 0;

                $pager.in.printf(
                    "%s | %s\n",
                    colored(sprintf("%3d", $counter), 'white on_blue'),
                    relativePath($workspaceMaster)
                )
            }

            $pager.in.say: $line.subst(/ ^\W*/, '    | ');
            $cache{$path} = True;
        }
    }

    $pager.in.close;
}

# Remove a file from the archive.
sub deportFiles(@files, IO $destinationDir, Bool $dryrun? = False) is export {
    my $file = @files.pop;

    testPathExistsInArchive($file);

    my $workspace = findWorkspace($file);
    my $parent = $file.parent;
    my $fileDestination = $destinationDir.add($file.basename);
    my $workspaceDestination = $destinationDir.add($workspace.basename);

    if ($fileDestination ~~ :f) {
        die ImageArchive::Exception::PathConflict.new(:path($fileDestination));
    }

    if ($workspaceDestination ~~ :d) {
        die ImageArchive::Exception::PathConflict.new(:path($workspaceDestination));
    }

    if ($dryrun) {
        wouldHaveDone("Move {relativePath($file)} to {$fileDestination}");
        return;
    }

    deindexFile($file);
    move($file, $fileDestination);
    $fileDestination.IO.chmod(0o644);
    deleteAlts($file);

    if ($workspace ~~ :d) {
        moveWorkspace($workspace, $destinationDir, $dryrun);
    }

    pruneEmptyDirsUpward($parent);

    if (@files) {
        deportFiles(@files, $destinationDir, $dryrun);
    }
}


#| Print a mapping of file paths to RGB triples.
sub printColorTable(@paths) is export {
    my $pager = getPager();

    my $colspec = "%-6s | %-11s | %s\n";

    $pager.in.say: "";
    $pager.in.printf($colspec, 'Swatch', 'RGB', 'Path');
    $pager.in.say: "-" x 72;

    for @paths -> $path {
        my %tags = getTags($path, 'AverageRGB');
        my $rgb = sprintf('%-11s', %tags<AverageRGB> || 'unknown');

        $pager.in.printf(
            $colspec,
            colored('      ', "white on_$rgb"),
            $rgb,
            relativePath($path)
        );
    }

    $pager.in.say: "";
    $pager.in.close;
}

#| Print the contents of a workspace log.
sub printHistory(@files) is export {
    my $pager = getPager();

    for @files -> $file {
        my $workspace = findWorkspace($file);
        my $log = findWorkspaceLog($workspace);

        next unless $log ~~ :f;

        for $log.lines -> $line {
            next unless $line.trim;
            next if $line.starts-with('#');
            $line.subst(/\*+\s/, "").say;
            $pager.in.print: "\n" if $line.starts-with('*');
        }
    }

    $pager.in.close;
}

sub printSearchResults(@results) is export {
    my $counter = 0;

    my $pager = getPager();

    for @results -> $result {
        my @columns = colored(sprintf("%3d", ++$counter), 'white on_blue');

        given $result {
            when $result<series>:exists {
                @columns.push: sprintf("%15s", formattedSeriesId(
                    $result<series>,
                    $result<seriesid>.Str
                ));
            }

            when $result<score>:exists {
                @columns.push: sprintf("%2.2f", $result<score>);
            }

            when $result<modified>:exists {
                @columns.push: $result<modified>.yyyy-mm-dd;
            }
        }

        @columns.push: relativePath($result<path>);

        $pager.in.say: @columns.join(" | ");
    }

    unless ($counter) {
        note 'No matches.';
    }

    $pager.in.close;
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

    replaceFile($master, $newMaster);
}

#| Locate file paths within the archive.
sub resolveFileTarget($target, Str $flavor = 'original') is export {
    my @paths;

    my $root = getPath('root');
    my $rootedTarget = $root.add($target);

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
                @paths.append: $target.IO;
                succeed;
            }

            when $rootedTarget.IO ~~ :f {
                @paths.append: $rootedTarget.IO;
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

            when $rootedTarget.IO ~~ :f {
                @paths.append: findAlternate($rootedTarget.IO, $size);
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

            when $rootedTarget.IO ~~ :f {
                @paths.append: $rootedTarget.IO.parent;
                succeed;
            }

            for findByStashIndex($target, 'searchresult') -> $record {
                testPathExistsInArchive($record<path>);
                next if @paths.grep($record<path>.parent);
                @paths.append: $record<path>.parent;
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

sub suggestContextKeywords(@contexts) {
    my %contexts = readConfig('contexts');

    my %suggestionContexts = @contexts Z=> %contexts{@contexts};

    say "";

    for %suggestionContexts.kv -> $context, $aliases {
        my @keywords = keywordsInContext($context);
        say colored("{$context} keywords", 'cyan underline') ~ "\n" ~ @keywords.sort.join(", ");
        say "To disable: no{$context}";
        say "";
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
sub viewExternally(*@paths) is export {
    my $key = 'view_file';

    given @paths[0].IO {
        when .extension eq 'html' {
            $key = 'view_html'
        }

        when :d {
            $key = 'view_directory'
        }
    }

    my $command = readConfig($key);

    unless ($command) {
        die ImageArchive::Exception::MissingConfig.new(:key($key));
    }

    # This uses shell rather than run for maximum compatibility.
    # For example, emacsclient wouldn't work with run.
    my $proc = shell "$command {@paths}", :err;
    my $err = $proc.err.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }
}

#| Remove a JobRef tag.
sub ungroupFiles(@targets, Str $name, Bool $dryrun = False) is export {
    my %aliases = readConfig('aliases');
    my $formalTag = %aliases<group>;

    for @targets -> $target {
        commitTags($target, "-{$formalTag}-=\{Name=$name\}".List, $dryrun);

        next if $dryrun;

        if (isArchiveFile($target)) {
            indexFile($target);
        }
    }
}

# Remove tags by keyword, alias, or alias-and-value.
multi sub untagTerm(@targets, Str $term, Str $value, Bool $dryrun = False) is export {
    my $termType = identifyTerm($term);

    given $termType {
        when 'alias' {
            for @targets -> $target {
                removeAlias($target, $term, $value, $dryrun);

                if (isArchiveFile($target)) {
                    indexFile($target);
                }
            }
        }

        when 'keyword' {
            for @targets -> $target {
                removeKeyword($target, $term, $dryrun);

                if (isArchiveFile($target)) {
                    indexFile($target);
                }
            }
        }
    }
}

multi sub untagTerm(Str $term, Str $value, Bool $dryrun = False) is export {
    my $termType = identifyTerm($term);

    given $termType {
        when 'alias' {
            removeAliasFromArchive($term, $value, $dryrun);
        }

        when 'keyword' {
            removeKeywordFromArchive($term, $dryrun);
        }
    }
}
