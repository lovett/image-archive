class Build {
    method build($dist-path) {
        my $in = $dist-path.IO.add('resources/colordelta.c');
        my $out = $in.parent.add('colordelta.sqlite3extension');
        my $gccFlags = '-shared';

        given $*KERNEL {
            when 'darwin' {
                $gccFlags = '-dynamiclib';
            }
        }

        run qqw{gcc -g -fPIC $gccFlags $in -o $out}
    }
}
