unit module ImageArchive::Command::Scrub;

use ImageArchive::Archive;

our sub make-it-so(Str $term, Str $value = '', Bool :$dryrun) {
    untagTerm($term, $value, $dryrun);
}
