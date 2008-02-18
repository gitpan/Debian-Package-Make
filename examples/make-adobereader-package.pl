#!/usr/bin/perl 

use strict;
use warnings;

use lib "../lib";

package Debian::Package::Make::AdobeReader;

use Debian::Package::Make::TemplateDir '0.02';
our @ISA = qw(Debian::Package::Make::TemplateDir);

sub new {
    my ( $class, %param ) = @_;
    $param{maintainer} ||= 'Hilko Bengen <bengen@debian.org>';
    $param{section}    ||= 'non-free/text';
    $class->SUPER::new(%param);
}

1;

package main;

use Cwd;
use Getopt::Long;

my ( $file, $url );

my $r = GetOptions(
    'file=s' => \$file,
    'url=s'  => \$url
);

my $pg = Debian::Package::Make::AdobeReader->new();

if ( defined $file ) {
    $pg->copy_orig_tarball( file => $file );
}
elsif ( defined $url ) {
    $pg->download_orig_tarball( url => $url );
}
else {
    $pg->cleanup;
    die "Usage:\n  $0 --file=...\n  $0 --urla=...\n";
}

print "Build directory: $pg->{base_dir}\n";
$pg->generate_build_dir;
$pg->prepare_files;
$pg->generate_files;
$pg->build_binary;
$pg->copy_files;
$pg->cleanup;

1;
