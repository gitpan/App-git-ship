use t::Util;
use App::git::ship::perl;

t::Util->goto_workdir('perl-build', 0);

{
  my $app = App::git::ship::perl->new;
  my $main_module_path;

  $app->start('Perl/Build.pm', 0);
  $main_module_path = $app->main_module_path;

  mkdir 'bin';
  touch(File::Spec->catfile("bin", $_)) for qw( e-x-e foo );
  chmod 0755, File::Spec->catfile(qw( bin e-x-e ));

  $app->_render_makefile_pl;
  t::Util->test_file(
    'Makefile.PL',
    qr{^\# Generated by git-ship. See 'git-ship --man'}m,
    qr{use ExtUtils::MakeMaker;[\r\n\s]+WriteMakefile\(}s,
    qr{NAME => '.+?',}m,
    qr{AUTHOR => '[^,]+,}m,
    qr{LICENSE => 'artistic_2',}m,
    qr{ABSTRACT_FROM => '$main_module_path',}m,
    qr{VERSION_FROM => '$main_module_path',}m,
    qr{bugtracker => 'https:},
    qr{homepage => 'https:},
    qr{repository => 'https:},
    qr{BUILD_REQUIRES => .*?\bTest::More\b}s,
    qr{PREREQ_PM => .*?\bperl\b}s,
  );

  TODO: {
    local $TODO = -x "bin/e-x-e" ? "" : "Cannot test on $^O";
    t::Util->test_file('Makefile.PL', qr{EXE_FILES => \[qw\( bin/e-x-e \)\]}s);
  }

  t::Util->test_file('Changes', qr{^[\d\.]+$}m);
  $app->_timestamp_to_changes for 1..3; # need to see what happens if you run multiple times
  t::Util->test_file('Changes', qr{^[\d\.]+\s+\w+\s}m);

  create_main_module();
  $app->_update_version_info;
  t::Util->test_file(
    File::Spec->catfile(qw( lib Perl Build.pm )),
    qr{^0\.01}m,
    qr{^our \$VERSION = '0\.01';}m,
  );

  add_version_to_changes("0.$_") for 1..3;
  like $app->_changes_to_commit_message, qr{^Released version 0\.3}s, '_changes_to_commit_message()';
  like $app->_changes_to_commit_message, qr{^Released version 0\.3\n\n\W+Some other cool feature for 0\.3\.\n\n$}s, '_changes_to_commit_message() reset diamond operator';

  touch($_) for qw( foo foo~ foo.bak foo.swp foo.old MYMETA.json );
  $app->_make('manifest');
  t::Util->test_file_lines('MANIFEST', qw( bin/e-x-e bin/foo .ship.conf Changes cpanfile foo lib/Perl/Build.pm Makefile.PL t/00-basic.t ), qr{^MANIFEST\s+});
}

done_testing;

sub create_main_module {
  open my $MAIN_MODULE, '>', File::Spec->catfile(qw( lib Perl Build.pm ));
  print $MAIN_MODULE "package Perl::Build;\n=head1 NAME\n\nPerl::Build\n\n=head1 VERSION\n\n0.00\n\n=cut\n\nour \$VERSION = '42';\n\n1";
}


sub add_version_to_changes {
  my $version = shift;
  local @ARGV = ('Changes');
  local $^I = '';
  while (<>) {
    print "$version\n       * Some other cool feature for $version.\n\n" if $. == 3;
    print;
  }
}

sub touch {
  open my $FH, '>>', shift;
}
