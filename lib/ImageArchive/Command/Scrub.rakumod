unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub scrub(Str $term, Str $value = '', Bool :$dryrun) is export {
    untagTerm($term, $value, $dryrun);
}
