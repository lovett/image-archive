unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub tag(Str $target, Bool :$dryrun, *@keywords) is export {
    my @targets = resolveFileTarget($target);
    tagAndImport(@targets, @keywords, $dryrun);
}
