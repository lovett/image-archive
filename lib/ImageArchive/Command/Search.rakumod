unit module ImageArchive::Command::Search;

use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Util;

sub make-it-so(Str $query, Int $limit, Bool $debug = False) is export {
    my $root = appPath('root');

    unless ($query) {
        note "No search terms were provided.";
        exit 1;
    }

    my @result = do given $query.words.head {
        when "lastimport" {
            findNewest(1, "searchresult")
        }

        when "recent" {
            findNewest($limit, "searchresult")
        }

        default {
            findByTag($query, "searchresult", $debug);
        }
    }

    my $pager = getPager();
    printSearchResults(@result, $pager, $root);
}
