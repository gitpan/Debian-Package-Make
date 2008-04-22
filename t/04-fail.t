use Test::More tests => 4;
use File::Temp qw(tempdir);
use Debian::Package::Make::TemplateDir;

{
    ok my $pg = Debian::Package::Make::TemplateDir->new(
        me           => 'Anonymous <nobody@example.invalid>',
        source       => 'fail1',
        template_dir => 't/data/ok1.template' ), 'generate D:P:M object';
    ok $pg->copy_orig_tarball( file => 't/data/fail1-3.2.tar.gz' ),
      'copy tarball to base_dir';
    local $SIG{__WARN__} = sub{};
    is $pg->generate_build_dir, undef,
      'fail to generate build_dir from broken tarball';
}

{
    my $pg = Debian::Package::Make::TemplateDir->new(
        me           => 'Anonymous <nobody@example.invalid>',
        source       => 'fail2',
        template_dir => 't/data/fail2.template' );
    $pg->copy_orig_tarball( file => 't/data/ok1-3.2.tar.gz' );
    $pg->debian_revision(1);
    $pg->generate_build_dir;
    $pg->prepare_files;
    $pg->generate_files;
    local $SIG{__WARN__} = sub{};
    is $pg->build, undef,       'fail build with broken debian/rules';
}
