use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Debian::Package::Make',
    VERSION_FROM      => 'lib/Debian/Package/Make.pm', # finds $VERSION
    PREREQ_PM         => { 'File::Temp'  => 0,
                           'File::Path'  => 0,
                           'File::Copy'  => 0,
                           'Cwd'         => 0,
                           'LWP::Simple' => 0,
                           'Dpkg::Arch'  => 0,
                           'Dpkg::Cdata' => 0,
                           'Text::Wrap'  => 0,
                           'File::Find'  => 0 },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Debian/Package/Make.pm', # retrieve abstract from module
       AUTHOR         => 'Hilko Bengen <bengen@debian.org>') : ()),
);
