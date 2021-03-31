=begin pod
This module is for multi-step operations invoked from the main script.
=end pod

unit module ImageArchive::Recipe;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Workspace;

use Terminal::ANSIColor;

#| Locate lines in log files matching a regex.
sub searchLogs(Regex $matcher, Str $directory?) is export {
    my SetHash $cache = SetHash.new;

    my IO::Path $root = getPath('root');
    if ($directory) {
        $root = findDirectory($directory);
    }

    for walkArchive($root, /history\.org/) -> $path {
        for $path.lines.grep($matcher) -> $line {
            if $path !(elem) $cache {
                print "\n" if $cache.elems > 0;
                say colored(relativePath($path.dirname), 'cyan underline');
            }

            say $line;
            $cache{$path} = True;
        }
    }
}
