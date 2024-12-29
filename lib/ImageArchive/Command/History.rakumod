unit module ImageArchive::Command::History;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

our sub make-it-so(Str $target) {
    my @targets = resolveFileTarget($target);
    my $pager = getPager();

    for @targets -> $file {
        my $workspace = findWorkspace($file);
        my $log = findWorkspaceLog($workspace);

        next unless $log ~~ :f;

        for $log.lines -> $line {
            next unless $line.trim;
            next if $line.starts-with('#');
            $line.subst(/\*+\s/, "").say;
            $pager.in.print: "\n" if $line.starts-with('*');
        }
    }

    $pager.in.close;
}
