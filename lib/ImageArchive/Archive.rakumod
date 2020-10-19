unit module ImageArchive::Archive;

use Terminal::ANSIColor;

use ImageArchive::Database;
use ImageArchive::Util;

sub deleteAlts(%config, IO::Path $file) {
    my $root = %config<_><root>;
    my $relativePath = $file.relative($root).IO;

    my $thumbnailExtension = %config<_><alt_format>;

    for %config<_><alt_sizes>.split(' ') -> $size {
        my $target = %config<_><root>.IO.add("_cache/$size/$relativePath").extension($thumbnailExtension);
        say $target;
        $target.IO.unlink;
    }
}

# Remove a file from the archive.
sub deportFile(%config, IO $file, IO $parent, Bool $dryRun? = False) is export {
    testPathExistsInArchive(%config, $file);

    my $destination = $parent.add($file.basename);

    if ($destination.IO ~~ :f) {
        confirm("Overwrite {$file.basename} in {$parent}?");
    }

    if ($dryRun) {
        wouldHaveDone("Remove {$file} from the database.");
        wouldHaveDone("Move {$file} to {$destination}");
        wouldHaveDone("Chmod {$destination} to read-write");
        return;
    }

    deindexFile(%config, $file);
    move($file, $destination);
    $destination.IO.chmod(0o600);
    deleteAlts(%config, $file);
}

# Resize and thumbnail via GraphicsMagick.
#
# If a path is not given, the archive is walked.
sub generateAlts(%config, IO::Path $file?) is export {
    my %rosters;
    my %counters;
    my $thumbnailExtension = %config<_><alt_format>;

    indir %config<_><root>, {
        for %config<_><alt_sizes>.split(' ') -> $size {
            %rosters{$size} = "roster-{$size}.txt".IO.open(:w);
        }

        if ($file) {
            testPathExistsInArchive(%config, $file);

            for %rosters.kv -> $size, $handle {
                $handle.say($file.relative(%config<_><root>));
                %counters{$size}++;
            }
        } else {
            my $callback = sub ($path) {
                for %rosters.kv -> $size, $handle {
                    my $target = %config<_><root>.IO.add("_cache/$size/$path").extension($thumbnailExtension);
                    next if $target ~~ :f;
                    $handle.say($path);
                    %counters{$size}++;
                }
            }

            walkArchive(%config, $callback);
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
sub importFile(%config, IO $file, IO $parent, Bool $dryRun? = False) is export {
    unless ($parent ~~ :d) {
        if ($dryRun) {
            wouldHaveDone("mkdir {$parent}");
        } else {
            $parent.mkdir();
        }
    }

    my $destination = $parent.add($file.basename);

    if ($destination ~~ :f) {
        die ImageArchive::Exception::FileExists.new(:path($destination));
    }

    if ($dryRun) {
        wouldHaveDone("Move {$file} to {$destination}");
        wouldHaveDone("Chmod {$destination} to read-only.");
        wouldHaveDone("Add {$destination} to the database.");
        wouldHaveDone("Generate alternate image sizes.");
        return;
    }

    my $root = %config<_><root>;
    move($file, $destination);
    $destination.IO.chmod(0o400);
    indexFile(%config, $destination);
    generateAlts(%config, $destination);
    say "Imported {$file.basename} to {$destination}";
}

# See if a file exists within the archive root.
sub testPathExistsInArchive(%config, IO $file) is export {
    return if $file.absolute.starts-with(%config<_><root>) && ($file ~~ :e);
    die ImageArchive::Exception::PathNotFoundInArchive.new;
}

# Perform an action on each file in the archive.
sub walkArchive(%config, Callable $callback) is export {
    my $root = %config<_><root>.IO;

    my @stack = $root;
    my @skipExtensions := <db bak txt>;

    while (@stack)  {
        for @stack.pop.dir -> $path {
            next if $path.IO.basename.starts-with('.');
            next if $path.IO.extension ∈ @skipExtensions;

            if ($path ~~ :d) {
                my $topDir = $path.relative($root).split('/', 2).first;
                next if $topDir eq '_cache';

                @stack.push($path);
                next;
            }


            $callback($path.relative($root));
        }
    }
}
