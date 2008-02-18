# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Debian-Package-Make.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;

BEGIN {
    use_ok('Debian::Package::Make');
    # Make sure all derived modules have at least the same version number.
    use_ok("Debian::Package::Make::Debhelper $Debian::Package::Make::VERSION" );
    use_ok("Debian::Package::Make::TemplateDir $Debian::Package::Make::VERSION" );
}

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

