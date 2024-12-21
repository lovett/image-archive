unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub deport(Str $target, Bool :$dryrun) is export {
    my @targets = resolveFileTarget($target);
    deportFiles(@targets, $*CWD.IO, $dryrun);
}
