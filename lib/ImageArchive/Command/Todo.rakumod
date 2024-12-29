unit module ImageArchive::Command::Todo;

use Terminal::ANSIColor;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Util;

#| Locate lines in log files matching a regex.
our sub make-it-so(Str $directory?) {
    my $root = appPath("root");
    my $matcher = /TODO/;
    my SetHash $cache = SetHash.new;
    my $pager = getPager();

    if ($directory) {
        $root = $root.add($directory);
    }

    my $counter = 0;

    clearStashByKey('searchresult');

    for walkArchive($root, /history\.org/) -> $path {
        for $path.lines.grep($matcher) -> $line {
            if $path !(elem) $cache {
                $counter++;
                my $workspaceMaster = findWorkspaceMaster($path.dirname.IO);
                stashPath($workspaceMaster);

                $pager.in.print: "\n" if $cache.elems > 0;

                $pager.in.printf(
                    "%s | %s\n",
                    colored(sprintf("%3d", $counter), 'white on_blue'),
                    relativePath($workspaceMaster, $root)
                )
            }

            $pager.in.say: $line.subst(/ ^\W*/, '    | ');
            $cache{$path} = True;
        }
    }

    $pager.in.close;
}
