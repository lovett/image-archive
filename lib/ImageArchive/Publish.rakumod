unit module ImageAarchive::Publish;

use Template::Mustache;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Util;

# Write an HTML file containing thumbnails of search results.
sub publishHtml(@results) is export {
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

    my $out = getPath('html').add('gallery.html');
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
    my $outdir = getPath('html');
    mkdir($outdir) unless $outdir.IO ~~ :d;

    my @assets = <ia.css>;

    for @assets -> $asset {
        copy(%?RESOURCES{$asset}, $outdir.add($asset));
    }
}
