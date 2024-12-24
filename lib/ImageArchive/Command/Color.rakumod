unit module ImageArchive::Command::Color;

use ImageArchive::Activity;
use ImageArchive::Color;

our sub run(Str $target) {
    my @targets = resolveFileTarget($target);
    printColorTable(@targets);
}
