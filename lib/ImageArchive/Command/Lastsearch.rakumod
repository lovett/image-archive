unit module ImageArchive::Command::Lastsearch;

use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Util;

sub make-it-so() is export {
    my $root = appPath('root');
    my @results = dumpStash('searchresult');
    my $pager = getPager();
    printSearchResults(@results, $pager, $root);
}
