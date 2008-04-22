use Test::More tests => 9;
use File::Temp qw(tempdir);
use Debian::Package::Make::TemplateDir;

{
    ok my $pg = Debian::Package::Make::TemplateDir->new(
        me           => 'Anonymous <nobody@example.invalid>',
        source       => 'ok1',
        template_dir => 't/data/ok1.template' ), 'generate D:P:M object';
    ok $pg->copy_orig_tarball( file => 't/data/ok1-3.2.tar.gz' ),
      'copy tarball to base_dir';
    ok $pg->debian_revision(1);
    ok $pg->generate_build_dir, 'generate build_dir';
    ok $pg->prepare_files,      'read, process  templates_dir';
    ok $pg->generate_files,     'generate debian/ directory';
    ok $pg->build,              'run dpkg-buildpackage';
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
