unit module ImageArchive::Command::Publish;

use Template::Mustache;

use ImageArchive::Database;
use ImageArchive::Activity;
use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

our sub run() {
    my @results = dumpStash('searchresult');
    my $path = publishHtml(@results);
    viewExternally($path);
}

# Write an HTML file containing thumbnails of search results.
sub publishHtml(@results) {
    my %templates = loadTemplates('layout', 'gallery');
    my @sizes = readConfig('alt_sizes').split(' ');

    my %vars;
    for @results -> $result {
        my $smallAlt = findAlternate($result<path>, @sizes[*-1]);
        my $largeAlt = findAlternate($result<path>, @sizes[0]);
        my $relpath = relativePath($result<path>);
        my %tags = getTags($result<path>, 'CreateDate');
        my $series = ($result<series> eq 'unknown') ?? '' !! $result<series>;
        if ($series and $result<seriesid>) {
            $series = formattedSeriesId($series, $result<seriesid>.Str);
        }

        %vars.push('image', %(
                       'path', $smallAlt,
                       'href', $largeAlt,
                       'filename', $result<path>.basename,
                       'date', %tags<CreateDate> || '',
                       'series', $series,
                   ));
    }

    my $stache = Template::Mustache.new(:from(%templates));

    my $out = appPath('html').add('gallery.html');
    mkdir($out.dirname) unless $out.dirname.IO ~~ :d;
    spurt $out, $stache.render('gallery', %vars);

    publishStaticAssets();
    return $out;
}

sub loadTemplates(*@basenames) {
    my %templates;
    for @basenames -> $basename {
        my $template = $basename ~ '.mustache';
        %templates{$basename} = %?RESOURCES{$template}.slurp;
    }
    return %templates;
}

sub publishStaticAssets() {
    my $outdir = appPath('html');
    mkdir($outdir) unless $outdir.IO ~~ :d;

    my @assets = <ia.css>;

    for @assets -> $asset {
        copy(%?RESOURCES{$asset}, $outdir.add($asset));
    }
}
