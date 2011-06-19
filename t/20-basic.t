#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

sub randomly {
  if (rand > 0.5) {
    return $a cmp $b;
  } else {
    return $b cmp $a;
  }
}

my @List = sort randomly (1..20);
# print STDERR "\x23 @List\n";

plan 
# skip_all => "tests disabled";
 tests => 18 + (46 * scalar(@List));

use_ok("Algorithm::SkipList", 2.00);

{
  my $l = Algorithm::SkipList->new();
  ok(defined $l, "new defined");
  ok($l->isa("Algorithm::SkipList"), "isa");

  ok($l->list->isa("Tree::Node"), "list->isa");
  ok($l->list->child_count >= $l->level, "list->level >= level");

  my $count = 0;
  foreach my $key (@List) {
    ok($l->size == $count, "size (before insert)");

    my ($n, $c, $f) = $l->_search($key);
    ok($c != 0, "_search failed");
    ($n, $c, $f) = $l->_search_with_finger($key);
    ok($c != 0, "_search_with_finger failed");

    ok(!$l->exists($key), "!exists");
    ok(!$l->find($key), "!find");
    ok(!$l->find_with_finger($key), "!find_with_finger");

    my $h = $l->level;
    $l->insert($key, ++$count);
    ok($l->size == $count, "size (after insert)");
    ok($l->level >= $h, "level");

    ($n, $c, $f) = $l->_search($key);
    ok($c == 0, "_search success");
    ok($n->key eq $key, "key eq key");
    ok($n->key_cmp($key) == 0, "key_cmp == 0");
    ok(!defined $f, "no finger");
    ok($n->value == $count, "value");

    ($n, $c, $f) = $l->_search_with_finger($key);
    ok($c == 0, "_search_with_finger success");
    ok($n->key eq $key, "key eq key");
    ok($n->key_cmp($key) == 0, "key_cmp == 0");
    ok(defined $f, "finger");
    ok($n->value == $count, "value");

    ($n, $c, $f) = $l->_search_with_finger($key, $f);
    ok($c == 0, "_search_with_finger (using finger) success");
    ok($n->key eq $key, "key eq key");
    ok($n->key_cmp($key) == 0, "key_cmp == 0");
    ok(defined $f, "finger");
    ok($n->value == $count, "value");

    ok($l->exists($key), "exists");
    ok($l->find($key), "find");
    ok($l->find($key,$f), "find (using finger)");
    ok($l->find_with_finger($key), "find_with_finger");
    ok($l->find_with_finger($key,$f), "find_with_finger (using finger)");

    my ($v, $u) = $l->find_with_finger($key);
    ok($v, "find_with_finger (array context)");
    ok($u, "find_with_finger (array context) returned finger");

    ($v, $u) = $l->find_with_finger($key,$f);
    ok($v, "find_with_finger (array context, using finger)");
    ok($u, "find_with_finger (array context, using finger) returned finger");
  }

  # Check that keys are in order

  my $n = $l->list;
  my $key = "";
  do {
    $n = $n->get_child(0);
    if ($n) {
      ok($n->key_cmp($key) == 1);
      $key = $n->key;
    }
  } while ($n);

  $key = "";
  do {
    $n = $l->_next_node;
    if ($n) {
      ok($n->key_cmp($key) == 1);
      $key = $n->key;
    }
  } while ($n);


  ok($l->_first_node->key eq $l->list->get_child(0)->key);

  {
    my @o = sort @List;

    my ($a, $b) = $l->least;
    my ($c, $d) = $l->greatest;
    
    ok($a eq $o[0], "first key");
    ok($c eq $o[-1], "last key");

    ok($l->find($a) eq $b, "first value");
    ok($l->find($c) eq $d, "last value");

    my $s = $l->size;
    ok($l->delete($c) eq $d, "delete last value");
    ok($l->size == ($s-1), "size shrank");
    my ($e, $f) = $l->greatest;
    ok(defined $e, "next to last key not undef");
    ok($e eq $o[-2], "next to last key less than last key");

    $l->insert($c, $d); # so we can run normal tests on deletions...

    my $m = Algorithm::SkipList->new();
    ok(!defined $m->least, "least undef in empty list");
    ok(!defined $m->greatest, "greatest undef in empty list");

    ok($l->first_key eq shift @o);
    while (@o) {
      ok($l->next_key eq shift @o);
    }
  }

  # test copies

  my $k = $l->copy;
  ok($k->isa("Algorithm::SkipList"), "copy isa");
  ok($l->size == $k->size, "comparing sizes");
  $l->_reset_iterator;
  $k->_reset_iterator;
  while (my $n = $l->_next_node) {
    my $m = $k->_next_node;
    ok(ref($n) eq ref($m), "comparing ref types");
    ok($n->key eq $m->key, "comparing key copies");
    ok($n->value eq $m->value, "comparing value copies");
  } 

  # test truncate

  foreach my $key (@List ){
    my $copy = $l->copy;
    my $tail = $copy->truncate($key);
    is(($copy->size + $tail->size), $l->size, "sizes add up from truncate");
    is($tail->first_key, $key, "expected first key of truncate");
    my $n = $copy->_last_node;
    is($n->key_cmp($key), -1, "copy->_last_node->key_cmp(key)");

    $copy->append($tail);
    is($copy->size, $l->size, "appended size correct");
    is($tail->size, 0, "tail truncated");
  }
  
  # test deletions

  $count = 0;
  foreach my $key (@List) {
    my $s = $l->size;
    my $h = $l->level;
    ok($l->delete($key) == ++$count, "delete");
    ok($l->size == ($s-1), "size decreased");
    ok($l->level == $h, "level decreases?");
  }


#   my $n = Algorithm::SkipList::Node->new("a", 1, [(undef) x 2]);
#   for(my $i=0; $i<$n->level; $i++) {
#     $n->set_next($i, $l->list->get_next($i));
#     $l->list->set_next($i,$n);
#   }


#   my ($m, $c, $f) = $l->_search($n->key);
#   ok(!$c, "_search success");

#   ok($m->key eq "a", "keys match");
#   ok($m == $n, "nodes match");
#   ok(!defined $f, "no finger");

#   ($m, $c, $f) = $l->_search_with_finger("a");
#   ok($c==0, "_search_with_finger success");
#   ok($m->key eq "a", "keys match");
#   ok($m == $n, "nodes match");
#   ok(defined $f, "finger");
#   ok(UNIVERSAL::isa($f, "ARRAY"), "finger is an array ref");
#   ok(defined $f->[0]);
#   # This may change in optimisation
#   # ok($f->[0]->get_next(0) == $n, "finger points to node");

#   ($m, $c, $f) = $l->_search_with_finger("a", $f);
#   ok($c==0, "_search_with_finger (using finger) success");
#   ok($m->key eq "a", "keys match");
#   ok($m == $n, "nodes match");
#   ok(defined $f, "finger");
#   ok(UNIVERSAL::isa($f, "ARRAY"), "finger is an array ref");
#   ok(defined $f->[0]);
#   # This may change in optimisation
#   # ok($f->[0]->get_next(0) == $n, "finger points to node");

}






