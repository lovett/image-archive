unit module ImageArchive::Command::Fixup;

use ImageArchive::Archive;

sub make-it-so(Bool $dryrun) is export {
    pruneEmptyDirsDownward('', $dryrun);
    verifyDateTags($dryrun);
    generateAlts($dryrun);
}
