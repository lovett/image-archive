unit module ImageArchive::Archive;

use Terminal::ANSIColor;

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

# Resize and thumbnail via GraphicsMagick.
#
# If a path is not given, the archive is walked.
sub generateAlts(IO::Path $file?) is export {
    my $root = getPath('root');
    my $cacheRoot = getPath('cache');
    my %rosters;
    my %counters;
    my $thumbnailExtension = readConfig('alt_format');

    indir $root, {
        for readConfig('alt_sizes').split(' ') -> $size {
            %rosters{$size} = "roster-{$size}.txt".IO.open(:w);
        }

        if ($file) {
            testPathExistsInArchive($file);

            for %rosters.kv -> $size, $handle {
                $handle.say($file.relative($root));
                %counters{$size}++;
            }
        } else {
            for walkArchive($root) -> $path {
                for %rosters.kv -> $size, $handle {
                    my $relativePath = $path.relative($root);
                    my $target = $cacheRoot.add("$size/{$relativePath}").extension($thumbnailExtension);
                    next if $target ~~ :f;
                    $handle.say($relativePath.Str);
                    %counters{$size}++;
                }
            }
        }

        for %rosters.kv -> $size, $handle {
            $handle.close;

            unless ($handle.path ~~ :z) {
                my $count = %counters{$size};
                my $label = ($count == 1) ?? 'file' !! 'files';

                unless ($file) {
                    print colored("Generating {$count} {$label } at {$size}...", 'magenta');
                }

                my $proc = run qqw{
                    gm mogrify -output-directory _cache/$size -create-directories -format $thumbnailExtension -thumbnail $size
                }, "@roster-{$size}.txt", :out, :err;
                my $err = $proc.err.slurp(:close);
                my $out = $proc.out.slurp(:close);


                if ($proc.exitcode !== 0) {
                    say $err;
                    die ImageArchive::Exception::BadExit.new(:err($err));
                }

                unless ($file) {
                    say "done";
                }
            }

            $handle.path.unlink;
        }
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

    unless ($destination ~~ :d) {
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
sub walkArchive(IO::Path $dir) is export {
    my @skipExtensions := <bak db ini txt versions>;

    gather for dir $dir -> $path {
        next if $path.basename eq '_cache';
        next if $path.basename.starts-with('.');
        next if $path.extension ∈ @skipExtensions;
        if $path.d { .take for walkArchive($path) };
        if $path.f { take $path };
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
