=head1 NAME

Debian::Package::Make::Debhelper - Perl extension for autobuilding Debian packages

=head1 SYNOPSIS

Debian::Package::Make::Debhelper is an implementation of the
Debian::Package::Make interface that creates default files for
debhelper(7).

=cut

package Debian::Package::Make::Debhelper;

our $VERSION = '0.02'; 

use Debian::Package::Make '0.02';
use Text::Wrap;

our @ISA    = qw(Debian::Package::Make);
our @EXPORT = qw(@ATTRIBUTES);

=pod

=head1 ATTRIBUTES

=over

=item * C<standards_version>

=item * C<build_depends> C<build_depends_indep>

=item * C<binaries>

=back

=cut

push @ATTRIBUTES, (
    qw( standards_version
      binaries
      build_depends
      build_depends_indep)
);

sub new {
    my ( $class, %param ) = @_;
    my $self = $class->SUPER::new(%param);
    push( @{ $self->{build_depends} }, 'debhelper (>> 5)' )
      unless grep /debhelper/, @{ $self->{build_depends} };
    bless $self, $class;
}

=pod

=head1 PUBLIC INTERFACE

=over

=item C<add_binary>

Causes a binary package $binname with $attributes to be added.

Valid attributes include:

=over

=item * C<depends> C<suggests> C<recommends> C<conflicts>

ARRAYs containing the dependencies. This may include terms that are
interpreted by Debhelper scripts, i.e. C<${shlib:Depends}>.

=item * C<description>, C<longdesc>

The short and long description for the binary package.

=back

=cut

sub add_binary {
    my ( $self, $binname, $attributes ) = @_;
    carp("Binary $binname already defined")
      if ( exists $self->{binaries}{$binname} );
    $self->{binaries}{$binname} = $attributes;
}

=item C<prepare_files>

C<prepare_files> populates C<$self->{files}> with sensible defaults
for a debhelper(7)-based setup. At the moment, this includes the
following files, but other files may be added in later versions of
Debian::Package::Make.

=over

=item * F<debian/control>

=item * F<debian/changelog>

=item * F<debian/compat>

=item * F<debian/rules>

=back 

A subclass that uses C<prepare_files> should add a proper
F<debian/copyright> file and populate F<debian/install>,
F<debian/docs>, F<debian/links> and/or patch the entry for
F<debian/rules>. See debhelper(7) for details.

=cut

sub prepare_files {
    my ( $self, %param ) = @_;
    my %f = %{ $self->{files} };
    local $" = ", ";

    $f{'debian/control'} = <<EOF;
Source: $self->{source}
Section: $self->{section}
Priority: $self->{priority}
Maintainer: $self->{maintainer}
EOF
    if ( exists $self->{uploaders} ) {
        $f{'debian/control'} .= "Uploaders: @{$self->{uploaders}}\n";
    }
    if ( exists $self->{build_depends} ) {
        $f{'debian/control'} .= "Build-Depends: @{$self->{build_depends}}\n";
    }
    if ( exists $self->{build_depends_indep} ) {
        $f{'debian/control'} .=
          "Build-Depends-Indep: @{$self->{build_depends_indep}}\n";
    }
    $f{'debian/control'} .= "Standards-Version: 3.7.2\n";
    foreach my $name ( keys %{ $self->{binaries} } ) {
        my %binary = %{ $self->{binaries}{$name} };
        $f{'debian/control'} .= <<EOF;

Package: $name
Architecture: $binary{architecture}
EOF
        foreach my $attr (qw(depends suggests recommends conflicts)) {
            next unless exists $binary{$attr};
            $f{'debian/control'} .= ucfirst($attr) . ": @{$binary{$attr}}\n";
        }
        $f{'debian/control'} .= "Description: $binary{description}\n";
        if ( exists $binary{longdesc} ) {
            local $Text::Wrap::columns = 72;
            local $Text::Wrap::huge    = 'overflow';
            my $longdesc = Text::Wrap::fill( " .\n ", ' ', $binary{longdesc} );
            $longdesc =~ s/^ \.\n//g;
            $f{'debian/control'} .= "$longdesc\n";
        }
    }

    $f{'debian/changelog.in'} = <<EOF;
#SOURCE# (#UPSTREAMVERSION#-#DEBIANVERSION#) #DISTRIBUTION#; urgency=#URGENCY#

  * #CHANGES#

 -- #USERNAME# <#EMAIL#>  #DATE#

EOF

    # FIXME append old changelog if present
    $f{'debian/compat'} = "5\n";
    $f{'debian/rules'}  = <<EOF;
#!/usr/bin/make -f
configure:
	#CONFIGURE#
build: build-indep build-arch
build-indep:
	#BUILDINDEP#
build-arch:
	#BUILDARCH#
clean:
	dh_testdir
	dh_testroot
	#CLEAN#
	dh_clean
install: install-indep install-arch
install-indep: build-indep
	dh_testdir
	dh_testroot
	dh_clean -k -i
	dh_installdirs -i
	#INSTALLINDEP#
	dh_install -i
install-arch: build-arch
	dh_testdir
	dh_testroot
	dh_clean -k -s
	dh_installdirs -s
	#INSTALLARCH#
	dh_install -s
binary-indep: build-indep install-indep
binary-arch: build-arch install-arch
binary: binary-arch binary-indep
	dh_testdir
	dh_testroot
	dh_installchangelogs
	dh_installdocs
#	dh_installexamples
#	dh_installmenu
#	dh_installdebconf	
#	dh_installlogrotate	
#	dh_installemacsen
#	dh_installpam
#	dh_installmime
#	dh_python
#	dh_installinit
#	dh_installcron
#	dh_installinfo
#	dh_installman
	dh_link
#	dh_strip
	dh_compress
	dh_fixperms
#	dh_perl
#	dh_makeshlibs
	dh_installdeb
	dh_shlibdeps
	dh_gencontrol
	dh_md5sums
	dh_builddeb
.PHONY: build clean binary-indep binary-arch binary install install-indep install-arch
EOF
    $self->{files} = \%f;
    $self->process_templates;
    1;
}

1;

=pod

=back

=head1 BUGS

=over

=item * This module lacks documentation. For the time being,
please refer to the scripts in the F<examples> directory.

=back

=head1 SEE ALSO

Debian::Package::Make, debhelper(7)

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
