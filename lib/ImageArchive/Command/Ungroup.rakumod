unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub ungroup(Str $target, Str $name, Bool :$dryrun) is export {
    my @targets = resolveFileTarget($target);
    ungroupFiles(@targets, $name, $dryrun);
}
