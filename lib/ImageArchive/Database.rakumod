unit module ImageArchive::Database;

# Tell DBIish to pick up libsqlite from an alternate location.
#
# Normally this isn't necessary because the default location is
# suitable. On macOS, a newer version may be available elsewhere if a
# package manager like Macports is being used.
#
# The version of sqlite3 reported from the CLI client is not
# necessarily the same as the version of the library thatDBIish sees.
unless (%*ENV<DBIISH_SQLITE_LIB>) {
    my @extraLibPaths = qw| /opt/local/lib |.grep: { .IO.d };

    @extraLibPaths.grep({ .IO.dir(test => / libsqlite3 /) }).first: {
        %*ENV<DBIISH_SQLITE_LIB> = "{$_}/sqlite3";
    }
}

use DBIish;
#use Grammar::Tracer;

use ImageArchive::Config;
use ImageArchive::Tagging;
use ImageArchive::Exception;
use ImageArchive::Util;
use ImageArchive::Grammar::Range;
use ImageArchive::Grammar::Search;

# Drop stash rows by key
sub clearStashByKey(Str $key) is export {
    my $dbh = openDatabase();

    my $sth = $dbh.prepare(q:to/STATEMENT/);
    DELETE FROM stash WHERE key=?
    STATEMENT

    $sth.execute($key);
}

# Tally of all records.
sub countRecords() is export {
    my $dbh = openDatabase();

    my $sth = $dbh.execute(q:to/STATEMENT/);
    SELECT count(*) FROM archive
    STATEMENT

    my $row = $sth.row;
    return $row[0];
}

# Tally of records by month.
sub countRecordsByMonth(Int $year) is export {
    my $query = q:to/SQL/;
    WITH RECURSIVE months(i, name) AS (
        SELECT  0, 'Unknown'
        UNION ALL
        SELECT i+1, CASE i+1
          WHEN  1 THEN 'January'
          WHEN  2 THEN 'February'
          WHEN  3 THEN 'March'
          WHEN  4 THEN 'April'
          WHEN  5 THEN 'May'
          WHEN  6 THEN 'June'
          WHEN  7 THEN 'July'
          WHEN  8 THEN 'August'
          WHEN  9 THEN 'September'
          WHEN 10 THEN 'October'
          WHEN 11 THEN 'November'
          WHEN 12 THEN 'December'
        END
        FROM months
        WHERE i<12
    ) SELECT
      months.name, count(archive.id)
    FROM months
    LEFT JOIN archive ON
      months.i=CAST(substr(tags ->> '$.CreateDate', 6, 2) as number)
      AND CAST(substr(tags ->> '$.CreateDate', 0, 5) as number) = ?
    GROUP BY months.i
    ORDER BY months.i > 0 DESC, months.i ASC
    SQL

    my $dbh = openDatabase();
    my $sth = $dbh.execute($query, $year);

    return $sth.allrows();
}

# Tally of records by fulltext search.
sub countRecordsByTag(Str $query, Bool $debug = False) is export {
    my $parserActions = SearchActions.new(
        filters => readConfig('filters')
    );

    my $parsedQuery = Search.parse(
        $query,
        actions => $parserActions
    );

    my $dbh = openDatabase();

    my $ftsQuery = qq:to/SQL/;
    SELECT count(*) FROM archive_fts
    WHERE {$parsedQuery.made<ftsClause>}
    SQL

    my $sth = $dbh.execute($ftsQuery);

    return $sth.row[0];
}

# Tally of records by year.
sub countRecordsByYear() is export {
    my $query = q:to/SQL/;
    SELECT IFNULL(
        substr(tags ->> '$.CreateDate', 0, 5),
        'Unknown'
    ) AS year, count(*)
    FROM archive
    GROUP BY year
    ORDER BY year
    SQL

    my $dbh = openDatabase();
    my $sth = $dbh.execute($query);

    return $sth.allrows();
}

# Remove a file from the database.
sub deindexFile(IO::Path $file) is export {
    my $uuid = readRawTag($file, 'id');
    my $dbh = openDatabase();
    my $sth = $dbh.prepare('DELETE FROM archive WHERE uuid=?');

    $sth.execute($uuid);
}

# Retrieve the contents of the stash table for a given key.
sub dumpStash(Str $key) is export {
    my $stashQuery = qq:to/SQL/;
    SELECT path, series, seriesid FROM (
        SELECT json_extract(a.tags, '\$.SourceFile') as path,
        IFNULL(json_extract(a.tags, '\$.SeriesName'), 'unknown') as series,
        CAST(IFNULL(json_extract(a.tags, '\$.SeriesIdentifier'), 0) AS INT)  as seriesid,
        row_number()
        OVER (ORDER BY s.id) as rownum
        FROM archive a, stash s
        WHERE a.id=s.archive_id
        AND s.key=?
    )
    SQL

    my $dbh = openDatabase();
    my $sth = $dbh.execute($stashQuery, $key);

    return gather {
        for $sth.allrows(:array-of-hash) -> $row {
            $row<path> = (appPath('root') ~ $row<path>).IO;
            take $row;
        }
    }
}

