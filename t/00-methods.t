#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

my @SkipListMethods = qw(
 new clear
 _search _search_with_finger exists search find find_with_finger
 insert delete
 reset least greatest first_key next_key
 TIEHASH STORE FETCH EXISTS CLEAR DELETE FIRSTKEY NEXTKEY
 size level list
 p k max_level node_class allow_duplicates
 find_duplicates next keys values truncate copy merge append
 _node_by_index key_by_index value_by_index index_by_key
);

use Algorithm::SkipList;

plan tests => scalar(@SkipListMethods);

foreach my $method (@SkipListMethods) {
  ok(Algorithm::SkipList->can($method), "SkipList can $method");
}
