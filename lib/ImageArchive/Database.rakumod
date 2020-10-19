unit module ImageArchive::Database;

use DBIish;

use ImageArchive::Config;
use ImageArchive::Tagging;

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
    has %!config;

    method tag ($/) {
        my $formalTag = %!config<filters>{$/<name>};
        unless ($formalTag) {
            die ImageArchive::Exception::BadFilter.new;
        }

        $!tag = $formalTag;
    }

    method term ($/) {
        %!terms{$!tag}.append($/.subst(/\W/, '', :g));
    }

    method date ($/) {
        %!terms{$!tag}.append('"' ~ $/.subst(/\-/, ':', :g) ~ '"');
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

                default {
                    @fragments.append: "NEAR($key $phrase, $distance)";
                }
            }
        }

        $/.make: "archive_fts MATCH '" ~ @fragments.join(' ') ~ "'";
    }
}

# Count metadata rows in the database.
sub countRecords(%config) is export {
    my $dbh = openDatabase(%config);

    my $sth = $dbh.execute(q:to/STATEMENT/);
    SELECT count(*) FROM archive
    STATEMENT

    my $row = $sth.row;
    $dbh.dispose;
    return $row[0];
}


# Remove a file from the database.
sub deindexFile(%config, IO $file) is export {
    my $uuid = readTag(%config, $file, 'id');
    my $dbh = openDatabase(%config);
    my $sth = $dbh.prepare(q:to/STATEMENT/);
    DELETE FROM archive WHERE uuid=?
    STATEMENT

    $sth.execute($uuid);
    $dbh.dispose;
}

# Store a file's tags in a database.
sub indexFile(%config, IO $file) is export {
    my $uuid = readTag(%config, $file, 'id');
    my $proc = run <
    exiftool
    -x Composite:all
    -x EXIF:StripByteCounts
    -x EXIF:StripOffsets
    -x Exif:ThumbnailImage
    -x ExifTool:all
    -x File:Directory
    -x File:FilePermissions
    -x MPF:all
    -j -g -struct>, $file.Str, :out, :err;

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
    $json ~~ s:g/ "{%config<_><root>}" //;

    my $dbh = openDatabase(%config);
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
sub openDatabase(%config) is export {
    my $dbPath = getDatabasePath(%config);
    return DBIish.connect("SQLite", database => $dbPath);
}

# Locate paths within the archive by their metadata.
sub searchMetadata(%config, Str $query) is export {
    my $parsedQuery = Search.parse($query, actions => SearchActions.new(:config => %config));

    my $dbh = openDatabase(%config);

    $dbh.execute("DELETE FROM history
    WHERE key='searchresults'");

    $dbh.execute("INSERT INTO history (key, value)
    SELECT 'searchresults', rowid
    FROM archive_fts
    WHERE {$parsedQuery.made}");

    my $sth = $dbh.execute("SELECT json_extract(a.tags, '\$.SourceFile') as path
    FROM archive a, history h
    WHERE a.id=h.value AND h.key='searchresults'
    ORDER BY h.id");

    return gather {
        for $sth.allrows() -> $row {
            take relativePath(%config, $row[0]);
        }

        $dbh.dispose;
    }
}
