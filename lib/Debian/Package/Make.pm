package Debian::Package::Make;

use 5.008008;
use strict;
use warnings;

our $VERSION = '0.02';

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw(@ATTRIBUTES);

use Carp qw(carp cluck);
use File::Temp;
use File::Path;
use File::Copy qw(cp mv);
use File::Copy::Recursive qw(dircopy);
use Cwd;
use LWP::UserAgent;

# Workarounds for etch comparibility
BEGIN {
    eval 'use Dpkg::Arch qw(get_host_arch)';
    if ($@) {
        eval {
            *get_host_arch = sub {
                my %dpkg_arch = map { chomp; split /=/ } `dpkg-architecture`;
                return $dpkg_arch{DEB_HOST_ARCH};
            };
        };
    }
    eval 'use Dpkg::Cdata qw(parsecdata)';
    # parsecdata has been copied from the Dpkg::CData module (dpkg-dev
    # 1.14.16.6). On systems newer than etch, it is not used.
    if ($@) {
        *parsecdata = sub {
            my ( $input, $file, %options ) = @_;

            $options{allow_pgp} = 0 unless exists $options{allow_pgp};
            $options{allow_duplicate} = 0
              unless exists $options{allow_duplicate};

            my $paraborder     = 1;
            my $fields         = undef;
            my $cf             = '';      # Current field
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
                }
                elsif (m/^\s+\S/) {
                    length($cf)
                      || syntaxerr( $file,
                        "continued value line not in field" );
                    $fields->{$cf} .= "\n$_";
                }
                elsif (m/^-----BEGIN PGP SIGNED MESSAGE/) {
                    $expect_pgp_sig = 1;
                    if ( $options{allow_pgp} ) {

                        # Skip PGP headers
                        while (<$input>) {
                            last if m/^$/;
                        }
                    }
                    else {
                        syntaxerr( $file, "PGP signature not allowed here" );
                    }
                }
                elsif (m/^$/) {
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
                    last;    # Finished parsing one block
                }
                else {
                    syntaxerr( $file,
                        "line with unknown format (not field-colon-value)" );
                }
            }
            return $fields;
        };
    }
}

=pod

=head1 NAME

Debian::Package::Make - Perl extension for autobuilding Debian packages

=head1 SYNOPSIS

Debian::Package::Make and Debian::Package::Make::* is a set of modules
designed to make automatically building Debian packages easier. This
can be useful for contents that need to be updated very frequently
(i.e. antispam or antivirus patterns) or for software whose author
does not permit redistribution of his work in a way that would allow
the package to be included in Debian or derived distributions.

=head1 DESCRIPTION

(or: Creating your package in seven easy steps)

In a nutshell, Debian::Package::Make and its derived classes provide
code and sensible default values and behavior to perform the steps
necessary to build a Debian package from source.

=over

=item 1. Create build environment

When a Debian::Package::Make::* object is created through the C<new>
constructor, a temporary directory is created. This directory is
called the base directory and its path is stored in the object's
C<base_dir> attribute. All files that are needed in the package
creation process should be put underneath this directory. Since this
is a temporary directory, it should be safe to remove it afterwards.

=item 2. Obtain original material

The material from which package(s) will be built may either be
supplied as a tarball or provided from a directory.

If a tarball is available on a public Internet host or locally, the
C<download_orig_tarball> or C<copy_orig_tarball> method, respectively,
should be used for placing this tarball in the base directory. The
downloaded or copied file will be named in a scheme that
F<dpkg-buildpackage> will recognize. (i.e. F<foobar_0.3.orig.tar.gz>)

If the source material is not available as a tarball,
C<generate_orig_dir> can be overloaded. The base method's purpose is
to create a directory that can be filled, i.e. by downloading current
updates for an antivirus product. The directory for the original
material will be named in a scheme that F<dpkg-buildpackage> will
recognize. (i.e. F<foobar-0.3.orig/>)

The version number of the package(s) should be determined and set as
soon as possible, either from the URL or filename or from the contents
that have been downloaded, copied, or generated.

=item 3. Lay out foundation for build directory

The C<generate_build_dir> method creates the build directory (i.e.
F<foobar-0.3/>) and fills it with content. The C<build_dir> attribute
contains the path of the build directory.

For non-native packages (where Debian-specific changes are applied to
the source package), it unpacks the original tarball or copies the
content of F<orig_dir> to the build directory.

Support for native packages has not yet been implemented.

=item 4. Apply Debian-specific changes to build directory

