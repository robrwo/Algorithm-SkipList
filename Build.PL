require 5.006;

use Module::Build;

my $build = Module::Build->new
    (
     module_name => 'Algorithm::SkipList',
     license => 'perl',
     requires => {
       'base'                       => 0,
       'perl'                       => '5.6.0',
       'Carp'                       => 0,
       'Tree::Node'                 => 0.07,
       'self'                       => 0.30,
     },
     recommends => {
       'IO::Scalar'                 => 0, # for 80-dump.t
       'Test::Memory::Cycle'        => 0,
       'Test::Portability::Files'   => 0,
     },
     build_requires => {
       'Test::More'                 => 0,
     },
     autosplit => [
       'lib/Algorithm/SkipList.pm',
     ],
     create_makefile_pl => 'traditional',
     dist_author        => 'Robert Rothenberg <rrwo at cpan.org>',
     sign               => 0,
     create_readme      => ($Module::Build::VERSION > 0.2702),
);

$build->create_build_script;
