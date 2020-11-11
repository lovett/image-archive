class Build {
    method build($dist-path) {
        my $colordeltaIn = $dist-path.IO.add('resources/colordelta.c');
        my $colordeltaOut = $colordeltaIn.parent.add("colordelta.so");

        run qqw{gcc -g -fPIC -shared  $colordeltaIn -o $colordeltaOut }
    }
}
