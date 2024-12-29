unit module ImageArchive::Command::Reindex;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Tagging;

sub make-it-so(Str $target) is export {
    my @paths = resolveFileTarget($target);
    run(@paths);
}

multi sub make-it-so() {
    my $root = appPath('root');
    my @paths =  walkArchive($root).List;
    run(@paths);
}

multi sub make-it-so(@paths) {
    for @paths -> $path {
        print "Reindexing {$path}...";
        tagFile($path, {});
        indexFile($path);
        say "done.";
    }
}
