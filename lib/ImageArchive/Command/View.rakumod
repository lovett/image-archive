unit module ImageArchive::Command::View;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

sub make-it-so(Str $target, Bool :$original) is export {
    my $flavor = ($original ?? 'original' !! 'alternate');
    my @targets = resolveFileTarget($target, $flavor);
    my $command = viewCommand("file");
    viewExternally($command, @targets);
}
