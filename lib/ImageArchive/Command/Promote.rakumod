unit module ImageArchive::Command::Promote;

use ImageArchive::Archive;
use ImageArchive::Util;

# Move a file out of the workspace.
sub make-it-so(Str $version, Bool $dryrun) is export {
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