The C<generate_files> method is used to write out the contents of the
C<files> attribute to the build directory.

The contents of C<files> should be set by a C<prepare_files> method.
which is not implemented in the Debian::Package::Make base class.

The Debian::Package::Make distribution provides a two classes that
offer different approaches for adding files to the build directory.
Since this is where most of the effort in generating Debian packages
goes, a design goal for Debian::Package::Make was to provide the
greatest possible flexibility at this stage.

=item 5. Finally build the package(s)

The C<build_source>, C<build_binary>, and C<build> method call
F<dpkg-buildpackage> with appropriate options for performing a
source-only, binary-only, or source+binary build, respectively.

=item 6. Copy the resulting files to a destination directory

The C<copy_files> method copies resulting files to the a destination
directory, defaulting to the current working directory.

=item 7. Clean up temporary files

The C<cleanup> method does no more than removing the contents of
C<build_dir>.

=back

=head1 ATTRIBUTES

The following attributes are defined in Debian::Package::Make::*
objects. If it is necessary to get or set attributes, object methods
should be used:

C<< $foobar_generator->version '0.3-2'; >>

Derived classes that need to define additional simple attributes may
do so by adding entries to the C<@ATTRIBUTES> array that they inherit
from Debian::Package::Make.

=over

=item Housekeeping for Debian::Package::Make

=over

=item C<base_dir>

=item C<orig_dir>

=item C<build_dir>

=item C<orig_tarball>

=item C<orig_tarball_extension>

=back

=item Variables for F<debian/control>

=over

=item C<source>

=item C<section>

=item C<priority>

=item C<maintainer>

=item C<uploaders>

=back

=item Variables for F<debian/changelog>

=over

=item C<version>, C<distribution>, C<urgency>

=item C<changes>

A list (ARRAY) of items that will be put into F<debian/changelog> as a
bulleted list.

=item C<me>

Uploader's name and e-mail address.

=item C<builddate>

=back

=back

=cut

our @ATTRIBUTES = (

    # Where the package is built
    qw( base_dir orig_dir build_dir
      orig_tarball orig_tarball_extension ),

    # .dsc, .tar.(gz|bz2), .diff.gz, .deb, .changes
    qw(output_files),

    # source section of debian/control
    qw( source
      section priority
      maintainer uploaders ),

    # topmost debian/changelog entry
    qw( version distribution urgency
      changes
      me builddate ),

    qw( sign_source sign_changes ),
);

=pod

=head1 PUBLIC INTERFACE

=over

=item C<new>

Creates an Debian::Package::Make object and sets up

=over

=item *

a base directory (C<base_dir> attribute) 

=item *

a build directory (C<build_dir> attribute) and

=item *

semi-sensible defaults for the C<priority>, C<distribution>,
C<urgency>, C<changes>, C<me>, C<builddate> attributes

=item *

defaults for the C<source>, C<section>, and C<version>
attributes that are not sensible at all and should be set by a
subclass.

=back

It is probably not a good idea to call this method directly in a
script; create a subclass instead.

=cut

sub new {
    my ( $class, %param ) = @_;
    my $self = bless {
        native   => 0,
        section  => 'unknown',
        priority => 'extra',
        source   => ( lc($class) =~ /.*::(.*?)$/ ),

        version      => '0.0-0unknown1',
        distribution => 'unstable',
        urgency      => 'low',
        changes      => ["Autobuilt using $class"],

        files        => {},
        output_files => [],
    }, $class;

    foreach my $key ( keys %param ) {
        $self->$key( $param{$key} );
    }

    $self->{me} ||= ( split( /,/, ( getpwuid($<) )[6] ) )[0]
      . (
        exists $ENV{DEBEMAIL}
        ? " <$ENV{DEBEMAIL}>"
        : ' <nobody@example.invalid>' );
    $self->{maintainer} ||= $self->{me};

    # Create directory in which everything gets built.
    if ( exists $self->{base_dir} ) {
        mkpath $self->{base_dir};
    } else {
        $self->{base_dir} =
          File::Temp::tempdir("/tmp/build-$self->{source}.XXXXXXXX");
    }

    $self->{build_dir} ||=
      ( $self->{base_dir} . '/' . $self->{source} . '-' . $self->{version} );
    mkpath( $self->{build_dir} );

    chomp( $self->{builddate} ||= `date -R` );

    return $self;
}

=item C<detect_version>

Use a regular expression to detect the verion number in common
filename patterns, e.g.:

=over

=item

F<COMset-2.6.28.tar.gz>

