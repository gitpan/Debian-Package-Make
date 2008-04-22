
=head1 NAME

Debian::Package::Make::TemplateDir - Perl extension for autobuilding Debian packages

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

package Debian::Package::Make::TemplateDir;

use strict;
use warnings;

our $VERSION = 0.04;

use Debian::Package::Make 0.04;

our @ISA    = qw(Debian::Package::Make);
our @EXPORT = qw(@ATTRIBUTES);

=pod

=head1 ATTRIBUTES

=over

=item C<template_dir>

The directory from which C<prepare_files> will fetch the templates. If
C<template_dir> is not set explicitly, it is derived from the program
name and the name of the class.

=back

=cut

push @ATTRIBUTES, qw( template_dir );

=pod

=head1 PUBLIC INTERFACE

=over

=item C<new>

=over

=item C<template_dir>

=back

Calls C<Debian::Package::Make::new()> and sets the C<template_dir>
attribute.

=cut

use File::Find;
use Cwd;

sub new {
    my ( $class, %param ) = @_;
    my $self = $class->SUPER::new(%param);
    $self->{template_dir} ||= $param{template_dir};
    if ( !$self->{template_dir} ) {
        my ($source) = ( lc($class) =~ /^(?:debian::package::make::)?(.*)$/i );
        $source =~ s/::/-/g;
        my ($path) = $0 =~ m(^(.*)/.+$); $path ||= '.';
        $self->{template_dir} ||= "$path/$source.template";
    }
    bless $self, $class;
}

=pod

=item C<prepare_files>

C<prepare_files> populates C<$self->{files}> using files from a
template directory (C<template_dir> parameter).

Files within this directory that end with F<.in> are treated as
templates that are processed using F<process_template>.

Note: In order for C<dpkg-buildpackage> to function correctly,
F<debian/control>, F<debian/changelog>, F<debian/rules> must be
provided by the template dir.

=cut

sub prepare_files {
    my ( $self, %param ) = @_;
    my %f = %{ $self->{files} };
    my $td = $param{template_dir} || $self->template_dir;
    find(
        sub {
            if (   $File::Find::name !~ /(?:\.ex|~)$/i
                && $File::Find::name !~ /\/(?:\.svn|\.git|CVS)/
                && -f $_
                && !-f "$_.in" )
            {
                {
                    my ($fn) = $File::Find::name =~ m(^$td/*(.*)$);
                    my $fh;
                    open $fh, '<', $_ or warn "Can't read $fn.\n";
                    local $/;
                    $f{$fn} = <$fh>;
                    close $fh;
                }
            }
        },
        $td );
    $self->{files} = \%f;
    $self->process_templates;
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

Debian::Package::Make

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
