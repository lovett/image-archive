unit module ImageArchive::Command::Show;

use ImageArchive::Config;
use ImageArchive::Activity;
use ImageArchive::Tagging;

our sub run(Str $target) {
    my @targets = resolveFileTarget($target);
    my %aliases = readConfig('aliases');

    for @targets -> $target {
        say readTags($target, %aliases.values);
    }
}
