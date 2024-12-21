unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub replace(Str $target, Str $substitue, Bool :$dryrun) is export {
    my @targets = resolveFileTarget($target);
    replaceFilePreservingName(@targets.first.IO, $substitue.IO, $dryrun);
}
