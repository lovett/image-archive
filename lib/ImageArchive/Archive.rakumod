unit module ImageArchive::Archive;

use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Exception;
use ImageArchive::Tagging;
use ImageArchive::Util;

# Remove a tag completely regardless of its value from all files.
multi sub removeAliasFromArchive(Str $alias, Str $value?, Bool $dryRun = False) is export {
    my $counter = 0;

    for hyper findByTag("{$alias}:any", 'searchresult') -> $result {
        my $path = findFile($result<path>);
        removeAlias($path, $alias, $value, $dryRun);

        unless ($dryRun) {
            indexFile($path);
        }

        $counter++;
    }

    my $message = "Untagged " ~ pluralize($counter, 'file', 'files');

    if ($dryRun) {
        wouldHaveDone($message);
        return;
    }

    say $message;
    return;
}

# Remove the tags associated with a keyword from all files.
sub removeKeywordFromArchive(Str $keyword, Bool $dryRun? = False) is export {
    my $counter = 0;
    for hyper findByTag("alias:{$keyword}", 'searchresult') -> $result {
        my $path = findFile($result<path>);
        removeKeyword($path, $keyword);

        unless ($dryRun) {
            indexFile($path);
        }

        $counter++;
    }

    my $message = "Untagged " ~ pluralize($counter, 'file', 'files');

    if ($dryRun) {
        wouldHaveDone($message);
        return;
    }

    say $message;
    return;
}

sub deleteAlts(IO::Path $file) is export {
    my $cacheRoot = getPath('cache');

    my $relativePath = relativePath($file.Str);

    my $thumbnailExtension = readConfig('alt_format');

    for readConfig('alt_sizes').split(' ') -> $size {
        my $target = $cacheRoot.add("$size/$relativePath").extension($thumbnailExtension);
        next unless $target ~~ :f;
        $target.IO.unlink;
        deleteEmptyFolders($target.parent);
    }
}

sub deleteEmptyFolders(IO::Path $leaf) {
    my $root = getPath('root');

    my $dir = $leaf;
    while ($dir.starts-with($root)) {
        if (dir $dir) {
            return;
        }

        rmdir($dir);
        $dir = $dir.parent;
    }
}

# Resolve a path to an archive file.
sub findFile(Str $path) is export {
    my $target = $path.IO;

    unless ($target ~~ :f) {
        $target = getPath('root').add($path);
    }

    testPathExistsInArchive($target);

    return $target;
}

# Resolve a path to an archive directory.
sub findDirectory(Str $path) is export {
    my $target = $path.IO;

    unless ($target ~~ :d) {
        $target = getPath('root').add($path);
    }

    testPathExistsInArchive($target);

    return $target;
}

# Resolve a path to an alternate.
sub findAlternate(Str $path, Str $size) is export {
    my $thumbnailExtension = readConfig('alt_format');
    my $cacheRoot = getPath('cache');

    my $target = $cacheRoot.add("$size/$path").extension($thumbnailExtension).IO;

    unless ($target ~~ :f) {
        generateAlts(findFile($path));
    }

    return $target;
}

# Locate files that are not in the database.
sub findUnindexed() returns Supply is export {
    my $archiveRoot = getPath('root');

    return walkArchive($archiveRoot).grep({
        my $query = 'sourcefile:' ~ relativePath($_);
        my $count = countRecordsByTag($query);
        $count == 0;
    });
}

# Resize an imported file to smaller sizes for faster access.
multi sub generateAlts(IO::Path $file, Bool $dryRun? = False) returns Nil is export {
    testPathExistsInArchive($file);

    my $archiveRoot = getPath('root');
    my $cacheRoot = getPath('cache');
    my $thumbnailExtension = readConfig('alt_format');
    my $source = $file.relative($archiveRoot);
    my @sizes = readConfig('alt_sizes').split(' ');
    my @clones;

    for @sizes -> $size {
        my $destination = $cacheRoot.add($size).add($source).extension($thumbnailExtension);
        next if $destination.f;

        if ($dryRun) {
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
multi sub generateAlts(Bool $dryRun? = False) returns Nil is export {
    my $root = getPath('root');
    my $channel = walkArchive($root).Channel;

    await (^$*KERNEL.cpu-cores).map: {
        start {
            react {
                whenever $channel -> $path {
                    generateAlts($path, $dryRun);
                }
            }
        }
    }

    return Nil;
}

# Move a file to a subfolder under the archive root.
sub importFile(IO $file, Bool $dryRun? = False) returns IO::Path is export {
    my $root = getPath('root');

    my $tagValue = readRawTag($file.IO, 'datecreated') || 'undated';

    my $destination = $root.add($tagValue.subst(":", "/", :g));

    my $newPath = $destination.add($file.basename);

    if (relativePath($newPath) eq relativePath($file)) {
        return Nil;
    }

    unless ($destination ~~ :d || $dryRun) {
        $destination.mkdir();
    }

    if ($destination ~~ :d) {
        for walkArchive($destination) -> $path {
            if ($path.extension('').basename eq $file.extension('').basename) {
                die ImageArchive::Exception::FileExists.new(:path($path));
            }
        }
    }

    if ($dryRun) {
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

    my $root = getPath('root');

    return $target.absolute.starts-with($root);
}

# Delete empty directories up-tree from the starting point.
sub pruneEmptyDirsUpward(IO::Path $origin) is export {
    my $root = getPath('root');

    rmdir($origin) unless ($origin.dir);

    if ($origin.starts-with($root)) {
        pruneEmptyDirsUpward($origin.parent);
    }
}

# See if a file exists within the archive root.
sub testPathExistsInArchive(IO $file) is export {
    my $root = getPath('root');
    return if $file.absolute.starts-with($root) && ($file ~~ :e);
    die ImageArchive::Exception::PathNotFoundInArchive.new;
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

# Display files in an external application.
sub viewFiles(@paths) is export {
    unless (@paths) {
        die ImageArchive::Exception::PathNotFoundInArchive.new;
    }

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

# Display files in an external application.
sub viewDirectories(@paths) is export {
    for @paths {
        unless ($_ ~~ :d) {
            die ImageArchive::Exception::PathNotFoundInArchive.new;
        }
    }

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
