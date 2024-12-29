unit module ImageArchive::Command::Setup;

use ImageArchive::Config;
use ImageArchive::Util;

our sub make-it-so() {
    my IO::Path $root = appPath("root");

    unless ($root.d) {
        confirm("Create {$root.absolute}?");
        mkdir($root);
    }

    createDatabase();
    writeConfig();
}

sub createDatabase() {
    my IO::Path $dbPath = appPath("database");

    return if $dbPath.f;

    my $schema = %?RESOURCES<schema-sqlite.sql>.IO.absolute;

    my $proc = run "sqlite3", $dbPath, :in;
    $proc.in.say(".read $schema");
    $proc.in.close;

    CATCH {
        when X::Proc::Unsuccessful {
            my $err = "Failed to apply database schema.";
            ImageArchive::Exception::BadExit.new(:err($err)).throw;
        }
    }
}

sub writeConfig() {
    my IO::Path $target = appPath("config");

    if ($target.f) {
        note "Skipping $target because it already exists.";
        return;
    }

    my $template = %?RESOURCES<config.ini>.IO.absolute;

    copy($template, $target);

    say "Wrote $target";
}
