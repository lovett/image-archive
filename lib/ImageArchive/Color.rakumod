unit module ImageArchive::Color;

use ImageArchive::Exception;

#| Get the average color of a file as an sRGB triple.
sub getAverageColor(IO::Path $file) is export {
    my $proc = run <convert -scale 1!x1!>, "{$file.Str}[0]", 'txt:-', :out, :err;
    my $err = $proc.err.slurp(:close);
    my $out = $proc.out.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    return extractRgbTriple($out);
}

#| Isolate RGB integers from a larger string.
sub extractRgbTriple($string) is export {
    my regex separator { <[\s,]>+ }
    my regex float { <[\d.]>+ }
    $string ~~ / '(' \s* $<r> = (<float>) <separator>  $<g> = (<float>) <separator>  $<b> = (<float>)/;

    return (~$<r>, ~$<g>, ~$<b>).map({ .Int });
}
