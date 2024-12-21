unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub visit(Str $target) is export {
    my @targets = resolveFileTarget($target, 'parent');
    viewExternally(@targets);
}
