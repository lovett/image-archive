unit module ImageArchive::Command::View;

use ImageArchive::Activity;
use ImageArchive::Archive;

our sub run(Str $target, Bool :$original) {
    my $flavor = ($original ?? 'original' !! 'alternate');
    my @targets = resolveFileTarget($target, $flavor);
    viewExternally(@targets);
}
