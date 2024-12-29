unit module ImageArchive::Command::Deport;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Exception;
use ImageArchive::Util;

sub make-it-so(Str $target, Bool $dryrun) is export {
    my @targets = resolveFileTarget($target);
    deportFiles(@targets, $*CWD.IO, $dryrun);
}

# Remove a file from the archive.
sub deportFiles(@files, IO $destinationDir, Bool $dryrun? = False) is export {
    my $root = appPath("root");
    my $file = @files.pop;

    testPathExistsInArchive($file);

    my $workspace = findWorkspace($file);
    my $parent = $file.parent;
    my $fileDestination = $destinationDir.add($file.basename);
    my $workspaceDestination = $destinationDir.add($workspace.basename);

    if ($fileDestination ~~ :f) {
        die ImageArchive::Exception::PathConflict.new(:path($fileDestination));
    }

    if ($workspaceDestination ~~ :d) {
        die ImageArchive::Exception::PathConflict.new(:path($workspaceDestination));
    }

    if ($dryrun) {
        wouldHaveDone("Move {relativePath($file, $root)} to {$fileDestination}");
        return;
    }

    deindexFile($file);
    move($file, $fileDestination);
    $fileDestination.IO.chmod(0o644);
    deleteAlts($file);

    if ($workspace ~~ :d) {
        moveWorkspace($workspace, $destinationDir, $dryrun);
    }

    pruneEmptyDirsUpward($parent);

    if (@files) {
        deportFiles(@files, $destinationDir, $dryrun);
    }
}
