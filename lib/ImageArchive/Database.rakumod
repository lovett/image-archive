unit module ImageArchive::Database;

use DBIish;
#use Grammar::Tracer;

use ImageArchive::Config;
use ImageArchive::Tagging;
use ImageArchive::Exception;
use ImageArchive::Util;

grammar Range {
    rule TOP {
        [ <range> | <barenumber> ]*
    }

    token separator {
        <[ \s , ]>
    }

    rule range {
        $<start> = \d+ '-' $<end> = \d+
    }

    rule barenumber {
        $<value> = \d+ <separator>*
    }
}

class RangeActions {
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

grammar Search {
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
        <[ \w \' \" \- \. ]>+
    }
}

class SearchActions {
    has $!tag = 'any';
    has %!terms;
    has %.filters;
    has $!order;

    method tag ($/) {
        if $/<name> eq 'order' {
            $!tag = $/<name>;
            return;
        }

        my $formalTag = %.filters{$/<name>};

        unless ($formalTag) {
            die ImageArchive::Exception::BadFilter.new(:filters(%.filters));
        }

        $!tag = $formalTag;
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
                    @fragments.append: "NEAR($key $phrase, $distance)";
                }
            }
        }

        $/.make: %(
            ftsClause => sprintf(
                "archive_fts MATCH '%s'",
                @fragments.join(' ')
            ),
            order => $!order
        )
    }
}

# Tally all records.
sub countRecords() is export {
    my $dbh = openDatabase();

    my $sth = $dbh.execute(q:to/STATEMENT/);
    SELECT count(*) FROM archive
    STATEMENT

    my $row = $sth.row;
    $dbh.dispose;
    return $row[0];
}

