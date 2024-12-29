unit module ImageArchive::Command::Import;

use ImageArchive::Database;

our sub make-it-so(IO::Path $file, Bool :$dryrun) {
    my $importedFile = importFile($file.IO, $dryrun);
    indexFile($importedFile);
    say "Imported as {$importedFile}";
}
