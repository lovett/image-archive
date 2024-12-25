unit module ImageArchive::Grammar::Search;

use ImageArchive::Exception;

grammar Search is export {
    rule TOP {
        [ <tag> | <date> | <term> ]*
    }

    rule tag {
        $<name> = [ \w+ ] ':'
    }

    token date {
        <[ \d \- ]>+
    }

    token term {
        <[ \w \' \" \- \. \/ ]>+
    }
}

class SearchActions is export {
    has $!tag = 'any';
    has %!terms;
    has %.filters;
    has $!order;

    method tag ($/) {
        $!tag = $.filters{$/<name>} // $/<name>;
    }

    method term ($/) {
        %!terms{$!tag}.append($/.subst(/\W/, '+', :g));
    }

    method date ($/) {
        %!terms{$!tag}.append(sprintf('"%s"', $/.subst(/\-/, ':', :g)));
    }

    method TOP ($/) {
        my @clauses;
        my $distance = 10;

        my @fragments;
        for %!terms.kv -> $key, @values {
            my $phrase = @values.join(' ');

            given $key {
                when 'any' {
                    @fragments.append: $phrase;
                }

                when 'order' {
                    $!order = $phrase;
                }

                default {
                    given $phrase {
                        when 'unknown' {
                            @fragments.append("(SourceFile NOT $key)");
                        }

                        when 'any' {
                            @fragments.append("(SourceFile AND $key)");
                        }

                        default {
                            @fragments.append: "NEAR($key $phrase, $distance)";
                        }
                    }
                }
            }
        }

        $/.make: %(
            tag => $!tag,
            terms => %!terms,
            ftsClause => sprintf(
                "archive_fts MATCH '%s'",
                @fragments.join(' AND ')
            ),
            order => $!order
        )
    }
}
