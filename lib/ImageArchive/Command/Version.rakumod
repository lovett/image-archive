unit module ImageArchive::Command::Version;

our sub run() {
    say $?DISTRIBUTION.meta<ver>.Str;
}
