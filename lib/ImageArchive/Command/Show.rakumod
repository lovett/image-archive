unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub show(Str $target) is export {
    my @targets = resolveFileTarget($target);
    showTags(@targets);
}
