unit module ImageArchive::Command::Promote;

use ImageArchive::Archive;
use ImageArchive::Workspace;
use ImageArchive::Util;

# Move a file out of the workspace.
our sub run(Str $version, Bool :$dryrun) {
    my $file = $version.IO;

    testPathExistsInWorkspace($file);

    my $master = findWorkspaceMaster($file.parent);
    my $newMaster = $master.extension($file.extension);

    if ($dryrun) {
        wouldHaveDone("{$file} becomes {$newMaster}");
        return;
    }

    replaceFile($master, $newMaster);
}
