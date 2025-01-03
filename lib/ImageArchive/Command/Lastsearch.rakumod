unit module ImageArchive::Command::Lastsearch;

use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Util;

our sub make-it-so() {
    my $root = appPath('root');
    my @results = dumpStash('searchresult');
    my $pager = getPager();
    printSearchResults(@results, $pager, $root);
}
