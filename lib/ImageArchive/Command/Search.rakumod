unit module ImageArchive::Command::Search;

use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Util;

our sub make-it-so(@terms, Int $limit, Bool $debug = False) {
    my $root = appPath('root');

    unless (@terms) {
        note "No search terms were provided.";
        exit 1;
    }

    my @result = do given @terms.head {
        when "lastimport" {
            findNewest(1, "searchresult")
        }

        when "recent" {
            findNewest($limit, "searchresult")
        }

        default {
            my $query = @terms.join(" ");
            findByTag($query, "searchresult", $debug);
        }
    }

    my $pager = getPager();
    printSearchResults(@result, $pager, $root);
}
