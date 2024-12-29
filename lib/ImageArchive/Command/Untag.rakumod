unit module ImageArchive::Command::Untag;

use ImageArchive::Archive;

our sub make-it-so(Str $target, Str $term, Str $value = '', Bool :$dryrun) {
    my @targets = resolveFileTarget($target);
    untagTerm(@targets, $term, $value, $dryrun);
}
