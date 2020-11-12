-- The schema below intentionally does not enable the WAL journal_mode
-- pragma. Based on the disadvantages documented at
-- https://sqlite.org/wal.html, the main one of interest to this
-- application is not being able to use network filesystems. Also, the
-- application doesn't really have any troubles with blocking between
-- readers and writers.

PRAGMA foreign_keys = ON;

-- Tables

CREATE TABLE stash (
    id INTEGER PRIMARY KEY,
    key TEXT,
    score REAL DEFAULT NULL,
    archive_id INTEGER,
    FOREIGN KEY (archive_id) REFERENCES archive(id)
      ON DELETE CASCADE
);

CREATE INDEX stash_key ON stash(key);

CREATE TABLE archive (
    id INTEGER PRIMARY KEY,
    uuid TEXT,
    tags TEXT
);

CREATE VIRTUAL TABLE archive_fts USING fts5(
    tags, content=archive, content_rowid=id,
    tokenize='porter unicode61'
);

CREATE UNIQUE INDEX archive_uuid ON archive(uuid);

-- Triggers

CREATE TRIGGER archive_after_insert
AFTER INSERT ON archive
BEGIN
    INSERT INTO archive_fts(rowid, tags)
    VALUES (new.id, new.tags);
END;

CREATE TRIGGER archive_after_delete
AFTER DELETE ON archive
BEGIN
    INSERT INTO archive_fts(archive_fts, rowid, tags)
    VALUES('delete', old.id, old.tags);
END;

CREATE TRIGGER archive_after_update
AFTER UPDATE ON archive
BEGIN
    INSERT INTO archive_fts(archive_fts, rowid, tags)
    VALUES('delete', old.id, old.tags);

    INSERT INTO archive_fts(rowid, tags)
    VALUES (new.id, new.tags);
END;
