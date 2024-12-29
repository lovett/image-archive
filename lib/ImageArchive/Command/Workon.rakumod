unit module ImageArchive::Command::Workon;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

our sub make-it-so(Str $target) {
    my @targets = resolveFileTarget($target);
    my $workspace = copyToWorkspace(@targets.first);
    my $command = viewCommand("directory");
    viewExternally($command, $workspace);
}
