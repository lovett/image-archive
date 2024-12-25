unit module ImageArchive::Command::Search;

use ImageArchive::Database;
use ImageArchive::Util;

our sub run(@terms, Int $limit, Bool $debug = False) {
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

    printSearchResults(@result);
}
