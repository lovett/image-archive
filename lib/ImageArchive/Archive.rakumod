unit module ImageArchive::Archive;

use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Exception;
use ImageArchive::Tagging;
use ImageArchive::Util;

# Remove a tag completely regardless of its value from all files.
multi sub removeAliasFromArchive(Str $alias, Str $value?, Bool $dryrun = False) is export {
    my $counter = 0;

    for hyper findByTag("{$alias}:any", 'searchresult') -> $result {
        testPathExistsInArchive($result<path>);
        removeAlias($result<path>, $alias, $value, $dryrun);

        unless ($dryrun) {
            indexFile($result<path>);
        }

        $counter++;
    }

    my $message = "Untagged " ~ pluralize($counter, 'file', 'files');

    if ($dryrun) {
        wouldHaveDone($message);
        return;
    }

    say $message;
    return;
}

# Remove the tags associated with a keyword from all files.
sub removeKeywordFromArchive(Str $keyword, Bool $dryrun? = False) is export {
    my $counter = 0;
    for hyper findByTag("alias:{$keyword}", 'searchresult') -> $result {
        testPathExistsInArchive($result<path>);
        removeKeyword($result<path>, $keyword);

        unless ($dryrun) {
            indexFile($result<path>);
        }

        $counter++;
    }

    my $message = "Untagged " ~ pluralize($counter, 'file', 'files');

    if ($dryrun) {
        wouldHaveDone($message);
        return;
    }

    say $message;
    return;
}

sub deleteAlts(IO::Path $file) is export {
    my $root = appPath("root");
    my $cacheRoot = appPath('cache');

    my $relativePath = relativePath($file.Str, $root);

    my $thumbnailExtension = readConfig('alt_format');

    for readConfig('alt_sizes').split(' ') -> $size {
        my $target = $cacheRoot.add("$size/$relativePath").extension($thumbnailExtension);
        next unless $target ~~ :f;
        $target.IO.unlink;
        pruneEmptyDirsUpward($target.parent);
    }
}

# Resolve a path to an alternate.
sub findAlternate(IO::Path $path, Str $size) is export {
    my $root = appPath("root");
    my $relPath = relativePath($path, $root);
    my $thumbnailExtension = readConfig('alt_format');
    my $cacheRoot = appPath('cache');

    my $target = $cacheRoot.add("$size/$relPath").extension($thumbnailExtension).IO;

    unless ($target ~~ :f) {
        generateAlts($path);
    }

    return $target;
}

# Locate files that are not in the database.
sub findUnindexed() returns Supply is export {
    my $root = appPath('root');

    return walkArchive($root).grep({
        my $query = 'sourcefile:' ~ relativePath($_, $root);
        countRecordsByTag($query) == 0;
    });
}

# Resize an imported file to smaller sizes for faster access.
multi sub generateAlts(IO::Path $file, Bool $dryrun? = False) returns Nil is export {
    testPathExistsInArchive($file);

    my $archiveRoot = appPath('root');
    my $cacheRoot = appPath('cache');
    my $thumbnailExtension = readConfig('alt_format');
    my $source = $file.relative($archiveRoot);
    my @sizes = readConfig('alt_sizes').split(' ');
    my @clones;

    for @sizes -> $size {
        my $destination = $cacheRoot.add($size).add($source).extension($thumbnailExtension);
        next if $destination.f;

        if ($dryrun) {
            wouldHaveDone("Create {$destination}");
            next;
        }

        mkdir($destination.parent) unless $destination.parent.d;
        @clones.append(qqw{ ( -clone 0 -resize $size -write $destination ) });
    }

    return unless @clones;

    my @args = (qqw{ convert $file\[0\] -density 300x300 }, @clones, 'null:').flat;

    my $proc = Proc::Async.new(@args);

    my $stderr;
    react {
        whenever $proc.stderr {
            $stderr ~= $_;
        }
        whenever $proc.start {
            when .exitcode !== 0 {
                die ImageArchive::Exception::BadExit.new(:err($stderr));
            }
        }
    }
}

# Resize all images in the archive to smaller sizes.
multi sub generateAlts(Bool $dryrun? = False) returns Nil is export {
    my $root = appPath('root');
    my $channel = walkArchive($root).Channel;

    await (^$*KERNEL.cpu-cores).map: {
        start {
            react {
                whenever $channel -> $path {
                    generateAlts($path, $dryrun);
                }
            }
        }
    }

    return Nil;
}

# Move a file to a subfolder under the archive root.
sub importFile(IO $file, Bool $dryrun? = False) returns IO::Path is export {
    my $root = appPath('root');

    my $tagValue = readRawTag($file.IO, 'datecreated') || 'undated';

    my $destination = $root.add($tagValue.subst(":", "/", :g));

    my $newPath = $destination.add($file.basename);

    if (relativePath($newPath, $root) eq relativePath($file, $root)) {
        return Nil;
    }

    unless ($destination ~~ :d || $dryrun) {
        $destination.mkdir();
    }

    if ($destination ~~ :d) {
        for walkArchive($destination) -> $path {
            if ($path.extension('').basename eq $file.extension('').basename) {
                die ImageArchive::Exception::PathConflict.new(:path($path), :reason("basename"));
            }
        }
    }

    if ($dryrun) {
        wouldHaveDone("Move {$file} to {$newPath}");
        return Nil;
    }

    move($file, $newPath);
    $newPath.IO.chmod(0o400);
    generateAlts($newPath);
    return $newPath;
}

