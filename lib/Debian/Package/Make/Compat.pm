=pod

=head1 NAME

Debian::Package::Make::Compat -- make Debian::Package::Make work in,
ahem, "older" environments such as Debian etch.

=head1 SYNOPSIS

Debian::Package::Make (and thus its subclasses) use some functions
only found in the newer, modular, versions (>= 1.14.6) of the dpkg-dev
tools. This module provides substitutes for them. if they are not
available.

This code is subject to changes and should not be used directly.

=head1 AUTHOR

Hilko Bengen, E<lt>bengen@debian.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Hilko Bengen

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=cut

use strict;
use warnings;

package Dpkg::Arch;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(get_host_arch);

sub get_host_arch() {
    my %dpkg_arch = map { chomp; split /=/ } `dpkg-architecture`;
    return $dpkg_arch{DEB_HOST_ARCH};
}

package Dpkg::Cdata;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(parsecdata);

sub parsecdata {
    my ( $input, $file, %options ) = @_;

    $options{allow_pgp} = 0 unless exists $options{allow_pgp};
    $options{allow_duplicate} = 0
      unless exists $options{allow_duplicate};

    my $paraborder     = 1;
    my $fields         = undef;
    my $cf             = '';	# Current field
    my $expect_pgp_sig = 0;
    while (<$input>) {
	s/\s*\n$//;
	next if ( m/^$/ and $paraborder );
	next if (m/^#/);
	$paraborder = 0;
	if (m/^(\S+?)\s*:\s*(.*)$/) {
	    unless ( defined $fields ) {
		my %f;

		# tie %f, "Dpkg::Fields::Object";
		$fields = \%f;
	    }
	    if ( exists $fields->{$1} ) {
		unless ( $options{allow_duplicate} ) {
		    syntaxerr( $file,
			       sprintf("duplicate field %s found"),
			       capit($1) );
		}
	    }
	    $fields->{$1} = $2;
	    $cf = $1;
	} elsif (m/^\s+\S/) {
	    length($cf)
	      || syntaxerr( $file,
			    "continued value line not in field" );
	    $fields->{$cf} .= "\n$_";
	} elsif (m/^-----BEGIN PGP SIGNED MESSAGE/) {
	    $expect_pgp_sig = 1;
	    if ( $options{allow_pgp} ) {

		# Skip PGP headers
		while (<$input>) {
		    last if m/^$/;
		}
	    } else {
		syntaxerr( $file, "PGP signature not allowed here" );
	    }
	} elsif (m/^$/) {
	    if ($expect_pgp_sig) {


		# Skip empty lines
		$_ = <$input> while defined($_) && $_ =~ /^\s*$/;
		length($_)
		  || syntaxerr( $file,
				"expected PGP signature, found EOF after blank line"
			      );
		s/\n$//;
		m/^-----BEGIN PGP SIGNATURE/
		  || syntaxerr(
			       $file,
			       sprintf("expected PGP signature, found something else \`%s'"),
			       $_
			      );

		# Skip PGP signature
		while (<$input>) {
		    last if m/^-----END PGP SIGNATURE/;
		}
		length($_)
		  || syntaxerr( $file, "unfinished PGP signature" );
	    }
	    last;		# Finished parsing one block
	} else {
	    syntaxerr( $file,
		       "line with unknown format (not field-colon-value)" );
	}
    }
    return $fields;
}


package Dpkg::Version;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(parseversion);

sub parseversion($) {
    my $ver = shift;
    my %verhash;
    if ( $ver =~ /:/ ) {
	$ver =~ /^(\d+):(.+)/ or die "bad version number '$ver'";
	$verhash{epoch} = $1;
	$ver = $2;
    } else {
	$verhash{epoch} = 0;
    }
    if ( $ver =~ /(.+)-(.+)$/ ) {
	$verhash{version}  = $1;
	$verhash{revision} = $2;
    } else {
	$verhash{version}  = $ver;
	$verhash{revision} = 0;
    }
    return %verhash;
}

1;
