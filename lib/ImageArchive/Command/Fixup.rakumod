unit package ImageArchive::Command;

use ImageArchive::Archive;

our sub fixup(Bool :$dryrun) is export {
    pruneEmptyDirsDownward('', $dryrun);
    verifyDateTags($dryrun);
    generateAlts($dryrun);
}
