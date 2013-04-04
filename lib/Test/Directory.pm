package Test::Directory;

use strict;
use warnings;

use Carp;
use File::Spec;
use Test::Builder::Module;

our $VERSION = '0.01';
our @ISA = 'Test::Builder::Module';

##############################
# Constructor / Destructor
##############################

sub new {
    my $class = shift;
    my $dir = shift;
    my %opts = @_;

    $opts{unique} = 1 unless defined $opts{unique};

    if ($opts{unique}) {
	mkdir $dir or croak "Failed to create '$dir': $!";
    } else {
	mkdir $dir;
	croak "$dir: $!" unless -d $dir;
    };
    my %self = (dir => $dir);
    $self{template} = $opts{template} if defined $opts{template};
    bless \%self, $class;
}

sub DESTROY {
    $_[0]->clean;
}

##############################
# Utility Functions
##############################

sub name {
    my ($self,$path) = @_;
    my @path = split /\//, $path;
    my $file = pop @path;
    if (defined($self->{template})) {
      $file = sprintf($self->{template}, $file);
    };
    File::Spec->catfile(@path,$file);
};

sub path {
    my ($self,$file) = @_;
    File::Spec->catfile($self->{dir}, $self->name($file));
};


sub touch {
    my $self = shift;
    foreach my $file (@_) {
	open my($fh), '>', $self->path($file);
	$self->{files}{$file} = 1;
    };
};

sub create {
  my ($self, $file, %opt) = @_;
  my $path = $self->path($file);

  open my($fh), '>', $path or croak "$path: $!";
  $self->{files}{$file} = 1;

  if (defined $opt{content}) {
    print $fh $opt{content};
  };
  if (defined $opt{time}) {
    utime $opt{time}, $opt{time}, $path;
  };
  return $path;
}

sub mkdir {
  my ($self, $dir) = @_;
  my $path = $self->path($dir);
  mkdir($path) or croak "$path: $!";
  $self->{directories}{$dir} = 1;
}

sub rm_dir {
  my ($self, $dir) = @_;
  my $path = $self->path($dir);
  rmdir($path) or croak "$path: $!";
  $self->{directories}{$dir} = 0;
}

sub check_file {
    my ($self,$file) = @_;
    my $rv;
    if (-f $self->path($file)) {
      $rv = $self->{files}{$file} = 1;
    } else {
      $rv = $self->{files}{$file} = 0;
    }
    return $rv;
}

sub check_directory {
    my ($self,$dir) = @_;
    my $rv;
    if (-d $self->path($dir)) {
      $rv = $self->{directories}{$dir} = 1;
    } else {
      $rv = $self->{directories}{$dir} = 0;
    }
    return $rv;
}

sub clean {
    my $self = shift;
    foreach my $file ( keys %{$self->{files}} ) {
    	unlink $self->path($file);
    };
    foreach my $dir ( keys %{$self->{directories}} ) {
    	rmdir $self->path($dir);
    };
    rmdir $self->{dir};
}
    
sub _path_map {
    my $self = shift;
    my %path;
    while (my ($k,$v) = each %{$self->{files}}) {
	$path{ $self->name($k) } = $v;
    };
    while (my ($k,$v) = each %{$self->{directories}}) {
	$path{ $self->name($k) } = $v;
    };
    return \%path;
}

sub count_unknown {
    my $self = shift;
    my $path = $self->_path_map;
    opendir my($dh), $self->{dir} or croak "$self->{dir}: $!";

    my $count = 0;
    while (my $file = readdir($dh)) {
	next if $file eq '.';
	next if $file eq '..';
	next if $path->{$file};
	++ $count;
    }
    return $count;
};

sub count_missing {
    my $self = shift;

    my $count = 0;
    while (my($file,$has) = each %{$self->{files}}) {
	++ $count if ($has and not(-f $self->path($file)));
    }
    while (my($file,$has) = each %{$self->{directories}}) {
	++ $count if ($has and not(-d $self->path($file)));
    }
    return $count;
}


sub remove_files {
  my $self = shift;
  my $count = 0;
  foreach my $file (@_) {
    my $path = $self->path($file);
    $self->{files}{$file} = 0;
    $count += unlink($path);
  }
  return $count;
}

##############################
# Test Functions
##############################

sub has {
    my ($self,$file,$text) = @_;
    $text = "File $file is found." unless defined $text;
    $self->builder->ok( $self->check_file($file), $text );
}

sub hasnt {
    my ($self,$file,$text) = @_;
    $text = "File $file is not found." unless defined $text;
    $self->builder->ok( not($self->check_file($file)), $text );
}

sub has_directory {
    my ($self,$file,$text) = @_;
    $text = "Directory $file is found." unless defined $text;
    $self->builder->ok( $self->check_directory($file), $text );
}

sub hasnt_directory {
    my ($self,$file,$text) = @_;
    $text = "Directory $file is not found." unless defined $text;
    $self->builder->ok( not($self->check_directory($file)), $text );
}

sub clean_ok {
    my ($self,$text) = @_;
    $self->builder->ok($self->clean, $text);
}

