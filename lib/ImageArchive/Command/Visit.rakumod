unit module ImageArchive::Command::Visit;

use ImageArchive::Archive;
use ImageArchive::Util;

our sub run(Str $target) {
    my @targets = resolveFileTarget($target, 'parent');
    viewExternally(@targets);
}
