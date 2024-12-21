unit package ImageArchive::Command;

use ImageArchive::Activity;
use ImageArchive::Database;

our sub search(Int :$limit = 10, Bool :$debug, *@terms) is export {
    unless (@terms) {
        note 'No search terms were provided.';
        exit 1;
    }

    my $query = @terms.join(' ');

    my @results;
    given $query {
        when 'lastimport' {
            @results = findNewest(1, 'searchresult');
        }

        when 'recent' {
            @results = findNewest($limit, 'searchresult');
        }

        default {
            @results = findByTag($query, 'searchresult', $debug);
        }
    }

    printSearchResults(@results);
}
