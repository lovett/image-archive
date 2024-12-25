unit module ImageArchive::Command::Import;

use ImageArchive::Database;

our sub run(IO::Path $file, Bool :$dryrun) {
    my $importedFile = importFile($file.IO, $dryrun);
    indexFile($importedFile);
    say "Imported as {$importedFile}";
}
