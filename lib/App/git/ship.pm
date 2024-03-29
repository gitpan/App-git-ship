package App::git::ship;

=head1 NAME

App::git::ship - Git command for shipping your project

=head1 VERSION

0.12

=head1 DESCRIPTION

L<App::git::ship> is a L<git|http://git-scm.com/> command for building and
shipping your project.

The main focus is to automate away the boring steps, but at the same time not
get in your (or any random contributor) way. Problems should be solved with
sane defaults according to standard rules instead of enforcing more rules.

This project can also L</start> (create) a new project, just L</build> (prepare
for L<shipping|/ship>) and L</clean> projects.

L<App::git::ship> differ from other tools like L<dzil|Dist::Zilla> by not
enforcing new ways to do things, but rather incorporate with the existing
way. Example structure and how L<App::git::ship> works on your files:

=over 4

=item * my-app/cpanfile and my-app/Makefile.PL

The L<cpanfile> is used to build the "PREREQ_PM" and "BUILD_REQUIRES"
structures in the L<ExtUtils::MakeMaker> based C<Makefile.PL> build file.
The reason for this is that L<cpanfile> is a more powerful format that can
be used by L<Carton> and other tools, so generating L<cpanfile> from
Makefile.PL would simply not be possible. Other data used to generate
Makefile.PL are: 

"NAME", "LICENSE" will have values from L</project_name> and L</license>.
"AUTHOR" will have the name and email from the last git committer.
"ABSTRACT_FROM" and "VERSION_FROM" are fetched from the
L<main_module_path|App::git::ship::perl/main_module_path>.
"EXE_FILES" will be the files in C<bin/> or C<script/> which is executable.
"META_MERGE" will use data from L</bugtracker>, L</homepage> andL</repository>.

=item * my-app/CHANGELOG.md or my-app/Changes

The Changes file will be updated with the correct L<timestamp|/new_version_format>,
from when you ran the L</build> action. The Changes file will also be the source
for L</next_version>. Both C<CHANGELOG.md> and C<Changes> are valid sources.

=item * my-app/README

Will be updated with the main module documentation using the command below:

  $ perldoc -tT $main_module_path > README;

If you don't like this format, you can create C<README.md> instead. The
presense of that file will prevent "my-app/README" from getting generated.

=item * my-app/lib/My/App.pm

This L<file|App::git::ship::perl/main_module_path> will be updated with
version number from the Changes file.

=item * .gitignore and MANIFEST.SKIP

Unless these files exist, they will be generated from a template which skip
the most common files. The default content of these files might change over
time if new temp files are created by new editors or some other formats come
along.

=item * t/00-basic.t

Unless this file exists, it will be created with a test for checking
that your modules can compile and that the POD is correct. The file can be
customized afterwards and will not be overwritten.

=back

=head1 SYNOPSIS

=head2 Existing project

  # Set up .ship config and basic repo files
  $ cd my-project
  $ git ship start

  # make changes
  $ $EDITOR lib/My/Project.pm

  # build first if you want to investigate the changes
  $ git ship build

  # ship the project to git (and CPAN)
  $ git ship

=head2 New project

  $ git ship -h
  $ git start My/Project.pm
  $ cd my-project

  # make changes
  $ $EDITOR lib/My/Project.pm

  # build first if you want to investigate the changes
  $ git ship build

  # ship the project to git (and CPAN)
  $ git ship

=head2 Git aliases

  # git build
  $ git config --global alias.build = ship build

  # git cl
  $ git config --global alias.cl = ship clean

  # git start
  # git start My/Project.pm
  $ git config --global alias.start = ship start

=head2 For developer

  package App::git::ship::some_language;
  use App::git::ship -base;

  # define attributes
  has some_attribute => sub {
    my $self = shift;
    return "default value";
  };

  # override the methods defined in App::git::ship
  sub build {
    my $self = shift;
  }

  1;

=head1 CONFIG

C<App::git::ship> automatically generates a config file when you L</start> a
new project.

=over 4

=item * bugtracker

URL to the bugtracker for this project.

=item * build_test_options

This holds the arguments for the test program to use when building the
project. The default is to not automatically run the tests. Example value:

  build_test_options = -l -j4

=item * class

This class is used to build the object that runs all the actions on your
project. This is autodetected by looking at the structure and files in
your project. For now this value can be L<App::git::ship> or
L<App::git::ship::perl>, but any customization is allowed.

=item * homepage

URL to the home page for this project.

=item * license

The name of the license to use. Defaults to "artistic_2".

=item * new_version_format

