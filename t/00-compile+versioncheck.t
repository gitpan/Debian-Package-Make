use Test::More tests => 3;

BEGIN {
    use_ok('Debian::Package::Make');
    # Make sure all derived modules have at least the same version number.
    use_ok("Debian::Package::Make::Debhelper $Debian::Package::Make::VERSION" );
    use_ok("Debian::Package::Make::TemplateDir $Debian::Package::Make::VERSION" );
}
