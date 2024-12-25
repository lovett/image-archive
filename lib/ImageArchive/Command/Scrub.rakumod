unit module ImageArchive::Command::Scrub;

use ImageArchive::Archive;

our sub run(Str $term, Str $value = '', Bool :$dryrun) {
    untagTerm($term, $value, $dryrun);
}