=item

F<BitDefender-scanner-7.5-4.linux-gcc3x.i586.tar.run>

=iten 

F</tmp/downloads/AdobeReader_enu-7.0.9-1.i386.tar.gz>

=item

F<http://dl.google.com/linux/standalone/picasa-2.2.2820-5.i386.bin>

=back

This method is called by the standard C<copy_orig_tarball> and
C<download_orig_tarball> methods after they have done their work.

FIXME

=cut

sub detect_version {
    my ( $self, %param ) = @_;

    my ( $pre, $name, $version, $post ) =
      $param{path} =~
      m(((?:.*/)?)([[:alnum:]][[:alnum:]_-]+[[:alnum:]])[-_](\d[\d\.-]+\d)(.*)$);

    if ( defined $version ) {
        $version =~ tr/-/./;
        $self->version("$version-1");
    } else {
        die("Could not guess version from path \"$param{path}\"");
    }
}

=pod

=item C<copy_orig_tarball>

=over

=item * C<file>

=item * C<extension>

If the extension can't be determined from the URL, it must be specified. gz or bz2.

=back

Put the original tarball into the base directory.

The subclasses' version of this method is probably a good place to
determine the version number for the package.

=cut

sub copy_orig_tarball {
    my ( $self, %param ) = @_;
    my ($version) = $self->{version} =~ /^(.*?)(?:-.*)?$/;
    if ( exists $param{extension} ) {
        $self->{orig_tarball_extension} = $param{extension};
    } elsif ( $param{file} =~ /\.(gz|bz2)$/ ) {
        $self->{orig_tarball_extension} = $1;
    } else {
        warn "Could not guess extension from filename. Assuming 'gz'\n";
        $self->{orig_tarball_extension} = 'gz';
    }
    my $extension = $self->{orig_tarball_extension};

    cp( $param{file},
        "$self->{base_dir}/$self->{source}_$version.orig.tar.$extension" );
    $self->{orig_tarball} =
      "$self->{base_dir}/$self->{source}_$version.orig.tar.$extension";
    $self->detect_version( path => $param{file} );
}

=pod

=item C<download_orig_tarball>

=over

=item * C<url>

=item * C<extension>

If the extension can't be determined from the URL, it must be
specified. C<Debian::Package::Make> can currently cope with C<gz> and
C<bz2>.

=back

Download C<url> to the base directory and set the C<orig_tarball>
attribute to the downloaded file..

=cut

sub download_orig_tarball {
    my ( $self, %param ) = @_;
    my ($version) = $self->{version} =~ /^(.*?)(?:-.*)?$/;
    if ( exists $param{extension} ) {
        $self->{orig_tarball_extension} = $param{extension};
    } elsif ( $param{url} =~ /\.(gz|bz2)$/ ) {
        $self->{orig_tarball_extension} = $1;
    } else {
        warn "Could not guess extension from filename. Assuming 'gz'\n";
        $self->{orig_tarball_extension} = 'gz';
    }
    my $extension = $self->{orig_tarball_extension};
    $self->{orig_tarball} =
      "$self->{base_dir}/$self->{source}_$version.orig.tar.$extension";

    my $ua       = LWP::UserAgent->new;
    my $response = $ua->get( $param{url} );
    if ( $response->is_success ) {
        open my $fh, ">$self->{orig_tarball}";
        print $fh $response->content;
        close $fh;
        $self->detect_version( path => $param{url} );
        return 1;
    } else {
        # FIXME: Output warnings here?
        delete $self->{orig_tarball};
        return;
    }
}

=pod

=item C<generate_orig_dir>

Create a directory F<source-version.orig/> beneath the base directory.
The name of this directory is stored in the C<orig_dir> attribute.

=cut

sub generate_orig_dir {
    my ( $self, %param ) = @_;
    unless ( exists $self->{orig_dir} ) {
        $self->{orig_dir} =
          File::Temp::tempdir("$self->{base_dir}/orig.XXXXXXXX");
        $self->rename_files();
    }
}

=pod

C<copy_orig_tarball> C<download_orig_tarball>, or C<generate_orig_dir>
methods in derived classes are probably good places to determine and
set the version number.

=item C<generate_build_dir>

Put source files into the build directory, by extracting them from
the C<orig_tarball> or by copying them from the C<orig_dir>

=cut

