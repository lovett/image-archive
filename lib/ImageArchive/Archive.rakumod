unit module ImageArchive::Archive;

use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Exception;
use ImageArchive::Tagging;
use ImageArchive::Util;

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

# Remove a file from the archive.
sub deportFile(IO::Path $file, IO $destinationDir, Bool $dryRun? = False) is export {

    my $destinationPath = $destinationDir.add($file.basename);

    if ($destinationPath ~~ :f) {
        die ImageArchive::Exception::DeportConflict.new(:path($destinationPath));
    }

    if ($dryRun) {
        wouldHaveDone("Move {relativePath($file)} to {$destinationPath}");
        return;
    }

    deindexFile($file);
    move($file, $destinationPath);
    $destinationPath.IO.chmod(0o600);
    deleteEmptyFolders($file.parent);
    deleteAlts($file);
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

# Resize an imported file to smaller sizes for faster access.
multi sub generateAlts(IO::Path $file, Bool $dryRun? = False) is export {
    testPathExistsInArchive($file);

    my $archiveRoot = getPath('root');
    my $cacheRoot = getPath('cache');
    my $thumbnailExtension = readConfig('alt_format');

    my $target = $file.relative($archiveRoot);

    for readConfig('alt_sizes').split(' ') -> $size {
        my $destinationFile = $cacheRoot.add($size).add($target).extension($thumbnailExtension);

        next if ($destinationFile.f);

        if ($dryRun) {
            wouldHaveDone("Create {$destinationFile}");
            next;
        }

        my $destinationDir = $destinationFile.parent;
        mkdir($destinationDir) unless $destinationDir.d;

        my $proc = run qqw{
            mogrify
            -density 300
            -format $thumbnailExtension
            -path $destinationDir
            -thumbnail $size
        }, "{$file}[0]", :out, :err;

        my $err = $proc.err.slurp(:close);
        my $out = $proc.out.slurp(:close);

        if ($proc.exitcode !== 0) {
            die ImageArchive::Exception::BadExit.new(:err($err));
        }
    }
}

# Resize all images in the archive to smaller sizes.
multi sub generateAlts(Bool $dryRun? = False) is export {
    my $root = getPath('root');

    for walkArchive($root) -> $path {
        generateAlts($path, $dryRun);
    }
}

# Move a file to a subfolder under the archive root.
sub importFile(IO $file, Bool $dryRun? = False) is export {
    my $root = getPath('root');

    my $tagValue = readRawTag($file.IO, 'datecreated') || 'undated';

    my $destination = $root.add($tagValue.subst(":", "/", :g));

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

    my $newPath = $destination.add($file.basename);

    if ($dryRun) {
        wouldHaveDone("Move {$file} to {$newPath}");
        return;
    }

    move($file, $newPath);
    $newPath.IO.chmod(0o400);
    indexFile($newPath);
    generateAlts($newPath);
    say "Imported as {$newPath}";
}

# See if a file exists within the archive root.
sub testPathExistsInArchive(IO $file) is export {
    my $root = getPath('root');
    return if $file.absolute.starts-with($root) && ($file ~~ :e);
    die ImageArchive::Exception::PathNotFoundInArchive.new;
}

# List the files in the archive.
sub walkArchive(IO::Path $dir) returns Supply is export {
    supply for ($dir.dir) {
        next when .basename eq '_cache';
        next when .basename.starts-with: '.';
        next when .ends-with: '_original';
        next when .extension eq 'bak';
        next when .extension eq 'db';
        next when .extension eq 'ini';
        next when .extension eq 'txt';
        next when .extension eq 'workspace';
        when :d { .emit for walkArchive($_) }
        when :f { .emit }
    }
}

# Display files in an external application.
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
