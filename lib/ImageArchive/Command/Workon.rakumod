unit module ImageArchive::Command::Workon;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

sub make-it-so(Str $target) is export {
    my @targets = resolveFileTarget($target);
    my $workspace = copyToWorkspace(@targets.first);
    my $command = viewCommand("directory");
    viewExternally($command, $workspace);
}