sub generate_build_dir {
    my ( $self, %param ) = @_;
    my $orig = getcwd;
    if ( exists $self->{orig_dir} ) {

        # copy orig_dir to build_dir
        dircopy( $self->{orig_dir}, $self->{build_dir} );
    } elsif ( exists $self->{orig_tarball} ) {
        my $extract;
        foreach ( $self->{orig_tarball_extension} ) {
            /^gz$/  && do { $extract = '-xzf'; next };
            /^bz2$/ && do { $extract = '-xjf'; next };
            die( "Unknown extension for original tarball: "
                  . $self->{orig_tarball_extension} );
        }

        my $tmpdir = File::Temp::tempdir("$self->{base_dir}/unpack.XXXXXXXX");
        my @cmdline = ( qw(tar -C), $tmpdir, $extract, $self->{orig_tarball} );
        _verbose_system(@cmdline) == 0 or return;

        # Mimic dpkg-source(1)'s behavior (sub extracttar):
        #
        # A tarball with a single directory (such as foo-0.1) at its
        # root is treated as a special case.
        my ( $dh, @entries );
        opendir( $dh, $tmpdir );
        @entries = grep( $_ ne "." && $_ ne "..", readdir($dh) );
        closedir($dh);
        if ( @entries == 1 && -d "$tmpdir/$entries[0]" ) {
            my $basedir = $entries[0];
            opendir( $dh, "$tmpdir/$basedir" );
            @entries =
              map { "$basedir/$_" }
              grep( $_ ne "." && $_ ne "..", readdir($dh) );
            closedir($dh);
        }

        foreach (@entries) {
            my ($dest) = m((?:.*/)?(.*));    # strip leading directory if any.
            rename( "$tmpdir/$_", "$self->{build_dir}/$dest" );
        }
        rmtree($tmpdir);
    }
}

=pod

=item C<test_build_setup>

Method that can be used to tet setup before calling dpkg-buildpackage

=cut

sub test_build_setup {
    my ( $self, %param ) = @_;

    if ( $self->{section} eq 'unknown' ||
	 $self->{version} eq '0.0-0unknown1' ||
	 $self->{me} =~ /unknown|example/ ||
	 $self->{maintainer} =~ /unknown|example/ ||
	 $self->{native} && $self->{orig_dir} ) {
	carp("Default values not changed.");
	return;
    }
}

=pod

=item C<prepare_files>

prepare_files() is not implemented in Debian::Package::Make. Derived
classes should populate %$self->{files} (see below) that is used by
generate_files() to generate BUILDDIR/debian.

=cut 

=pod

=item C<process_templates>

This function is used internally to replace macros within files ending
with F<.in>. the following macros are currently recognized.

=over

=item * #SOURCE#

=item * #VERSION#

=item * #UPSTREAMVERSION#

=item * #DEBIANVERSION#

=item * #DISTRIBUTION#

=item * #URGENCY#

=item * #CHANGES#

=item * #USERNAME#

=item * #EMAIL#

=item * #DATE#

=back

=cut

sub process_templates {
    my ($self) = @_;

    # FIXME Regex probably too simple -- epoch?
    my ( $upstreamversion, $debianversion ) = $self->{version} =~ /^(.+)-(.+)$/;
    my ( $username, $email ) = $self->{me} =~ /^(.+) <(.+)>$/;

    #                                    Tue, 05 Feb 2008 17:09:27 +0100
    my ($year) = $self->{builddate} =~ /^..., .. ... (....)/;
    foreach my $in ( grep /\.in$/, keys %{ $self->{files} } ) {
        next if ( $in =~ m(po/POTFILES\.in$) );    # Blacklist

        my ($out) = $in =~ /^(.*)\.in$/;
        $self->{files}{$out} = $self->{files}{$in};
        delete $self->{files}{$in};

        # debian/control
        $self->{files}{$out} =~ s/#SECTION#/$self->{section}/g;
        $self->{files}{$out} =~ s/#POLICY#/$self->{policy_version}/g;
        # FIXME Maintainer
        $self->{files}{$out} =~ s/#SOURCE#/$self->{source}/g;
        $self->{files}{$out} =~ s/#PACKAGE#/$self->{source}/g;

        # debian/changelog
        $self->{files}{$out} =~ s/#VERSION#/$self->{version}/g;
        $self->{files}{$out} =~ s/#UPSTREAMVERSION#/$upstreamversion/g;
        $self->{files}{$out} =~ s/#DEBIANVERSION#/$debianversion/g;
        $self->{files}{$out} =~ s/#DISTRIBUTION#/$self->{distribution}/g;
        $self->{files}{$out} =~ s/#URGENCY#/$self->{urgency}/g;
        local $" = "\n  * ";
        $self->{files}{$out} =~ s/#CHANGES#/@{$self->{changes}}/g;
        $self->{files}{$out} =~ s/#USERNAME#/$username/g;
        $self->{files}{$out} =~ s/#EMAIL#/$email/g;
        $self->{files}{$out} =~ s/#DATE#/$self->{builddate}/g;

        # README.Debian
        $self->{files}{$out} =~
          s/#DASHLINE#/'-'x(length("$self->{source} for Debian"))/ge;

        # msic
        $self->{files}{$out} =~ s/#YEAR#/$year/g;

        # $self->{files}{$out} =~ s/#SHORTDATE#/$shortdate/g;
        $self->{files}{$out} =~ s/#SCRIPTNAME#/$0/g;

        # Here (otther): AUTOGENWARNING
        # Here: SCRIPTNAME

        # Maybe sensible in D:P:M:Debhelper (dh_make):
        # DEBHELPERVERSION CHANGELOGS PRESERVE CONFIG_STATUS CONFIGURE
        # CONFIGURE_STAMP INSTALL PHONY_CONFIGURE CDBS_CLASS DPKG_ARCH
        # BUILD_DEPS
    }
}

