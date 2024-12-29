unit module ImageArchive::Command::Untag;

use ImageArchive::Archive;

sub make-it-so(Str $target, Str $term, Str $value = '', Bool $dryrun) is export {
    my @targets = resolveFileTarget($target);
    untagTerm(@targets, $term, $value, $dryrun);
}