sub is_ok {
    my $self = shift;
    my $name = shift;
    my $test = $self->builder;

    my @miss;
    while (my($file,$has) = each %{$self->{files}}) {
	if ($has and not(-f $self->path($file))) {
	    push @miss, $file;
	}
    }
    my @miss_d;
    while (my($file,$has) = each %{$self->{directories}}) {
	if ($has and not(-d $self->path($file))) {
	    push @miss_d, $file;
	}
    }

    opendir my($dh), $self->{dir} or croak "$self->{dir}: $!";

    my $path = $self->_path_map;
    my @unknown;
    while (my $file = readdir($dh)) {
	next if $file eq '.';
	next if $file eq '..';
	next if $path->{$file};
	push @unknown, $file;
    }

    my $rv = $test->is_num(@miss+@unknown, 0, $name);
    unless ($rv) {
	$test->diag("Missing file: $_") foreach @miss;
	$test->diag("Missing directory: $_") foreach @miss_d;
	$test->diag("Unknown file: $_") foreach @unknown;
    }
    return $rv;
}



1;
__END__

=head1 NAME

Test::Directory - Perl extension for maintaining test directories.

=head1 SYNOPSIS

 use Test::Directory
 use My::Module

 my $dir = Test::Directory->new($path);
 $dir->touch($src_file);
 My::Module::something( $dir->path($src_file), $dir->path($dst_file) );
 $dir->has_ok($dst_file);   #did my module create dst?
 $dir->hasnt_ok($src_file); #is source still there?

=head1 DESCRIPTION

Sometimes, testing code involves making sure that files are created and
deleted as expected.  This module simplifies maintaining test directories by
tracking their status as they are modified or tested with this API, making
it simple to test both individual files, as well as to verify that there are
no missing or unknown files.

Test::Directory implements an object-oriented interface for managing test
directories.  It tracks which files it knows about (by creating or testing
them via its API), and can report if any files were missing or unexpectedly
added.

There are two flavors of methods for interacting with the directory.  I<Utility>
methods simply return a value (i.e. the number of files/errors) with no
output, while the I<Test> functions use L<Test::Builder> to produce the
approriate test results and diagnostics for the test harness.


The directory will be automatically cleaned up when the object goes out of
scope; see the I<clean> method below for details.

=head2 CONSTRUCTOR

=over

=item B<new>(I<$path> [,I<$options>])

Create a new instance pointing to the specified I<$path>. I<$options> is 
an optional hashref of options.

I<$path> will be created it necessary.  If I<$options>->{unique} is set, it is
an error for I<$path> to already exist.

=back


=head2 UTILITY METHODS

=over

=item B<touch>(I<$file> ...)

Create the specified I<$file>s and track their state.

=item B<create>(I<$file>,I<%options>) 

Create the specified I<$file> and track its state.  The I<%options> hash
supports the following:

=over 8

=item B<time> => I<$timestamp>

Passed to L<perlfunc/utime> to set the files access and modification times.

=item B<content> => I<$data>

Write I<$data> to the file.

=back

=item B<name>(I<$file>)

Returns the name of the I<$file>, relative to the directory; including any
template substitutions.  I<$file> need not exist.

=item B<path>(I<$file>)

Returns the path for the I<$file>, including the directory name and any template
substitutions.  I<$file> need not exist.

=item B<check_file>(I<$file>)

Checks whether the specified I<$file> exists, and updates its state
accordingly.  Returns true if I<$file> exists, false otherwise.

=item B<remove_files>(I<$file>...) 

Remove the specified $I<file>s; return the number of files removed.

=item B<clean>

Remove all known files, then call I<rmdir> on the directory; returns the
status of the I<rmdir>.  The presence of any unknown files will cause the
rmdir to fail, leaving the directory with these unknown files.

This method is called automatically when the object goes out of scope.

=item B<count_unknown>

=item B<count_missing>

Returns a count of the unknown or missing files.

=back

=head2 TEST METHODS

The test methods validate the state of the test directory, calling
L<Test::Builder>'s I<ok> and I<diag> methods to generate output.

=over

=item B<has>  (I<$file>, I<$test_name>)

=item B<hasnt>(I<$file>, I<$test_name>)

Verify the status of I<$file>, and update its state.  The test will pass if
the state is expected.

=item B<is_ok>(I<$test_name>)

Pass if the test directory has no missing or extra files.

=item B<clean_ok>([I<$test_name>])

Equivalent to ok(clean,I<$test_name>)

=back

=head2 EXAMPLES

=head3 Calling an external program to move a file

 $dir->touch('my-file.txt');
 system ('gzip', $dir->path('my-file.txt'));
 $dir->has  ('my-file.txt.gz', '.gz file is added');
 $dir->hasnt('my-file.txt',    '.txt file is removed');
 $dir->is_ok; #verify no other changes to $dir

=head1 SEE ALSO

L<Test::Builder>

=head1 AUTHOR

Steve Sanbeg, E<lt>sanbeg@cpan.org<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Steve Sanbeg

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=cut