=pod

=item C<generate_files>

generate_files() creates files in build_dir/debian (and possibly other
new files) from %$self->{files}.

=cut

sub generate_files {
    my ( $self, %param ) = @_;

    # filter out directory traversal attempts
    my %f = map { $_ => $self->{files}{$_} } grep !m(\.\./),
      keys %{ $self->{files} };

    foreach ( keys %f ) {

        # Create leading directories
        if (m(^(.*/))) {
            mkpath("$self->{build_dir}/$1");
        }
        open my $fh, ">$self->{build_dir}/$_"
          || cluck("couldn't open $self->{build_dir}/$_: $!");
        print $fh $f{$_};
        close $fh;
    }
    chmod 0755, "$self->{build_dir}/debian/rules";
}

=pod

=item C<output_add_changes_file>

Expects a F<.changes> file and adds that plus referenced files to
F<output_files>.

=cut

sub output_add_changes_file {
    my ( $self, $changes_file ) = @_;
    push @{ $self->{output_files} }, $changes_file;
    open my $fh, "$self->{base_dir}/$changes_file"
      || cluck("couldn't open $self->{base_dir}/$changes_file: $!");
    my $fields = parsecdata( $fh, $changes_file );
    foreach ( split /\n/, $fields->{Files} ) {
        push @{ $self->{output_files} }, ( split /\s+/, $_ )[-1];
    }
    close $fh;
}

=pod

=item C<build_source>

Builds a source-only package.

=cut

sub build_source {
    my ( $self, %param ) = @_;
    $self->call_buildpackage(argv => [qw(-S)]);
}

=pod

=item C<build_binary>

Builds one or more binary-only packages.

=cut

sub build_binary {
    my ( $self, %param ) = @_;
    $self->call_buildpackage(argv => [qw(-b)]);
}

=pod

=item C<build>

Builds source and binary packages.

=cut

sub build {
    my ( $self, %param ) = @_;
    $self->call_buildpackage();
}

=pod

=item C<call_buildpackage>

Calls F<dpkg-buildpackage> from within C<base_dir>.

=cut

sub call_buildpackage {
    my ( $self, %param ) = @_;
    $param{argv} ||= [];
    my @argv = qw(-rfakeroot);
    push @argv, @{ $param{argv} };
    if ( !$self->sign_changes ) {
        push @argv, '-uc';
    }
    if ( !$self->sign_source ) {
        push @argv, '-us';
    }
    my $orig = getcwd;
    my $arch = get_host_arch;
    chdir $self->{build_dir};
    my $rc = _verbose_system( 'dpkg-buildpackage', @argv );
    chdir $orig;
    if ( $rc == 0 ) {
        $self->output_add_changes_file(
            "$self->{source}_$self->{version}_$arch.changes");
        return 1;
    }
    else {
        return;
    }
}

=pod

=item C<copy_files>

Copies F<.changes> file and source and/or binary files that are
referenced in the F<.changes> file to F<dest_dir>.

=over

=item * C<dest_dir>

specifies the destination directory. Defaults to the current working
directory.

=item * C<overwrite>

Normally, C<copy_files> does not overwrite existing files in the
destination directory because that may. This switch overrides this.

=back

=cut

