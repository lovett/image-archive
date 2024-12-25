unit module ImageArchive::Command::Lastsearch;

use ImageArchive::Database;
use ImageArchive::Util;

our sub run() {
    my @results = dumpStash('searchresult');
    printSearchResults(@results);
}