# Store a file's tags in a database.
sub indexFile(IO $file) is export {
    my $uuid = readRawTag($file, 'id');
    my $proc = run <exiftool
    -x Composite:all
    -x EXIF:CreateDate
    -x EXIF:StripByteCounts
    -x EXIF:StripOffsets
    -x EXIF:ThumbnailImage
    -x EXIF:PreviewImageStart
    -x EXIF:PreviewImageLength
    -x EXIFTool:all
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
    my $root = appPath('root');
    $json ~~ s:g/ "{$root}" //;

    my $dbh = openDatabase();
    my $sth = $dbh.prepare(q:to/STATEMENT/);
    INSERT INTO archive (uuid, tags)
    VALUES (?, ?)
    ON CONFLICT (uuid) DO UPDATE
    SET tags=excluded.tags
    STATEMENT

    $sth.execute($uuid, $json);
}

# Look up one or more tags for a given file.
#
# This is the database-oriented equivalent of Tagging:readRawtags().
sub getTags(IO::Path $path, *@tags) is export {
    my $relativePath = relativePath($path);

    my $parserActions = SearchActions.new();

    my $parsedQuery = Search.parse(
        'sourcefile: ' ~ $relativePath,
        actions => $parserActions
    );

    my $selectSql = @tags.map(
        { "json_extract(a.tags, '\$.{$_}') as '$_'" }
    ).join(', ');


    my $query = qq:to/STATEMENT/;
    SELECT {$selectSql}
    FROM archive a JOIN archive_fts f ON a.id=f.rowid
    WHERE {$parsedQuery.made<ftsClause>}
    STATEMENT

    my $dbh = openDatabase();
    my $sth = $dbh.execute($query);

    return $sth.row(:hash);
}

# Open a connection to the SQLite database.
#
# Uses Raku's state declarator for connection reuse.
# See https://docs.raku.org/syntax/state
sub openDatabase() is export {
    state $dbh = DBIish.connect(
        'SQLite',
        database => appPath('database')
    );

    # Minimum version for FTS5.
    if ($dbh.parent.version < v3.9.0) {
        die "Sqlite version {$dbh.parent.version} is not supported. Need v3.9.0 or newer.";
    }

    return $dbh;
}

# The absolute path to the most-recently-imported file in the archive.
sub findByNewestImport(Int $limit = 1) returns Seq is export {
    my $query = q:to/SQL/;
    SELECT json_extract(a.tags, '$.SourceFile') as path,
    IFNULL(json_extract(a.tags, '$.SeriesName'), 'unknown') as series,
    CAST(IFNULL(json_extract(a.tags, '$.SeriesIdentifier'), 0) AS INT)  as seriesid
    FROM archive a
    ORDER BY a.rowid DESC
    LIMIT ?
    SQL

    my $dbh = openDatabase();
    my $sth = $dbh.execute($query, $limit);

    return gather {
        for $sth.allrows(:array-of-hash) -> $row {
            $row<path> = (appPath('root') ~ $row<path>).IO;
            take $row;
        }
    }
}

# Locate archive paths by index from a previous search.
sub findByStashIndex(Str $query, Str $key, Bool $debug = False) is export {
    my $parserActions = RangeActions.new;

    my $parsedQuery = Range.parse(
        $query,
        actions => $parserActions
    );

    unless ($parsedQuery) {
        return;
    }

    my $stashQuery = qq:to/SQL/;
    SELECT path, series, seriesid FROM (
        SELECT json_extract(a.tags, '\$.SourceFile') as path,
        IFNULL(json_extract(a.tags, '\$.SeriesName'), 'unknown') as series,
        CAST(IFNULL(json_extract(a.tags, '\$.SeriesIdentifier'), 0) AS INT)  as seriesid,
        row_number()
        OVER (ORDER BY s.id) as rownum
        FROM stash s, archive a
        WHERE s.archive_id=a.id
        AND s.key=?
    ) WHERE {$parsedQuery.made}
    SQL

    my $dbh = openDatabase();

    my $sth = $dbh.execute($stashQuery, $key);

    my $root = appPath('root');
    return gather {
        for $sth.allrows(:array-of-hash) -> $row {
            $row<path> = (appPath('root') ~ $row<path>).IO;
            take $row;
        }

        if ($debug) {
            say '';
            debug($stashQuery, 'stash query');
        }
    }
}

