unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub group(Str $target, Str $name, Bool :$dryrun) is export {
    my @targets = resolveFileTarget($target);
    groupFiles(@targets, $name, $dryrun);
}
