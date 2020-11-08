-- The schema below intentionally does not enable the WAL journal_mode
-- pragma. Based on the disadvantages documented at
-- https://sqlite.org/wal.html, the main one of interest to this
-- application is not being able to use network filesystems. Also, the
-- application doesn't really have any troubles with blocking between
-- readers and writers.

CREATE TABLE IF NOT EXISTS history (
    id INTEGER PRIMARY KEY,
    key TEXT,
    value TEXT
);

CREATE TABLE IF NOT EXISTS archive (
    id INTEGER PRIMARY KEY,
    uuid TEXT,
    tags TEXT
);

DROP TABLE IF EXISTS archive_fts;

CREATE VIRTUAL TABLE archive_fts USING fts5(
    tags, content=archive, content_rowid=id,
    tokenize='porter unicode61'
);

INSERT INTO archive_fts(rowid, tags)
SELECT id, tags from archive;


-- Indexes

CREATE INDEX IF NOT EXISTS history_key
ON history(key);

CREATE UNIQUE INDEX IF NOT EXISTS archive_uuid
ON archive(uuid);


-- Triggers

CREATE TRIGGER IF NOT EXISTS archive_after_insert
AFTER INSERT ON archive
BEGIN
    INSERT INTO archive_fts(rowid, tags)
    VALUES (new.id, new.tags);
END;

CREATE TRIGGER IF NOT EXISTS archive_after_delete
AFTER DELETE ON archive
BEGIN
    INSERT INTO archive_fts(archive_fts, rowid, tags)
    VALUES('delete', old.id, old.tags);
END;

CREATE TRIGGER IF NOT EXISTS archive_after_update
AFTER UPDATE ON archive
BEGIN
    INSERT INTO archive_fts(archive_fts, rowid, tags)
    VALUES('delete', old.id, old.tags);

    INSERT INTO archive_fts(rowid, tags)
    VALUES (new.id, new.tags);
END;
