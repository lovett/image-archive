unit package ImageArchive::Command;

use ImageArchive::Activity;
use ImageArchive::Workspace;

our sub workon(Str $target) is export {
    my @targets = resolveFileTarget($target);
    my $workspace = copyToWorkspace(@targets.first);
    viewExternally($workspace);
}
