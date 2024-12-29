unit module ImageArchive::Command::Version;

sub make-it-so() is export {
    say $?DISTRIBUTION.meta<ver>.Str;
}
