unit module ImageArchive::Command::Reprompt;

use ImageArchive::Archive;
use ImageArchive::Database;
use ImageArchive::Tagging;

sub make-it-so($target, Bool $dryrun) is export {
    my @targets = resolveFileTarget($target);
    for @targets -> $target {
        my %newTags = askQuestions($target);

        tagFile($target, %newTags, $dryrun);
        next if $dryrun;

        if (isArchiveFile($target)) {
            my $workspace = findWorkspace($target);
            my $importedFile = importFile($target);
            if ($importedFile) {
                say "Relocated to {$importedFile}";

                if ($workspace ~~ :d) {
                    moveWorkspace($workspace, $importedFile.parent);
                }
                pruneEmptyDirsUpward($target.parent);
                indexFile($importedFile);
                next;
            }

            indexFile($target);
        }
    }
}
