unit package ImageArchive::Command;

use ImageArchive::Activity;
use ImageArchive::Database;

our sub import(IO::Path $file, Bool :$dryrun) is export {
    my $importedFile = importFile($file.IO, $dryrun);
    indexFile($importedFile);
    say "Imported as {$importedFile}";
}
