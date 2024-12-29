unit module ImageArchive::Command::Fixup;

use ImageArchive::Archive;

our sub make-it-so(Bool :$dryrun) {
    pruneEmptyDirsDownward('', $dryrun);
    verifyDateTags($dryrun);
    generateAlts($dryrun);
}
