unit module ImageArchive::Util;

use Terminal::ANSIColor;

# Extract version information from META6.json
# Can't do this directly from the main script.
sub applicationVersion() is export returns Str {
    return $?DISTRIBUTION.meta<ver>.Str;
}

# Ask a yes-or-no question and exit if the answer isn't yes.
sub confirm(Str $question) is export {
    exit unless (prompt "{$question} [y/N]: ") eq 'y';
}

# Create a new UUID using external utilities.
sub generateUuid() is export {
    my @generators = </proc/sys/kernel/random/uuid /usr/bin/uuidgen>;

    for @generators -> $generator {
        next unless ($generator.IO.f);

        if ($generator.starts-with('/proc/')) {
            my $id = $generator.IO.slurp();
            return chomp($id);
        } else {
            my $proc = run $generator, :out, :err;
            my $id = $proc.out.slurp(:close);

            if ($proc.exitcode == 0) {
                return chomp($id);
            }
        }
    }

    die ImageArchive::Exception::UUID.new();
}

# Get the hash of a file path using external utilities.
sub hashFile(IO $path) returns Str is export {
    my @executables = <md5 md5sum>;

    for @executables -> $exe {
        my $proc = run $exe, $path, :out, :err;
        my $out = $proc.out.slurp(:close);

        if ($proc.exitcode == 0) {
            return $out.split(' ').first;
        }
    }

    return '';
}

# Pick the singular or plural form based on a quantity.
sub pluralize(Int $quantity, Str $singular, Str $plural) is export {
    my $label = ($quantity === 1) ?? $singular !! $plural;
    return sprintf("%d %s", $quantity, $label);
}

# Canonical formatting for series name with id.
sub formattedSeriesId($series, $id) is export {
    return sprintf('%s-%03d', $series, $id);
}

# Print a messsage to stdout indicating what would have happened if
# the --dryrun flag had not been specified.
sub wouldHaveDone(Str $message) is export {
    say sprintf('%s %s', colored('DRYRUN', 'white on_magenta'), $message);
}

# Print a troubleshooting message to stdout.
sub debug(Str $message, Str $label='') is export {
    my $header = "-- DEBUG $label";

    say colored($header, 'yellow');
    say colored('-' x $header.chars, 'yellow');
    say $message.chomp;
    say "";
}

# Convert an absolute path to a root-relative path.
sub relativePath($file, $root --> IO::Path) is export {
    my $relpath = $file.subst(/^ $root \/* /, '');
    return $relpath.IO;
}

sub printSearchResults(@results, $pager, $root) is export {
    my $counter = 0;

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

        @columns.push: $result<path>;

        $pager.in.say: @columns.join(" | ");
    }

    unless ($counter) {
        note 'No matches.';
    }

    $pager.in.close;
}

# Display one or more files in an external application.
sub viewExternally(Str $command, *@paths) is export {
    # Using shell rather than run for maximum compatibility.
    my $proc = shell "$command {@paths}", :err;
    my $err = $proc.err.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }
}
