#!/usr/bin/perl

use Test::More;

# plan skip_all => "Enable DEVEL_TESTS environent variable"
#   unless ($ENV{DEVEL_TESTS});

eval "use IO::Scalar";
plan skip_all => "IO::Scalar not installed" if ($@);

my $size = 3;

plan tests => 3 + (2*$size) + (2*($size+1));

use Algorithm::SkipList;

my $l = Algorithm::SkipList->new();

for (1..$size) { $l->insert($_, $size+$_); }

my $out = "";
my $fh  = new IO::Scalar \$out;

$l->_debug($fh);

ok($out ne "", "data written");

my @lines = split /\n/, $out;
ok(@lines != 0, "lines");

$l->_reset_iterator;

while (@lines) {
  my $line = shift @lines;
  # print STDERR "\x23 $line\n";
  if ($line ne "") {
    if ($line =~ /^(\w+)\=(\w+)\s(.+)/) {
      my ($k, $v, $t) = ($1, $2, $3);
      $count++;
      my $node = ($count > 1) ? $l->_next_node : $l->list;
      if ($count > 1) { # ignore first node
        is($k, $node->key, "key matches");
        is($v, $node->value, "value matches");  
      }
      else {
      }
      my $children = $node->child_count;
      ok($children > 0, "children > 0");
      ok($children <= $l->max_level);
    };
  }
}
is($count, $size+1, "node count");
