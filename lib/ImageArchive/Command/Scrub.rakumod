unit module ImageArchive::Command::Scrub;

use ImageArchive::Archive;

sub make-it-so(Str $term, Str $value = '', Bool $dryrun) is export {
    untagTerm($term, $value, $dryrun);
}
