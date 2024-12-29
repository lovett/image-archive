unit module ImageArchive::Command::Import;

use ImageArchive::Database;

sub make-it-so(IO::Path $file, Bool $dryrun) is export {
    my $importedFile = importFile($file.IO, $dryrun);
    indexFile($importedFile);
    say "Imported as {$importedFile}";
}