# Tally records by month.
sub countRecordsByMonth(Int $year) is export {
    my $dbh = openDatabase();
    my $sth = $dbh.execute('SELECT substr(json_extract(tags, "$.XMP.CreateDate"), 0, 5) as year,
    substr(json_extract(tags, "$.XMP.CreateDate"), 6, 2) as month,
    count(*) AS tally
    FROM archive
    WHERE year=?
    GROUP BY month
    ORDER BY month', $year.Str);

    return gather {
        for $sth.allrows(:array-of-hash) -> $row {
            take ($row<month>, $row<tally>);
        }
        $dbh.dispose;
    }
}

# Tally records by year.
sub countRecordsByYear() is export {
    my $dbh = openDatabase();
    my $sth = $dbh.execute('SELECT substr(json_extract(tags, "$.XMP.CreateDate"), 0, 5)
    AS year, count(*) AS tally
    FROM archive
    GROUP BY year
    ORDER BY year');

    return gather {
        for $sth.allrows(:array-of-hash) -> $row {
            take ($row<year>, $row<tally>);
        }
        $dbh.dispose;
    }
}



# Remove a file from the database.
sub deindexFile(IO::Path $file) is export {
    my $uuid = readRawTag($file, 'id');
    my $dbh = openDatabase();
    my $sth = $dbh.prepare(q:to/STATEMENT/);
    DELETE FROM archive WHERE uuid=?
    STATEMENT

    $sth.execute($uuid);
    $dbh.dispose;
}

# Store a file's tags in a database.
sub indexFile(IO $file) is export {
    my $uuid = readRawTag($file, 'id');
    my $proc = run <
    exiftool
    -x Composite:all
    -x EXIF:StripByteCounts
    -x EXIF:StripOffsets
    -x Exif:ThumbnailImage
    -x Exif:PreviewImageStart
    -x Exif:PreviewImageLength
    -x ExifTool:all
    -x File:Directory
    -x File:FilePermissions
    -x ICC_Profile:all
    -x MPF:all
    -json>, $file.Str, :out, :err;

    my Str $json = chomp($proc.out.slurp(:close));
    my $err  = $proc.err.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    # Exiftool generates a JSON array of one element.
    # Mangle it to just the element.
    $json ~~ s:g/ ^\[ | \]$ //;

    # Exiftool populates the SourceFile with an absolute path.
    # Make it root-relative.
    my $root = getPath('root');
    $json ~~ s:g/ "{$root}" //;

    my $dbh = openDatabase();
    my $sth = $dbh.prepare(q:to/STATEMENT/);
    INSERT INTO archive (uuid, tags)
    VALUES (?, ?)
    ON CONFLICT (uuid) DO UPDATE
    SET tags=excluded.tags
    STATEMENT

    $sth.execute($uuid, $json);
    $dbh.dispose;
}

# Open a connection to the SQLite database.
#
# Caller is responsible for disposing of the returned handle.
sub openDatabase() is export {
    return DBIish.connect(
        'SQLite',
        database => getPath('database')
    );
}

# Locate archive paths by index from a previous search.
sub findBySearchIndex(Str $query) is export {
    my $parserActions = RangeActions.new;

    my $parsedQuery = Range.parse(
        $query,
        actions => $parserActions
    );

    unless ($parsedQuery) {
        return;
    }

    my $dbh = openDatabase();

    my $sth = $dbh.execute("SELECT * FROM (
    SELECT json_extract(a.tags, '\$.SourceFile') as path, row_number()
    OVER (ORDER BY h.id) as rownum
    FROM archive a, history h
    WHERE a.id=h.value
    AND h.key='searchresults')
    WHERE {$parsedQuery.made}");

    return gather {
        for $sth.allrows() -> $row {
            take $row[0];
        }

        $dbh.dispose;
    }
}

# Locate archive paths by fulltext
sub searchMetadata(Str $query, Bool $debug = False) is export {
    my $parserActions = SearchActions.new(
        filters => readConfig('filters')
    );

    my $parsedQuery = Search.parse(
        $query,
        actions => $parserActions
    );

    my $dbh = openDatabase();

    $dbh.execute("DELETE FROM history
    WHERE key='searchresults'");

    my $ftsQuery = qq:to/SQL/;
    INSERT INTO history (key, value)
    SELECT 'searchresults', archive_fts.rowid
    FROM archive_fts
    JOIN archive ON archive_fts.rowid=archive.id
    WHERE {$parsedQuery.made<ftsClause>}
    SQL

    given $parsedQuery.made<order> {
        when 'series' {
            $ftsQuery ~= q:to/SQL/;
            ORDER BY json_extract(archive.tags, '$.SeriesName'),
            CAST(IFNULL(json_extract(archive.tags, '$.SeriesIdentifier'), 0) AS INT)
            SQL
        }

        when 'filename' {
            $ftsQuery ~= 'ORDER BY json_extract(archive.tags, "$.FileName")';
        }

        default {
            $ftsQuery ~= 'ORDER BY json_extract(archive.tags, "$.SourceFile")';
        }
    }

    $dbh.execute($ftsQuery);

    my $historyQuery = q:to/SQL/;
    SELECT json_extract(a.tags, '$.SourceFile') as path,
    IFNULL(json_extract(a.tags, '$.SeriesName'), 'unknown') as series,
    CAST(IFNULL(json_extract(a.tags, '$.SeriesIdentifier'), 0) AS INT)  as seriesid
    FROM archive a, history h
    WHERE a.id=h.value AND h.key='searchresults'
    ORDER BY h.rowid
    SQL

    my $sth = $dbh.execute($historyQuery);

    my $root = getPath('root');
    return gather {
        for $sth.allrows(:array-of-hash) -> $row {
            take $row;
        }

        if ($debug) {
            say '';
            debug($ftsQuery, 'fts query');
            debug($historyQuery, 'history query');
        }

        $dbh.dispose;
    }
}

# Establish (or update) the SQLite database.
sub applyDatabaseSchema() is export {
    my $dbPath = getPath('database');

    my $schemaPath = %?RESOURCES<schema-sqlite.sql>.absolute;

    my $proc = run 'sqlite3', $dbPath, :in;
    $proc.in.say(".read {$schemaPath}");
    $proc.in.close;

    CATCH {
        when X::Proc::Unsuccessful {
            my $err = "Failed to apply database schema.";
            ImageArchive::Exception::BadExit.new(:err($err)).throw;
        }
    }
}
