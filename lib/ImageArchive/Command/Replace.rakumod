unit module ImageArchive::Command::Replace;

use Terminal::ANSIColor;

use ImageArchive::Activity;

our sub run(Str $target, Str $substitue, Bool :$dryrun) {
    my @targets = resolveFileTarget($target);
    replaceFilePreservingName(@targets.first.IO, $substitue.IO, $dryrun);

    CATCH {
        when ImageArchive::Exception::PathNotFoundInWorkspace {
            note colored($_.message, 'red');
            exit 1;
        }
    }
}
