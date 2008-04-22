#!/usr/bin/perl

=pod

=encoding utf8

=head1 NAME

C<make-avira-package> -- generate Debian packages for Avira Antivir

=head1 SYNOPSIS

C<make-avira-package --dir=/path/to/antivir>

C<make-avira-package --file=antivir-workstation-pers.tar.gz>

=head1 DESCRIPTION

C<make-avira-package> copies F<antivir>, F<antivir[0-9].vdf>, and
F<hbedv.key>to a temporary directory and invokes C<antivir --update>.
After it has verified that the update works (by scanning an EICAR
testfile), the following packages are built:

=over 4

=item avira-engine

The scanning engine

=item avira-pattern-vdf[0-3]

Virus definition files that are updated independently.

=back

Individual version numbers are inferred from C<antivir>'s output. The
version numbers are prefixed with an epoch if one is specified via the
C<--epoch> command line switch.

Both engine and virus definition files are installed into
F</usr/lib/avira>.

The needed files can be extracted from an official tarball such as
F<antivir-workstation-pers.tar.gz> or copied from a directory. If
neither a archive nor a directory are specified, the F</usr/lib/avira>
is assumed.

=head1 FILES

C<make-avira-package> creates a temporary work directory
F<make-avira-package-XXXXXX> in the current working directory. This
directory is cleaned up after a successful run.

=head1 AUTHOR

Hilko Bengen E<lt>bengen@debian.orgE<gt>

=cut

use strict;
use warnings;

package Debian::Package::Make::Avira;

use Debian::Package::Make::Debhelper;
our @ISA = qw(Debian::Package::Make::Debhelper);

sub new {
    my ( $class, %param ) = @_;
    $param{maintainer} ||= 'Hilko Bengen <bengen@debian.org>';
    $param{section}    ||= 'non-free/utils';

    my $self = $class->SUPER::new(%param);
    $self->{files}{'debian/dirs'} .= "usr/lib/avira\n";
    # FIXME copyright?
    bless $self, $class;
}

1;

package main;

use File::Temp;
use Getopt::Long;

use Archive::Tar;
use IO::Zlib;

use File::Copy qw(cp);
use IPC::Run3;

my ( $file, $dir, $verbose, $epoch );
my $pg;

$epoch = 0; # Default value

sub print_verbose {
    $verbose && print @_;
}

# http://service.avira.com/freet/index.php?id=26&domain=free-av.com
# http://dl6.avgate.net/down/unix/packages/antivir-workstation-pers.tar.gz

my $rc = GetOptions(
    'file=s'    => \$file,
    'dir=s'     => \$dir,
    'epoch=i'   => \$epoch,
    'verbose'   => \$verbose );

my $tmpdir = File::Temp::tempdir( 'make-avira-package-XXXXXX', CLEANUP => 1 );
print_verbose "Build directory: $tmpdir\n";
if ( defined $file ) {
    my $tar = Archive::Tar->new;
    {
	local $SIG{__WARN__} = sub { };
        $tar->read( $file, 1 ) or die "Could not open $file: $!\n";
    }
    foreach ( $tar->list_files ) {
        m((?:/hbedv\.key
            |/bin/linux_glibc22/antivir
            |/vdf/antivir\d\.vdf
            |/LICENSE(?:\.DE)?
            )$)x
          && do {
            my ($dfile) = m(.*/(.+?)$);
            $tar->extract_file( $_, "$tmpdir/$dfile" )
              or die( "Could not extract $_: " . $tar->error . "\n" );
          };
    }
} else {
    $dir ||= '/usr/lib/avira';
    foreach ( qw(antivir
                 antivir0.vdf antivir1.vdf  antivir2.vdf antivir3.vdf
                 hbedv.key) ) {

        cp("$dir/$_", "$tmpdir/$_") || die "Could not copy $dir/$_: $!\n";
        chmod oct 755, "$tmpdir/antivir";
    }
}

my $out;
my %version;

run3( [ "$tmpdir/antivir", '--update' ], \undef, \$out, \$out );
print_verbose $out;
if ( $? >> 8 > 1 ) {
    die "antivir --update exited with error code" . ( $? >> 8 ) . "\n";
    exit 1;
}

run3( [ "$tmpdir/antivir", '--check', '--update' ], \undef, \$out, \$out );
print_verbose $out;
if ( $? >> 8 > 1 ) {
    die "antivir --check --update exited with error code" . ( $? >> 8 ) . "\n";
    exit 1;
}

foreach  (split /\n\r?/,$out) {
    # 02.01.11.65   =  02.01.11.65  [antivir]
    # 00.00.00.00   <  06.40.00.00  [antivir0.vdf]
    m(^([\d\.]+)\s+([<=])\s+([\d\.]+)\s+\[(antivir(?:\d\.vdf)?)\]$) && do {
        $version{$4} = $3;
    }
}

if ( keys %version == 0 ) {
    die "Could not parse output of antivir --check --update\n";
}

open my $fh, '>', "$tmpdir/eicar.com";
$fh->print(
    'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*');
close $fh;

run3( [ "$tmpdir/antivir", "$tmpdir/eicar.com" ], \undef, \$out, \$out );
print_verbose $out;
if ( ( $? >> 8 != 1 ) || ( $out !~ /Eicar-Test-Signature/ ) ) {
    die "antivir failed to recognize the EICAR test signature.\n";
}

foreach ( keys %version ) {
    my ( $pkgname, $num );
    if (m(^antivir$)) {
        $pkgname = 'avira-engine';
    } elsif (m(^antivir(\d)\.vdf$)) {
        $num     = $1;
        $pkgname = "avira-pattern-vdf$1";
    } else {
        warn "unknown package type: $_\n";
        next;
    }

    $pg = Debian::Package::Make::Avira->new(
        source  => $pkgname,
        version => "$epoch:$version{$_}",
        verbose => $verbose );

    if ( $pkgname eq 'avira-engine' ) {
        $pg->add_binary(
            $pkgname => {
                architecture => 'i386 amd64',
                depends      => ['${shlibs:Depends}'],
                description  => "Avira Antivir AV engine",
                longdesc     => "Avira Antivir executable"
            } );
        $pg->{files}{'debian/links'} .=
          "/usr/lib/avira/antivir /usr/bin/antivir\n";
    } else {
        $pg->add_binary(
            $pkgname => {
                architecture => "all",
                description  => "virus definition file (VDF$num)",
                longdesc     => "Virus definition file for Avira Antivir"
            } );
    }
    open $fh, '<', "$tmpdir/$_" or die "$!\n";
    { local $/; $pg->{files}{$_} = <$fh>; }
    close $fh;
    $pg->prepare_files;
    $pg->{files}{'debian/install'} .= "$_ /usr/lib/avira\n";

    $pg->generate_files;
    if ( $pkgname eq 'avira-engine' ) {
        chmod oct 755, "$pg->{build_dir}/antivir";
    }

    $pg->build_binary;
    $pg->copy_files;

    $pg->cleanup;
}