# Locate archive paths by closeness to an RGB color.
#
# This uses an SQLite extension loaded at runtime, but there are
# complications (no obvious way to invoke
# sqlite3_enable_load_extension() through DBIish). The workaround is
# to shell out to the sqlite3 command-line client where extension
# loading is already enabled. Once that happens a standard DBIish
# connection is used for followup queries that do not need the
# extension.
sub findBySimilarColor(@rgb, Str $key) is export {
    my $dbPath = appPath('database');

    my $proc = run 'sqlite3', $dbPath, :in, :err;

    my $extension = %?RESOURCES<colordelta.sqlite3extension>.IO.absolute;

    $proc.in.say: qq:to/SQL/;
    .load {$extension} sqlite3_colordelta_init

    DELETE FROM stash WHERE key='{$key}';

    INSERT INTO stash (key, score, archive_id)
    SELECT '{$key}',
      colordelta('{@rgb.join(',')}', json_extract(tags, '\$.AverageRGB'))
        AS delta,
      archive.id
    FROM archive
    WHERE delta < 10
    ORDER BY delta ASC;
    SQL

    $proc.in.close;

    my $err = $proc.err.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    my $dbh = openDatabase();

    my $stashQuery = qq:to/SQL/;
    SELECT json_extract(a.tags, '\$.SourceFile') as path, s.score
    FROM archive a, stash s
    WHERE a.id=s.archive_id AND s.key='{$key}'
    ORDER BY s.rowid
    SQL

    my $sth = $dbh.execute($stashQuery);

    my $root = appPath('root');
    return gather {
        for $sth.allrows(:array-of-hash) -> $row {
            $row<path> = (appPath('root') ~ $row<path>).IO;
            take $row;
        }
    }
}

sub findNewest(Int $limit, Str $key) is export {
    my $dbh = openDatabase();

    clearStashByKey($key);

    my $sth = $dbh.prepare(q:to/SQL/);
    INSERT INTO stash (key, archive_id)
    SELECT ?, a.rowid
    FROM archive a
    ORDER BY a.id DESC LIMIT ?
    SQL

    $sth.execute($key, $limit.Str);

    my $stashQuery = q:to/SQL/;
    SELECT json_extract(a.tags, '$.SourceFile') as path,
    IFNULL(json_extract(a.tags, '$.SeriesName'), 'unknown') as series,
    CAST(IFNULL(json_extract(a.tags, '$.SeriesIdentifier'), 0) AS INT)  as seriesid
    FROM archive a, stash s
    WHERE a.id=s.archive_id AND s.key=?
    ORDER BY s.rowid
    SQL

    $sth = $dbh.execute($stashQuery, $key);

    my $root = appPath('root');
    return gather {
        for $sth.allrows(:array-of-hash) -> $row {
            $row<path> = (appPath('root') ~ $row<path>).IO;
            take $row;
        }
    }
}

# Locate archive paths by fulltext search
sub findByTag(Str $query, Str $key, Bool $debug = False) is export {
    my $parserActions = SearchActions.new(
        filters => readConfig('filters')
    );

    my $parsedQuery = Search.parse(
        $query,
        actions => $parserActions
    );

    my $dbh = openDatabase();

    clearStashByKey($key);

    my $ftsQuery = qq:to/SQL/;
    INSERT INTO stash (key, archive_id)
    SELECT '{$key}', archive_fts.rowid
    FROM archive_fts
    JOIN archive ON archive_fts.rowid=archive.id
    WHERE {$parsedQuery.made<ftsClause>}
    SQL

    given $parsedQuery.made<order> {
        when 'filename' {
            $ftsQuery ~= 'ORDER BY json_extract(archive.tags, "$.FileName")';
        }

        default {
            $ftsQuery ~= q:to/SQL/;
            ORDER BY json_extract(archive.tags, '$.SeriesName'),
            CAST(IFNULL(json_extract(archive.tags, '$.SeriesIdentifier'), 0) AS INT),
            json_extract(archive.tags, "$.SourceFile")
            SQL
        }
    }

    $dbh.execute($ftsQuery);

    my $stashQuery = q:to/SQL/;
    SELECT json_extract(a.tags, '$.SourceFile') as path,
    IFNULL(json_extract(a.tags, '$.SeriesName'), 'unknown') as series,
    CAST(IFNULL(json_extract(a.tags, '$.SeriesIdentifier'), 0) AS INT)  as seriesid
    FROM archive a, stash s
    WHERE a.id=s.archive_id AND s.key=?
    ORDER BY s.rowid
    SQL

    my $sth = $dbh.execute($stashQuery, $key);

    return gather {
        for $sth.allrows(:array-of-hash) -> $row {
            $row<path> = (appPath('root') ~ $row<path>).IO;
            take $row;
        }

        if ($debug) {
            say '';
            debug($ftsQuery, 'fts query');
            debug($stashQuery, 'stash query');
        }
    }
}

sub stashPath(IO::Path $path, Str $key='searchresult') is export {
    my $relativePath = relativePath($path);

    my $dbh = openDatabase();

    state $sth = $dbh.prepare(qq:to/STATEMENT/);
    INSERT INTO stash (key, archive_id)
    SELECT '{$key}', a.id
    FROM archive a
    WHERE json_extract(a.tags, '\$.SourceFile') = ?
    STATEMENT

    $sth.execute($relativePath);
}
