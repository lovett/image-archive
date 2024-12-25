unit module ImageArchive::Command::Workon;

use ImageArchive::Archive;
use ImageArchive::Workspace;
use ImageArchive::Util;

our sub run(Str $target) {
    my @targets = resolveFileTarget($target);
    my $workspace = copyToWorkspace(@targets.first);
    viewExternally($workspace);
}
