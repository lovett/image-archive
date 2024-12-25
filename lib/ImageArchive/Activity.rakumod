unit module ImageArchive::Activity;

use Terminal::ANSIColor;

use ImageArchive::Archive;
use ImageArchive::Color;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Tagging;
use ImageArchive::Util;
use ImageArchive::Workspace;

=begin pod
This module is for multi-step operations that involve multiple other modules or do things that don't
quite fit in another module. It helps keep the main script lean.
=end pod

sub replaceFile(IO::Path $original, IO::Path $replacement) is export {
    transferTags($original, $replacement);
    deleteAlts($original);
    deindexFile($original);
    unlink($original);
    importFile($replacement);
}

sub printSearchResults(@results) is export {
    my $counter = 0;

    my $pager = getPager();

    for @results -> $result {
        my @columns = colored(sprintf("%3d", ++$counter), 'white on_blue');

        given $result {
            when $result<series>:exists {
                @columns.push: sprintf("%15s", formattedSeriesId(
                    $result<series>,
                    $result<seriesid>.Str
                ));
            }

            when $result<score>:exists {
                @columns.push: sprintf("%2.2f", $result<score>);
            }

            when $result<modified>:exists {
                @columns.push: $result<modified>.yyyy-mm-dd;
            }
        }

        @columns.push: relativePath($result<path>);

        $pager.in.say: @columns.join(" | ");
    }

    unless ($counter) {
        note 'No matches.';
    }

    $pager.in.close;
}

# Display one or more files in an external application.
sub viewExternally(*@paths) is export {
    my $key = do given @paths[0].IO {
        when .extension eq 'html' { 'view_html' }
        when :d { 'view_directory' }
        default { 'view_file' }
    }

    my $command = readConfig($key);

    unless ($command) {
        die ImageArchive::Exception::MissingConfig.new(:key($key));
    }

    # Using shell rather than run for maximum compatibility.
    my $proc = shell "$command {@paths}", :err;
    my $err = $proc.err.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }
}

# Remove tags by keyword, alias, or alias-and-value.
multi sub untagTerm(@targets, Str $term, Str $value, Bool $dryrun = False) is export {
    my $termType = identifyTerm($term);

    given $termType {
        when 'alias' {
            for @targets -> $target {
                removeAlias($target, $term, $value, $dryrun);

                if (isArchiveFile($target)) {
                    indexFile($target);
                }
            }
        }

        when 'keyword' {
            for @targets -> $target {
                removeKeyword($target, $term, $dryrun);

                if (isArchiveFile($target)) {
                    indexFile($target);
                }
            }
        }
    }
}

multi sub untagTerm(Str $term, Str $value, Bool $dryrun = False) is export {
    my $termType = identifyTerm($term);

    given $termType {
        when 'alias' {
            removeAliasFromArchive($term, $value, $dryrun);
        }

        when 'keyword' {
            removeKeywordFromArchive($term, $dryrun);
        }
    }
}