sub copy_files {
    my ( $self, %param ) = @_;
    my $d = $param{dest_dir} || getcwd();
    if ( !$param{overwrite} ) {
        foreach ( @{ $self->{output_files} } ) {
            if ( -e "$d/$_" ) {
                warn "Not copying any files: $d/$_ exists.\n";
                return;
            }
        }
    }
    foreach ( @{ $self->{output_files} } ) {
        unless (cp( "$self->{base_dir}/$_", "$d/$_" )) {
            warn "Could not copy $self->{base_dir}/$_ to $d/$_: $!\n";
            return;
        }
    }
    return 1;
}

=pod

=item C<cleanup>

Removes base_dir and all its subdirectories. All those valuable
auto-generate package files will be lost. Applications should
therefore copy what they need somewhere else before calling cleanup.

=cut

sub cleanup {
    my ( $self, %param ) = @_;
    rmtree( $self->{base_dir} );
}

=pod

=item C<rename_files>

If necessary, this function renames C<orig_tarball>, C<build_dir>,
C<orig_dir> so that they are in sync with the C<source>, C<version>,
and C<orig_tarball_extension> attributes.

=cut

sub rename_files {
    my ( $self, %param ) = @_;
    my ( $tempdir, $source, $ext ) =
      ( $self->{base_dir}, $self->{source}, $self->{orig_tarball_extension} );
    my ($version) = ( $self->{version} =~ /^(.+?)(?:-.+)?$/ );
    if ( exists $self->{build_dir} ) {
        mv( $self->{build_dir}, "$tempdir/$source-$version" ) || die "$!";
        $self->{build_dir} = "$tempdir/$source-$version";
    }
    if ( exists $self->{orig_dir} ) {
        mv( $self->{orig_dir}, "$tempdir/$source-$version.orig" ) || die "$!";
        $self->{orig_dir} = "$tempdir/$source-$version.orig";
    }
    if ( exists $self->{orig_tarball} ) {
        mv( $self->{orig_tarball}, "$tempdir/${source}_$version.orig.tar.$ext" )
          || die "$!";
        $self->{orig_tarball} = "$tempdir/${source}_$version.orig.tar.$ext";
    }
}

=head1 HELPER FUNCTIONS

These functions are documented here only for reference. They I<should>
not be called from within derived classes.

=item C<_getset>

Simple get/set function, used by C<AUTOLOAD>.

=cut

sub _getset {
    my ( $self, $param, $value ) = @_;
    if ( defined $value ) {
        $self->{$param} = $value;
    }
    $self->{$param};
}

=pod

=item C<_verbose_system>

Simple wrapper around C<system> that emits warnings if the called
program returns with an exit code != 0 or can't be executed.

=cut

sub _verbose_system {
    my $rc = system(@_);
    if ( $rc != 0 ) {
        if ( $? == -1 ) {
            warn "failed to execute @_: $!\n";
        } elsif ( $? & 127 ) {
            warn "child @_ died with signal " . ( $? & 127 ) . "\n";
        } else {
            warn "child @_ exited with value " . ( $? >> 8 ) . "\n";
        }
    }
    return $rc;
}

=pod

=item C<AUTOLOAD>

=cut

# Accessor/mutator function
our $AUTOLOAD;

sub AUTOLOAD {
    my ( $self, $v ) = @_;
    my ( $p, $a ) = ( $AUTOLOAD =~ /^(.+)::(.+)$/ );
    return if ( $a eq 'DESTROY' );

    # Avoid error
    #   Can't use string ("Debian::Package::Make::Avira::AT") as an
    #   ARRAY ref while "strict refs" in use
    no strict 'refs';
    unless ( grep /^$a$/, @{"${p}::ATTRIBUTES"} ) {
        carp("Undefined subroutine $AUTOLOAD called");
        return;
    }
    if ( defined $v ) {
        $self->{$a} = $v;
        if ( grep /^$a$/, qw(source version) ) {
            $self->rename_files();
        }
    }
    return $self->{$a};
}

1;

=pod

=head1 BUGS

Likely. Please report them, either through the Debian Bug Tracking
System or to the author.

=head1 KNOWN BUGS

=over

=item * Error checking needs work.

=item * Debian::Package::Make doesn't have support for native packages yet.

=item * The template mechanism is under-documented and needs work.

=back

=head1 SEE ALSO

Debian::Package::Make::Debhelper, Debian::Package::Make::TemplateDir,
debhelper(7), dpkg-source(1), dpkg-buildpackage(1)

The F<examples> directory in the Debian::Package::Make distribution.

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
