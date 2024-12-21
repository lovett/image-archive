unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub untag(Str $target, Str $term, Str $value = '', Bool :$dryrun) is export {
    my @targets = resolveFileTarget($target);
    untagTerm(@targets, $term, $value, $dryrun);
}
