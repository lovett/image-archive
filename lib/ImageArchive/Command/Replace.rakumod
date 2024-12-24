unit module ImageArchive::Command::Replace;

use ImageArchive::Activity;

our sub run(Str $target, Str $substitue, Bool :$dryrun) {
    my @targets = resolveFileTarget($target);
    replaceFilePreservingName(@targets.first.IO, $substitue.IO, $dryrun);
}
