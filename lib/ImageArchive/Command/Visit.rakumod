unit module ImageArchive::Command::Visit;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

our sub make-it-so(Str $target) {
    my @targets = resolveFileTarget($target, 'parent');
    my $command = viewCommand("directory");
    viewExternally($command, @targets);
}
