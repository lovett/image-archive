unit module ImageArchive::Util;

use Terminal::ANSIColor;

# Convert a comma-delimited list of values to a list.
sub commaSplit(Str $value) is export {
    $value.split(/ \s* \, \s* /);
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

# Print a messsage to stdout indicating what would have happened if
# the --dryrun flag had not been specified.
sub wouldHaveDone(Str $message) is export {
    say colored("DRYRUN", "magenta") ~ " " ~ $message;
}
