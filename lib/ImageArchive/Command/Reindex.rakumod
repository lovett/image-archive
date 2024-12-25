unit module ImageArchive::Command::Reindex;

use ImageArchive::Config;
use ImageArchive::Tagging;
use ImageArchive::Archive;
use ImageArchive::Database;

multi sub run(Str $target) is export {
    my @paths = resolveFileTarget($target);
    run(@paths);
}

multi sub run() {
    my $root = appPath('root');
    my @paths =  walkArchive($root).List;
    run(@paths);
}

multi sub run(@paths) {
    for @paths -> $path {
        print "Reindexing {$path}...";
        tagFile($path, {});
        indexFile($path);
        say "done.";
    }
}
