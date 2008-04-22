use Test::More tests => 9;
use File::Temp qw(tempdir);
use Debian::Package::Make::Debhelper;

{
    ok my $pg = Debian::Package::Make::Debhelper->new(
        me     => 'Anonymous <nobody@example.invalid>',
        source => 'ok1',
        binaries => {ok1 => {
            architecture => 'all',
            description  => 'a short description',
            longdesc => "This should be a verbose description, but it isn't."
        }} ), 'generate D:P:M object';

    $pg->copy_orig_tarball( file => 't/data/ok1-3.2.tar.gz' );
    $pg->generate_build_dir;
    ok $pg->upstream_version('4.0');
    ok $pg->debian_revision(3);
    ok $pg->epoch(1);

    ok $pg->prepare_files,  'read, process  templates_dir';
    ok $pg->generate_files, 'generate debian/ directory';
    ok $pg->build,          'run dpkg-buildpackage';
    my $d = tempdir( CLEANUP => 1 );
    ok $pg->copy_files( dest_dir => $d ), 'copy resulting files';
    my @missing =
      grep { $_ ne '' }
        map { -e "$d/$_" ? '' : $_ }
          qw( ok1_4.0-3.dsc
              ok1_4.0-3.diff.gz
              ok1_4.0-3_all.deb );
    is_deeply \@missing, [], 'check all expected files are there';
}
