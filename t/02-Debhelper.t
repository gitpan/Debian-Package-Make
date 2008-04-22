use Test::More tests => 10;
use File::Temp qw(tempdir);
use Debian::Package::Make::Debhelper;

{
    ok my $pg = Debian::Package::Make::Debhelper->new(
        me     => 'Anonymous <nobody@example.invalid>',
        source => 'ok1' ) , 'generate D:P:M object (TemplateDir)';;
    ok $pg->copy_orig_tarball( file => 't/data/ok1-3.2.tar.gz' ),
      'copy tarball to base_dir';
    ok $pg->generate_build_dir, 'generate build_dir';
    ok $pg->debian_revision(1);
    ok $pg->add_binary(
        ok1 => {
            architecture => 'all',
            description  => 'a short description',
            longdesc => "This should be a verbose description, but it isn't."
        } );
    ok $pg->prepare_files,  'read, process  templates_dir';
    ok $pg->generate_files, 'generate debian/ directory';
    ok $pg->build,          'run dpkg-buildpackage';
    my $d = tempdir( CLEANUP => 1 );
    ok $pg->copy_files( dest_dir => $d ), 'copy resulting files';
    my @missing =
      grep { $_ ne '' }
        map { -e "$d/$_" ? '' : $_ }
          qw( ok1_3.2-1.dsc
              ok1_3.2.orig.tar.gz
              ok1_3.2-1.diff.gz
              ok1_3.2-1_all.deb );
    is_deeply \@missing, [], 'check all expected files are there';
}
