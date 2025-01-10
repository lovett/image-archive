unit module ImageArchive::Command::Untag;

use ImageArchive::Archive;

multi sub make-it-so(Str $target, Str $term, Str $value = '', Bool $dryrun = False) is export {
    my @targets = resolveFileTarget($target);
    untagTerm(@targets, $term, $value, $dryrun);
}

multi sub make-it-so("all", Str $term, Str $value = '', Bool $dryrun = False) is export {
    untagTerm($term, $value, $dryrun);
}
