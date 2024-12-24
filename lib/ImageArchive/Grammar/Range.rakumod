unit package ImageArchive::Grammar;

grammar Range is export {
    rule TOP {
        [ <range> | <barenumber> ]*
    }

    token separator {
        ','
    }

    rule range {
        $<start> = \d+ '-' $<end> = \d+
    }

    rule barenumber {
        $<value> = \d+ <separator>*
    }
}

class RangeActions is export {
    has @!indices;
    has @!ranges;

    method barenumber ($/) {
        @!indices.push: $/<value>;
    }

    method range ($/) {
        @!ranges.push: ($/<start>, $/<end>);
    }

    method TOP ($/) {
        my $sql;
        if (@!indices) {
            $sql ~= sprintf(
                "rownum IN (%s)",
                @!indices.join(',')
            )
        }

        if (@!indices && @!ranges) {
            $sql ~= ' OR ';
        }

        if (@!ranges) {
            my @clauses = ( "(rownum BETWEEN {.list[0]} AND {.list[1]})" for @!ranges );
            $sql ~= @clauses.join(' OR ');
        }

        $/.make: $sql;
    }
}