This is optional, but specifies the version format in your "Changes" file.
The example below will result in "## 0.42 (2014-01-28)".

  new_version_format = \#\# %v (%F)

"%v" will be replaced by the version, while the format arguments are passed
on to L<POSIX/strftime>.

The default is "%-7v  %a %b %e %H:%M:%S %Y".

=item * project_name

This name is extracted from either the L<App::git::ship::perl/main_module_path>
or defaults to "unknown" if no project name could be found. Example:

  project_name = My::App

=item * Comments

Comments are made by adding the hash symbol (#) followed by text. If you want
to use the "#" as a value, it need to be escaped using "\#". Examples:

  # This whole line is skipped
  parameter = 123 # The end of this line is skipped
  parameter = some \# value with hash

=item * Hooks

It is possible to add hooks to the L</CONFIG> file. These hooks are
programs that runs in your shell. Example L<.ship|/CONFIG> file with hooks:

  before_build = bash script/new-release.sh
  after_build = rm -r lib/My/App/templates lib/My/App/public
  after_ship = cat Changes | mail -s "Changes for My::App" all@my-app.com

Possible hook are C<before_build>, C<after_build>, C<before_ship> and C<after_ship>.

=back

=cut

use feature ':5.10';
use strict;
use warnings;
use Carp;
use Data::Dumper ();
use File::Basename 'dirname';
use File::Find ();
use File::Path 'make_path';
use File::Spec ();

use constant DEBUG => $ENV{GIT_SHIP_DEBUG} || 0;

our $VERSION = '0.12';

my %DATA;

=head1 ATTRIBUTES

=head2 config

  $hash_ref = $self->config;

Holds the configuration from end user. The config is by default read from
C<.ship.conf> in the root of your project.

=head2 next_version

  $str = $self->next_version;

Holds the next version to L</ship>.

=head2 project_name

  $str = $self->project_name;

Holds the name of the current project. This attribute can be read from
L</config>.

=head2 repository

  $str = $self->repository;

Returns the URL to the first repository that point to "origin".
This attribute can be read from L</config>.

=head2 silent

  $bool = $self->silent;
  $self = $self->silent($bool);

Set this to true if you want less logging. By default it silent is false.

=cut

__PACKAGE__->attr(config => sub {
  my $self = shift;
  my $file = $ENV{GIT_SHIP_CONFIG} || '.ship.conf';
  my $config;

  open my $CFG, '<', $file or $self->abort("Read $file: $!");

  while (<$CFG>) {
    chomp;
    warn "[ship::config] $_\n" if DEBUG == 2;
    m/\A\s*(?:\#|$)/ and next; # comments
    s/\s+(?<!\\)\#\s.*$//; # remove inline comments
    m/^\s*([^\=\s][^\=]*?)\s*=\s*(.*?)\s*$/ or next;
    my ($k, $v) = ($1, $2);
    $config->{$k} = $v;
    $config->{$k} =~ s!\\\#!#!g;
    warn "[ship::config] $1 = $2\n" if DEBUG;
  }

  return $config;
});

__PACKAGE__->attr(next_version => sub { 0 });

__PACKAGE__->attr(project_name => sub {
  my $self = shift;
  return $self->config->{project_name} if $self->config->{project_name};
  return 'unknown';
});

__PACKAGE__->attr(repository => sub {
  my $self = shift;
  open my $REPOSITORIES, '-|', q( git remote -v ) or $self->abort("git remote -v: $!");
  my ($repository) = grep { /^origin\b.*\bpush\b/ } <$REPOSITORIES>;
  $repository = sprintf 'https://github.com/%s', $repository ? (split /[:\s+]/, $repository)[2] : lc(join '/', (getpwuid $<)[0], $self->project_name =~ s!::!-!gr);
  warn "[ship::repository] $repository\n" if DEBUG;
  $repository;
});

__PACKAGE__->attr(silent => sub { $ENV{GIT_SHIP_SILENT} // 0 });

=head1 METHODS

=head2 abort

  $self->abort($str);
  $self->abort($format, @args);

Will abort the application run with an error message.

=cut

sub abort {
  my ($self, $format, @args) = @_;
  my $message = @args ? sprintf $format, @args : $format;

  Carp::confess("!! $message") if DEBUG;
  die "!! $message\n";
}

=head2 attr

  $class = $class->attr($name => sub { my $self = shift; return $default_value });

or ...

  use App::git::ship -base;
  has $name => sub { my $self = shift; return $default_value };

Used to create an attribute with a lazy builder.

=cut

sub attr {
  my ($self, $name, $default) = @_;
  my $class = ref $self || $self;
  my $code = "";

  $code .= "package $class; sub $name {";
  $code .= "return \$_[0]->{$name} if \@_ == 1 and exists \$_[0]->{$name};";
  $code .= "return \$_[0]->{$name} = \$_[0]->\$default if \@_ == 1;";
  $code .= "\$_[0]->{$name} = \$_[1] if \@_ == 2;";
  $code .= '$_[0];}';

  eval "$code;1" or die "$code: $@";

  return $self;
}

=head2 build

This method builds the project. The default behavior is to L</abort>.
Need to be overridden in the subclass.

=cut

sub build {
  $_[0]->abort('build() is not available for %s', ref $_[0]);
}

=head2 can_handle_project

  $bool = $class->can_handle_project($file);

This method is called by L<App::git::ship/detect> and should return boolean
true if this module can handle the given git project.

This is a class method which gets a file as input to detect or have to
auto-detect from current working directory.

=cut

sub can_handle_project { $_[1] ? 0 : 1 }

=head2 detect

  $class = $self->detect;
  $class = $self->detect($file);

Will detect the module which can be used to build the project. This
can be read from the "class" key in L</config> or will in worse
case default to L<App::git::ship>.

=cut

sub detect {
  my $self = shift;
  my $file = 'auto-detect';

  if (!@_ and $self->config->{class}) {
    my $class = $self->config->{class};
    eval "require $class;1" or $self->abort("Could not load $class: $@");
    return $class;
  }
  else {
    $file = shift;
    require Module::Find;
    for my $class (sort { length $b <=> length $a } Module::Find::findallmod(__PACKAGE__)) {
      eval "require $class;1" or next;
      next unless $class->can('can_handle_project');
      warn "[ship::detect] $class->can_handle_project($file)\n" if DEBUG;
      return $class if $class->can_handle_project($file);
    }
  }

  $self->abort("Could not figure out what kind of project this is from '$file'");
}

=head2 run_hook

  $self->run_hook($name);

Used to run a hook before or after an event. The hook is a command which
needs to be defined in the config file. Example config line parameter:

  before_build = echo foo > bar.txt

=cut

sub run_hook {
  my ($self, $name) = @_;
  my $cmd = $self->config->{$name} or return;
  $self->system($cmd);
}

=head2 new

  $self = $class->new(%attributes);

Creates a new instance of C<$class>.

=cut

sub new {
  my $class = shift;
  my $self = bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;

  open $self->{STDOUT}, '>&STDOUT';
  open $self->{STDERR}, '>&STDERR';

  $self;
}

=head2 render

  $self->render($file, \%args);

Used to render a template by the name C<$file> to a C<$file>. The template
need to be defined in the C<DATA> section of the current class or one of
the super classes.

=cut

sub render {
  my ($self, $name, $args) = @_;
  my $file = File::Spec->catfile(split '/', $name);
  my $class = ref $self;
  my $str;

  if (-e $file and !$args->{force}) {
    say "# $file exists" unless $self->silent;
    return $self;
  }

  no strict 'refs';
  for my $c ($class, @{"$class\::ISA"}) {
    $str = $c->_data->{$name} and last;
  }

  $self->abort("Could not find template for $name") unless $str;

  local @_ = ($self, $args);
  $str =~ s!<%=(.+?)%>!{
            my $x = eval $1 // die DEBUG ? "($1) => $@" : $@;
            ref $x ? Data::Dumper->new([$x])->Indent(1)->Terse(1)->Sortkeys(1)->Dump : $x;
          }!sge;

  return $str if $args->{to_string};
  make_path dirname($file) or $self->abort("Could not make directory for $file") unless -d dirname $file;
  open my $FH, '>', $file or $self->abort("Could not write $name to $file $!");
  print $FH $str;
  say "# Generated $file" unless $self->silent;
}

=head2 ship

This method ships the project to some online repository. The default behavior
is to make a new tag and push it to "origin".

=cut

sub ship {
  my $self = shift;
  my ($branch) = qx(git branch) =~ /\* (.+)$/m;

  $self->abort("Cannot ship without a current branch") unless $branch;
  $self->abort("Cannot ship without a version number") unless $self->next_version;
  $self->system(qw( git push origin ), $branch);
  $self->system(qw( git tag ) => $self->next_version);
  $self->system(qw( git push --tags origin ));
}

=head2 start 

This method is called when initializing the project. The default behavior is
to populate L</config> with default data:

=over 4

=item * bugtracker

URL to the bug tracker. Will be the the L</repository> URL without ".git", but
with "/issues" at the end instead.

=item * homepage

URL to the project homepage. Will be the the L</repository> URL, without ".git".

=item * license

The name of the license. Default to L<artistic_2|http://www.opensource.org/licenses/artistic-license-2.0>.

See L<CPAN::Meta::Spec/license> for alternatives.

=back

=cut

sub start {
  my $self = shift;

  if (@_ and ref($self) eq __PACKAGE__) {
    return $self->detect($_[0])->new($self)->start(@_);
  }

  $self->config({}); # make sure repository() does not die
  $self->system(qw( git init )) unless -d '.git' and @_;
  $self->render('.ship.conf', { homepage => $self->repository =~ s!\.git$!!r });
  $self->render('.gitignore');
  $self->system(qw( git add . ));
  $self->system(qw( git commit -m Initialized )) if @_;
  delete $self->{config}; # regenerate config from .ship.conf
  $self;
}

=head2 system

  $self->system($program, @args);

Same as perl's C<system()>, but provides error handling and logging.

=cut

sub system {
  my ($self, $program, @args) = @_;
  my $exit_code;

  if ($self->silent) {
    open STDERR, '>', File::Spec->devnull;
    open STDOUT, '>', File::Spec->devnull;
  }
  else {
    my $log = "$program @args";
    $log =~ s!\n\r?!\\n!g;
    say "\$ $log" unless $self->silent;
  }

  local $?;
  system $program => @args;
  $exit_code = $? >> 8;

  if ($self->silent) {
    open STDERR, '>&', $self->{STDERR};
    open STDOUT, '>&', $self->{STDOUT};
  }

  $self->abort("'$program @args' failed: $exit_code") if $exit_code;
  $self;
}

=head2 test_coverage

This method check test coverage for the project. The default behavior is to
L</abort>. Need to be overridden in the subclass.

=cut

sub test_coverage {
  $_[0]->abort('test_coverage() is not available for %s', ref $_[0]);
}

=head2 import

  use App::git::ship;
  use App::git::ship -base;

Called when this class is used. It will automatically enable L<strict>,
L<warnings>, L<utf8> and Perl 5.10 features.

C<-base> will also make sure the calling class inherit from
L<App::git::ship> and gets the L<has|/attr> function.

=cut

sub import {
  my ($class, $arg) = @_;
  my $caller = caller;

  if ($arg and $arg eq '-base') {
    no strict 'refs';
    push @{"${caller}::ISA"}, __PACKAGE__;
    *{"${caller}::has"} = sub { attr($caller, @_) };
    *{"${caller}::DEBUG"} = \&DEBUG;
  }

  feature->import(':5.10');
  strict->import;
  warnings->import;
}

# Taken from Mojo::Loader
sub _data {
  my $class = shift;

  return $DATA{$class} if $DATA{$class};
  my $handle = do { no strict 'refs'; \*{"${class}::DATA"} };
  return {} unless fileno $handle;
  seek $handle, 0, 0;
  my $data = join '', <$handle>;

  # Ignore everything before __DATA__ (Windows will seek to start of file)
  $data =~ s/^.*\n__DATA__\r?\n/\n/s;

  # Ignore everything after __END__
  $data =~ s/\n__END__\r?\n.*$/\n/s;

  # Split files
  (undef, my @files) = split /^@@\s*(.+?)\s*\r?\n/m, $data;

  # Find data
  my $all = $DATA{$class} = {};
  while (@files) {
    my $name = shift @files;
    $all->{$name} = shift @files;
  }

  return $all;
}

=head1 SEE ALSO

=over

=item * L<Dist::Zilla>

This project can probably get you to the moon.

=item * L<Minilla>

This looks really nice for shipping your project. It has the same idea as
this distribution: Guess as much as possible.

=item * L<Shipit>

One magical tool for doing it all in one bang.

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;

__DATA__
@@ .ship.conf
# Generated by git-ship. See 'git-ship --man' for help or https://github.com/jhthorsen/app-git-ship
class = <%= ref $_[0] %>
project_name = 
homepage = <%= $_[1]->{homepage} %>
bugtracker = <%= join('/', $_[1]->{homepage}, 'issues') =~ s!(\w)//!$1/!r %>
license = artistic_2
build_test_options = # Example: -l -j8
@@ .gitignore
~$
*.bak
*.old
*.swp
/local
@@ test
test = <%= $_[1]->{x} %> + <%= $_[0]->can_handle_project %>.
