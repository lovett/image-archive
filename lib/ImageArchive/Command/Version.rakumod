unit module ImageArchive::Command::Version;

our sub make-it-so() {
    say $?DISTRIBUTION.meta<ver>.Str;
}
