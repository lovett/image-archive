unit module ImageArchive::Command::Show;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Tagging;

sub make-it-so(Str $target) is export {
    my @targets = resolveFileTarget($target);
    my %aliases = readConfig('aliases');

    for @targets -> $target {
        say readTags($target, %aliases.values);
    }
}
