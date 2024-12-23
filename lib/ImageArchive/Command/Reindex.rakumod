unit package ImageArchive::Command;

use ImageArchive::Config;
use ImageArchive::Activity;
use ImageArchive::Tagging;
use ImageArchive::Archive;
use ImageArchive::Database;

multi sub reindex(Str $target) is export {
    my @paths = resolveFileTarget($target);
    reindex(@paths);
}

multi sub reindex() is export {
    my $root = appPath('root');
    my @paths =  walkArchive($root).List;
    reindex(@paths);
}

multi sub reindex(@paths) is export {
    for @paths -> $path {
        print "Reindexing {$path}...";
        tagFile($path, {});
        indexFile($path);
        say "done.";
    }
}
