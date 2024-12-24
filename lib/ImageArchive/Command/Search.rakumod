unit package ImageArchive::Command;

use ImageArchive::Activity;
use ImageArchive::Database;

our sub search(@terms, Int $limit, Bool $debug = False) is export {
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
