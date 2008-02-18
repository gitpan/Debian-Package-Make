#!/usr/bin/perl

use strict;
use warnings;

use lib '../lib';

# TODO
package Debian::Package::Make::BitDefender::Scanner;

use Debian::Package::Make::TemplateDir '0.02';
our @ISA = qw(Debian::Package::Make::TemplateDir);
# use Cwd;
# use File::Path;
# use File::Copy;

sub new {
    my ( $class, %param ) = @_;
    $param{maintainer} ||= 'Hilko Bengen <bengen@debian.org>';
    $param{source}     ||= 'bitdefender-scanner';
    $param{section}    ||= 'non-free/utils';
    my $self = $class->SUPER::new(%param);
    bless $self, $class;
}

sub _mangle_tarball {
    my ($self) = @_;
    my ($version, $compression);
    rename $self->{orig_tarball}, "$self->{orig_tarball}run";
    open (my $fh,"sh $self->{orig_tarball}run --dumpconf|")
      || cluck ("Could run downloaded tarball.");
    while (<$fh>) {
	/^LABEL="BitDefender Scanner v(.*)"$/ && do {
	    $version=$1; $version =~ tr/-/./;
	};
	/^COMPRESS=(.*)$/ && ($compression = $1);
    }
    close $fh;
    my ($in, $out, $buf);
    open $in, "$self->{orig_tarball}run";
    open $out, ">$self->{orig_tarball}";
    while (<$in>) {
	chomp;
	last if ($_ eq 'eval $finish; exit $res');
    }
    while (read $in, $buf, 4096) {
	print $out $buf;
    }
    close $in;
    close $out;

    unlink "$self->{orig_tarball}run";
    	    
    if ($compression eq 'bzip2') {
	$self->orig_tarball_extension('bz2');
    } elsif ($compression eq 'gzip') {
	$self->orig_tarball_extension('gz');
    } else {
	warn "Unknoen compression scheme $1";
    }
}

sub copy_orig_tarball {
    my ($self, %param ) =@_;
    $self->SUPER::copy_orig_tarball(%param);
    $self->_mangle_tarball;
}

sub download_orig_tarball {
    my ($self, %param ) =@_;
    $self->SUPER::download_orig_tarball(%param);
    $self->_mangle_tarball;
}

1;

package Debian::Package::Make::BitDefender::Data;

use Debian::Package::Make::Debhelper '0.02';
use Cwd;
use File::Path;
use File::Copy;

our @ISA = qw(Debian::Package::Make::Debhelper);

sub new {
    my ( $class, %param ) = @_;
    $param{maintainer} ||= 'Hilko Bengen <bengen@debian.org>';
    $param{source}     ||= 'bitdefender-data';
    $param{section}    ||= 'non-free/utils';
    my $self = $class->SUPER::new(%param);
    bless $self, $class;
}

sub generate_orig_dir {
    my ( $self, %param ) = @_;
    $self->SUPER::generate_orig_dir(%param);
    my ( $pwd, $conffile, $update, $version );

    mkpath("$self->{orig_dir}/var/lib/scan/Plugins/");
    copy( "/usr/lib/BitDefender-scanner/var/lib/scan/bdupd.so",
        "$self->{orig_dir}/var/lib/scan" )
      or die "$!";

    # FIXME: Should we generate var/bddt.dat form installed keyfile?

    # Generate temporary configuration file for running the update routine
    open $conffile, ">$self->{orig_dir}/bdscan.conf";
    print $conffile <<'EOF';
InstallPath = .
UpdateHttpLocation = http://upgrade.bitdefender.com/update_is_90
Key = 3A40EEB213FF728D8A3D
EOF
    close $conffile;
    $pwd = getcwd();
    chdir( $self->{orig_dir} );
    system(
        "/usr/bin/bdscan --update --conf-file=$self->{orig_dir}/bdscan.conf");
    open $update, "$self->{orig_dir}/var/lib/scan/Plugins/update.txt"
      or die "$!";

    while (<$update>) {
        ( ($version) = /^Version: ([\d\.]+)/ ) && last;
    }
    close $update;
    chdir($pwd);
    if ( !defined $version ) {
        warn "Could not determine version\n";
    }
    else {
        $self->version("$version-1");
    }
}

sub prepare_files {
    my ( $self, %param ) = @_;
    $self->SUPER::prepare_files(%param);
    $self->{files}{'debian/rules'} =~
      s(#CLEAN#)(rm -f bdscan.conf var/bddt.dat var/lib/scan/bdupd.so);
    $self->{files}{'debian/dirs'} .=
      "usr/lib/BitDefender-scanner/var/lib/scan/Plugins\n";
    $self->{files}{'debian/install'} .=
      "var/lib/scan/Plugins usr/lib/BitDefender-scanner/var/lib/scan\n";
}

1;

package main;

use Getopt::Long;
use Cwd;

our ( $type, $file, $url, $pg );
$type='';

sub usage {
    die "Usage\n  $0 --type=scanner --file=FEIL\n  $0 --type=scanner --url=URL\n  $0 --type=data\n";
}

my $r = GetOptions(
    'type=s' => \$type,
    'file=s' => \$file,
    'url=s'  => \$url
);

if ( $type eq 'scanner' ) {
    usage if ( !defined $file && !defined $url );
    $pg = Debian::Package::Make::BitDefender::Scanner->new;
    print "Build directory: $pg->{base_dir}\n";
    if ( defined $file ) {
        $pg->copy_orig_tarball( file => $file, extension => '' );
    } else {
        $pg->download_orig_tarball( url => $url, extension => '' );
    }
    $pg->generate_build_dir;
    $pg->prepare_files;
} elsif ( $type eq 'data' ) {
    $pg = Debian::Package::Make::BitDefender::Data->new;
    print "Build directory: $pg->{base_dir}\n";
    $pg->generate_orig_dir;
    $pg->generate_build_dir;
    $pg->add_binary(
        'bitdefender-data' => {
            architecture => 'any',
            description  => 'BitDefender Antivirus definition files',
            longdesc =>
'This package contains virus definition rulesets for the BitDefender Antivirus scanner. It was built using make-bitdefender-package.pl.',
            depends => ['bitdefender-scanner'],
        } );
    $pg->prepare_files;
} else {
    usage;
}

$pg->generate_files;
if    ( $type eq 'data' )    { $pg->build_binary; }
elsif ( $type eq 'scanner' ) { $pg->build; }
$pg->copy_files;
$pg->cleanup;

1;
