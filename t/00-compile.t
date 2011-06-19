#!/usr/bin/perl

use strict;
use warnings;

use constant MINIMUM_VERSION => '2.00';

use Test::More;

my @Modules = qw(
  Algorithm::SkipList
  Algorithm::SkipList::Node
  Algorithm::SkipList::Header
);

plan tests => scalar(@Modules);

foreach my $name (@Modules) {
  use_ok($name, MINIMUM_VERSION);
}



