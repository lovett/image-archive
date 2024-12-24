unit package ImageArchive::Command;

use ImageArchive::Config;
use ImageArchive::Activity;
use ImageArchive::Tagging;

our sub show(Str $target) is export {
    my @targets = resolveFileTarget($target);
    my %aliases = readConfig('aliases');

    for @targets -> $target {
        say readTags($target, %aliases.values);
    }
}
