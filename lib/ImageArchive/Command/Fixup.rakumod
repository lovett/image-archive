unit module ImageArchive::Command::Fixup;

use ImageArchive::Archive;

our sub run(Bool :$dryrun) {
    pruneEmptyDirsDownward('', $dryrun);
    verifyDateTags($dryrun);
    generateAlts($dryrun);
}
