unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub view(Str $target, Bool :$original) is export {
    my $flavor = ($original ?? 'original' !! 'alternate');
    my @targets = resolveFileTarget($target, $flavor);
    say @targets;
    #viewExternally(@targets);
}
