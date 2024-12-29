unit module ImageArchive::Command::Visit;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

sub make-it-so(Str $target) is export {
    my @targets = resolveFileTarget($target, 'parent');
    my $command = viewCommand("directory");
    viewExternally($command, @targets);
}
