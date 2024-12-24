unit module ImageArchive::Command::View;

use ImageArchive::Activity;

our sub run(Str $target, Bool :$original) {
    my $flavor = ($original ?? 'original' !! 'alternate');
    my @targets = resolveFileTarget($target, $flavor);
    say @targets;
    #viewExternally(@targets);
}
