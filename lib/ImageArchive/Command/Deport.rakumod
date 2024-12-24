unit module ImageArchive::Command::Deport;

use ImageArchive::Activity;

our sub run(Str $target, Bool :$dryrun) {
    my @targets = resolveFileTarget($target);
    deportFiles(@targets, $*CWD.IO, $dryrun);
}
