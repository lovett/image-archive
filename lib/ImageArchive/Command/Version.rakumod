unit package ImageArchive::Command;

our sub version() is export {
    say $?DISTRIBUTION.meta<ver>.Str;
}
