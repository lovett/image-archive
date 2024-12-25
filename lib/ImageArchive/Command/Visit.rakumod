unit module ImageArchive::Command::Visit;

use ImageArchive::Activity;
use ImageArchive::Archive;

our sub run(Str $target) {
    my @targets = resolveFileTarget($target, 'parent');
    viewExternally(@targets);
}
