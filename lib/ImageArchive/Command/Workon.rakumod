unit module ImageArchive::Command::Workon;

use ImageArchive::Activity;
use ImageArchive::Workspace;

our sub run(Str $target) {
    my @targets = resolveFileTarget($target);
    my $workspace = copyToWorkspace(@targets.first);
    viewExternally($workspace);
}
