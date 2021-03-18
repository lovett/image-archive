unit module ImageArchive::Formatters;

use Terminal::ANSIColor;
use ImageArchive::Config;
use ImageArchive::Workspace;

sub searchLogsFormatter(IO::Path $root, Regex $matcher) is export {
    my SetHash $cache = SetHash.new;
    for searchLogs($root, $matcher) -> ($path, $line) {
        if $path !(elem) $cache {
            print "\n" if $cache.elems > 0;
            say colored(relativePath($path), 'cyan underline');
        }

        say $line;
        $cache{$path} = True;
    }
}