sub isArchiveFile(IO $path) returns Bool is export {
    my $target = $path.IO;
    return False unless ($target ~~ :f);

    my $root = appPath('root');

    return $target.absolute.starts-with($root);
}

#| Delete empty directories down-tree from the starting point.
sub pruneEmptyDirsDownward(Str $directory?, Bool $dryrun = False) is export {
    my IO::Path $root = appPath('root');

    if ($directory) {
        $root = $root.add($directory);
    }

    for walkArchiveDirs($root) -> $dir {
        my @files = $dir.dir;
        next if @files;

        if ($dryrun) {
            wouldHaveDone("Delete $dir");
            next;
        }

        rmdir($dir);
    }
}

# Delete empty directories up-tree from the starting point.
sub pruneEmptyDirsUpward(IO::Path $origin) is export {
    my $root = appPath('root');

    rmdir($origin) unless ($origin.dir);

    if ($origin.starts-with($root)) {
        pruneEmptyDirsUpward($origin.parent);
    }
}

# See if a file exists within the archive root.
sub testPathExistsInArchive($path) is export {
    my $root = appPath('root');

    return True if $path.IO.absolute.starts-with($root) && $path.IO.f;
    return True if $root.IO.add($path) ~~ :e;
    die ImageArchive::Exception::PathNotFoundInArchive.new(
        :path($path)
    );
}

# An image's date tag should reflect its filesystem path.
sub verifyDateTags(Bool $dryrun = False) is export {
    my $root = appPath('root');
    my $channel = walkArchive($root).Channel;

    await (^$*KERNEL.cpu-cores).map: {
        start {
            react {
                whenever $channel -> $path {
                    my $tagDate = readRawTag($path, 'XMP-xmp:CreateDate').subst(':', '/', :g);
                    my $expectedDate = relativePath($path, $root).IO.dirname;

                    next if ($tagDate eq $expectedDate);
                    next if ($tagDate eq '' && $expectedDate eq 'undated');

                    my $newDate = $expectedDate.subst('/', '-', :g);

                    if ($newDate eq 'undated') {
                        $newDate = '-';
                    }


                    tagFile($path, {datecreated => $newDate}, $dryrun);
                    indexFile($path);
                }
            }
        }
    }

    return Nil;
}

# List the files in the archive.
multi sub walkArchive(IO::Path $origin) returns Supply is export {
    supply for ($origin.dir) {
        next when .basename eq '_cache';
        next when .basename.starts-with: '.';
        next when .ends-with: '_original';
        next when .extension eq 'archive';
        next when .extension eq 'bak';
        next when .extension eq 'db';
        next when .extension eq 'ini';
        next when .extension eq 'txt';
        next when .extension eq 'workspace';
        when :d { .emit for walkArchive($_) }
        when :f { .emit }
    }
}

# List the files in the archive matching a given regex.
multi sub walkArchive(IO::Path $origin, Regex $matcher) returns Supply is export {
    supply for ($origin.dir) {
        next when .basename eq '_cache';
        .emit if ($_ ~~ $matcher);
        when :d { .emit for walkArchive($_, $matcher) }
    }
}

# List the directories in the archive.
sub walkArchiveDirs(IO::Path $origin) returns Supply is export {
    supply for ($origin.dir) {
        when :d {
            .emit for walkArchiveDirs($_);
            .emit;
        }
    }
}

