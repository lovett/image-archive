unit package ImageArchive::Command;

use ImageArchive::Activity;
use ImageArchive::Color;

our sub color(Str $target) is export {
    my @targets = resolveFileTarget($target);
    printColorTable(@targets);
}
