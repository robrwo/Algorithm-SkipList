#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

plan skip_all => "Enable DEVEL_TESTS environent variable"
  unless ($ENV{DEVEL_TESTS});

eval "use Test::Memory::Cycle";

plan skip_all => "Test::Memory::Cycle not installed" if ($@);

plan tests => 2;

use Algorithm::SkipList;

sub randomly {
  if (rand > 0.5) {
    return $a cmp $b;
  } else {
    return $b cmp $a;
  }
}

my @List = sort randomly (1..100);

my $l = Algorithm::SkipList->new();

my $count = 0;
foreach my $k (@List) {
  $l->insert($k, ++$count);
}

memory_cycle_ok($l);
weakened_memory_cycle_ok($l);
