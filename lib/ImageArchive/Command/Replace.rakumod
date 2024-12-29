unit module ImageArchive::Command::Replace;

use Terminal::ANSIColor;

use ImageArchive::Archive;
use ImageArchive::Util;

our sub make-it-so(Str $target, Str $substitue, Bool :$dryrun) {
    my @targets = resolveFileTarget($target);
    replaceFilePreservingName(@targets.first.IO, $substitue.IO, $dryrun);

    CATCH {
        when ImageArchive::Exception::PathNotFoundInWorkspace {
            note colored($_.message, 'red');
            exit 1;
        }
    }
}

sub replaceFilePreservingName(IO::Path $original, IO::Path $substitue, Bool $dryrun = False) is export {
    testPathExistsInArchive($original);

    my $replacement = $substitue.dirname().IO.add($original.basename).extension($substitue.extension);

    if ($dryrun) {
        wouldHaveDone("Rename $substitue to $replacement");
        wouldHaveDone("Replace $original with $replacement");
        exit;
    }

    rename($substitue, $replacement);

    replaceFile($original, $replacement);
}