#| Locate file paths within the archive.
sub resolveFileTarget($target, Str $flavor = 'original') is export {
    my @paths;

    my $root = appPath('root');
    my $rootedTarget = $root.add($target);

    given $flavor {
        when 'original' {
            when $target eq 'lastimport' {
                for findByNewestImport() -> $record {
                    testPathExistsInArchive($record<path>.IO);
                    @paths.append: $record<path>.IO;
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
                testPathExistsInArchive($record<path>.IO);
                @paths.append: $record<path>.IO;
            }
        }

        when 'alternate' {
            my $size = readConfig('alt_sizes').split(' ').first;

            when $target eq 'lastimport' {
                for findByNewestImport() -> $record {
                    testPathExistsInArchive($record<path>.IO);
                    @paths.append: findAlternate($record<path>.IO, $size);
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
                testPathExistsInArchive($record<path>.IO);
                @paths.append: findAlternate($record<path>.IO, $size);
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
                testPathExistsInArchive($record<path>.IO);
                next if @paths.grep($record<path>.IO.parent);
                @paths.append: $record<path>.IO.parent;
            }
        }
    }

    unless @paths {
        die ImageArchive::Exception::PathNotFoundInArchive.new;
    }

    return @paths;
}

sub replaceFile(IO::Path $original, IO::Path $replacement) is export {
    transferTags($original, $replacement);
    deleteAlts($original);
    deindexFile($original);
    unlink($original);
    importFile($replacement);
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

# Add a text file to a workspace for capturing notes and progress.
sub addWorkspaceLog(IO::Path $workspace) returns Nil {
    my $root = appPath("root");
    my $log = findWorkspaceLog($workspace);

    unless $log.f {
        my $dayNames = <Sun Mon Tue Wed Thu Fri Sat Sun>;
        my $template = %?RESOURCES<history.org>.IO.slurp;
        $template = $template.subst('@@WORKSPACE@@', relativePath($workspace, $root));

        $template = $template.subst(
            '@@DATE@@',
            Date.today(
                formatter => {
                    sprintf("%04d-%02d-%02d %s", .year, .month, .day, $dayNames[.day-of-week]);
                }
            )
        );
        spurt $log, $template;
    }

    return Nil;
}

# Create an editable version of a file in the archive.
sub copyToWorkspace(IO::Path $source) returns IO::Path is export {
    my $workspace = openWorkspace($source);

    my $sourceHash = hashFile($source);

    my $workspaceFile;

    for lazy 0...99 -> $counter {
        my $candidate = sprintf(
            'v-%02d.%s',
            $counter,
            $source.extension
        );

        $workspaceFile = $workspace.add($candidate);

        if ($workspaceFile ~~ :f) {
            my $workspaceFileHash = hashFile($workspaceFile);
            if ($workspaceFileHash eq $sourceHash) {
                $workspaceFile = Nil;
                last;
            }
        }

        last unless $workspaceFile ~~ :f;
    }

    if ($workspaceFile) {
        $source.copy($workspaceFile);
        $workspaceFile.chmod(0o644);
    }

    return $workspace;
}

sub findNewestVersion(IO::Path $workspace) is export {
    my IO::Path $newest;

    for ($workspace.dir) -> $path {
        next unless $path.f;
        next unless $path.basename.starts-with: 'v';
        next if $newest && $newest.modified > $path.modified;
        $newest = $path;
    }

    return $newest;
}

# The history file within a given workspace.
sub findWorkspaceLog(IO::Path $workspace) returns IO::Path is export {
    return $workspace.add("history.org");
}

# Locate the editing workspace for a given file.
sub findWorkspace(IO::Path $file) is export {
    testPathExistsInArchive($file);
    my $workspace = $file.extension('workspace');
    return $workspace;
}

# Create the editing workspace for a given file.
sub openWorkspace(IO::Path $file) is export {
    my $workspace = findWorkspace($file);

    unless $workspace ~~ :d {
        mkdir($workspace);
        addWorkspaceLog($workspace);
    }

    return $workspace;
}

# Transfer a workspace to a new location within or outside the archive.
sub moveWorkspace(IO::Path $workspace, IO::Path $destination, Bool $dryrun? = False) is export {
    my $root = appPath("root");
    my $destinationPath = $destination.add($workspace.basename);

    if ($destinationPath.IO ~~ :d) {
        die ImageArchive::Exception::PathConflict.new(:path($destinationPath));
    }

    if ($dryrun) {
        wouldHaveDone("Move {relativePath($workspace, $root)} to {$destinationPath}");
        return;
    }

    rename($workspace, $destinationPath);

    my $log = findWorkspaceLog($destinationPath);

    if ($log) {
        my $originalRelativePath = relativePath($workspace, $root);
        my $destinationRelativePath = relativePath($destinationPath, $root);

        my $tmp = open $log ~ '.tmp', :w;

        for $log.lines -> $line {
            $tmp.say: $line.subst($originalRelativePath, $destinationRelativePath);
        }

        $tmp.close;
        rename($tmp, $log);
    }
}

# Locate the file associated with the workspace.
sub findWorkspaceMaster(IO::Path $workspace) is export {

    my $workspaceBasename = $workspace.extension('').basename;

    for walkArchive($workspace.parent) -> $path {
        return $path if $path.extension('').basename eq $workspaceBasename;
    }

    die ImageArchive::Exception::OrphanedWorkspace.new(
        :path($workspace)
    );
}

# See if a file exists within a workspace directory.
sub testPathExistsInWorkspace(IO::Path $file) is export {
    return if $file.parent.basename.ends-with('workspace');
    die ImageArchive::Exception::PathNotFoundInArchive.new(
        :path($file)
    );
}

#| Filter the list of workspaces.
sub walkWorkspaces(Str $flavor, Str $directory?) is export {
    my IO::Path $root = appPath('root');

    if ($directory) {
        $root = $root.add($directory);
    }

    my $counter = 0;

    clearStashByKey('searchresult');

    return gather {
        for walkArchiveDirs($root) -> $dir {
            next unless $dir.extension eq 'workspace';

            my IO::Path $master = findWorkspaceMaster($dir);
            my $newestVersion = findNewestVersion($dir);

            my $masterIsNewer = $master.modified >= $newestVersion.modified;

            next if $flavor eq 'active' and $masterIsNewer;
            next if $flavor eq 'inactive' and not $masterIsNewer;

            stashPath($master);

            take %(path => $master, modified => $newestVersion.modified.DateTime);
        }
    }
}
