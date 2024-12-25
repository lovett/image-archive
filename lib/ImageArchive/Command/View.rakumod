unit module ImageArchive::Command::View;

use ImageArchive::Archive;
use ImageArchive::Util;

our sub run(Str $target, Bool :$original) {
    my $flavor = ($original ?? 'original' !! 'alternate');
    my @targets = resolveFileTarget($target, $flavor);
    viewExternally(@targets);
}
