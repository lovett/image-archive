unit module ImageArchive::Database;

use DBIish;

use ImageArchive::Config;
use ImageArchive::Tagging;
use ImageArchive::Exception;

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
    has %!filters;

    method tag ($/) {
        my $formalTag = %!filters>{$/<name>};
        unless ($formalTag) {
            die ImageArchive::Exception::BadFilter.new(:filters(%!filters));
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
sub countRecords() is export {
    my $dbh = openDatabase();

    my $sth = $dbh.execute(q:to/STATEMENT/);
    SELECT count(*) FROM archive
    STATEMENT

    my $row = $sth.row;
    $dbh.dispose;
    return $row[0];
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
    -x ExifTool:all
    -x File:Directory
    -x File:FilePermissions
    -x ICC_Profile:all
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

# Locate paths within the archive by their metadata.
sub searchMetadata(Str $query) is export {
    my %filters = readConfig('filters');

    my $parsedQuery = Search.parse(
        $query,
        actions => SearchActions.new(:filters(%filters))
    );

    my $dbh = openDatabase();

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

    my $root = getPath('root');
    return gather {
        for $sth.allrows() -> $row {
            take relativePath($row[0]);
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
