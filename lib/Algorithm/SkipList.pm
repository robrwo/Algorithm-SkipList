=head1 NAME

Algorithm::SkipList - Perl implementation of skip lists

=begin readme

=head1 REQUIREMENTS

The following non-core modules are used:

  Tree::Node

=head1 INSTALLATION

Installation can be done using the traditional F<Makefile.PL> or the
newer F<Build.PL> method .

Using Makefile.PL:

  perl Makefile.PL
  make test
  make install

(On Windows platforms you should use F<nmake> instead.)

Using Build.PL (if you have L<Moddule::Build> installed):

  perl Build.PL
  perl Build test
  perl Build install

=end readme

=head1 SYNOPSIS

  my $list = new Algorithm::SkipList();

  $list->insert( 'key1', 'value' );
  $list->insert( 'key2', 'another value' );

  $value = $list->find('key2');

  $list->delete('key1');

=head1 DESCRIPTION

This is an implementation of skip lists in Perl.

Skip lists are an alternative to balanced trees. They are ordered
linked lists with random links at various I<levels> that allow
searches to skip over sections of the list, like so:

  4 +---------------------------> +----------------------> +
    |                             |                        |
  3 +------------> +------------> +-------> +-------> +--> +
    |              |              |         |         |    |
  2 +-------> +--> +-------> +--> +--> +--> +-------> +--> +
    |         |    |         |    |    |    |         |    |
  1 +--> +--> +--> +--> +--> +--> +--> +--> +--> +--> +--> +
         A    B    C    D    E    F    G    H    I    J   NIL

A search would start at the top level: if the link to the right
exceeds the target key, then it descends a level.

Skip lists generally perform as well as balanced trees for searching
but do not have the overhead with respect to reblanacing the structure.
And on average, they use less memory than trees.

They also use less memory than hashes, and so are appropriate for
large collections.

=for readme stop

For more information on skip lists, see the L</"SEE ALSO"> section below.

=head2 METHODS

=cut

package Algorithm::SkipList;

use 5.006;
use strict;
use warnings::register __PACKAGE__;

our $VERSION = '2.00_03';
$VERSION = eval $VERSION;

use self;

use Carp qw( carp croak );
use Tree::Node;
use Algorithm::SkipList::Header;

use constant MAX_LEVEL       => 31;
use constant MIN_LEVEL       =>  1;

use constant DEFAULT_P       => 0.25;
use constant DEFAULT_K       => 0;

# We could use Algorithm::SkipList::Node, which exists as a stub. But
# there's just no point to it.

use constant DEFAULT_NODE_CLASS => 'Tree::Node';

# This is an internal routine which defines valid configuration options and
# their default values.  It is meant to be called by the BEGIN block (see
# source code below) that creates access methods for these options.

my %CONFIG_OPTIONS;

sub _set_config_options {
  %CONFIG_OPTIONS = (
    p                => DEFAULT_P,
    k                => DEFAULT_K,
    min_level        => MIN_LEVEL,
    max_level        => MAX_LEVEL,
    node_class       => DEFAULT_NODE_CLASS,
    allow_duplicates => 0,
  );
}

=over

=item new

  $list = new Algorithm::SkipList();

Creates a new skip list.

If you need to use a different L<node class|/"Node Methods"> for using
customized L<comparison|/"key_cmp"> routines, you will need to specify a
different class:

  $list = new Algorithm::SkipList( node_class => 'MyNodeClass' );

See the L</"Customizing the Node Class"> section below.

Specialized internal parameters may be configured:

  $list = new Algorithm::SkipList( max_level => 31 );

Defines a different maximum list level (the default is 31).

The initial list (see the L</"list"> method) will start out at one
level, and will increase as the size of the list doubles, up intil
it reaches the maximum level.

The default minimum level can be changed:

  $list = new Algorithm::SkipList( min_level => 4 );

You can also control the probability used to determine level sizes for
each node by setting the L<P|/"p"> and k values:

  $list = new Algorithm::SkipList( p => 0.25, k => 1 );

See  L</p> for more information on this parameter.

You can enable duplicate keys by using the following:

  $list = new Algorithm::SkipList( allow_duplicates => 1 );

This is an experimental feature. See the L</KNOWN ISSUES> section
below.

=cut

sub new {
  my $class = shift || __PACKAGE__;
  my $self  = {
    p                => DEFAULT_P,
    k                => DEFAULT_K,
    p_levels         => [ ],            # array used by random_level
  };

  bless $self, $class;

  # Set default values

  foreach my $field (CORE::keys %CONFIG_OPTIONS) {
    my $method = "_set_" . $field;
    $self->$method( $CONFIG_OPTIONS{$field} );
  }

  # Update user-settings

  if (@_) {
    while (my $arg = shift) {
      if (exists $CONFIG_OPTIONS{$arg}) {
	my $value = shift;
	my $method = "_set_" . $arg;
	$self->$method($value);
      }
      else {

	croak "Unknown option: \'$arg\'";
      }
    }
  }

  # Additional user-settings checks, since the practical way to check is
  # after all of the settings have been changed.

  if ($self->min_level > $self->max_level) {
    croak "min_level > max_level";
  }

  $self->clear;

  return $self;
}

=item list

  $node = $list->list;

Returns the initial node in the list.  Accessing accessors other than
C<set_child> and C<get_child> will trigger an error.

This method is meant for internal use.

=cut

sub list {
  return $self->{list};
}

=item level

  $level = $list->level;

Returns the current maximum level (number of forward pointers) that
any node can have.  It will not be larger than L</max_level>, nor
does it correspond to the number of nodes in L</list>.

This method is meant for internal use.

=cut

sub level {
  return $self->{level};
}

=item clear

  $list->clear;

Erases existing nodes and resets the list.

=cut

sub clear {
  $self->{list}      = Algorithm::SkipList::Header->new(MAX_LEVEL);
  $self->{level}     = MIN_LEVEL;

  if ($self->{max_level} > $self->{list}->child_count) {
    $self->{max_level} = $self->{list}->child_count;
    carp sprintf('max_level downgraded to %d due to limits of list header',
		 $self->{list}->child_count) if (warnings::enabled);
  }

  $self->{size}      = 0;

  $self->{size_threshold}      = 2**($self->{level});
  $self->{last_size_threshold} = $self->{size};

  $self->{last_node} = undef;

  $self->_reset_iterator;
}

=begin internal

=item _search

  ($node, $cmp) = $list->_search( $key );

  ($node, $cmp) = $list->_search( $key, $finger );

Same as L</_search_with_finger>, only that no search finger is returned.

This is useful for searches where a finger is not needed.  The speed
of searching is improved.

Note that as of version 2.00, the order of return values has been
changed.

=end internal

=cut

sub _search {
  my ($key, $finger) = @args;

  use integer;

  my $list   = $self->list;
  my $level  = $self->level-1;

  my $node   = $finger->[ $level ] || $list;

  my $fwd;
  my $cmp = -1;

  do {
    while ( ($fwd = $node->get_child($level)) &&
	    ($cmp = $fwd->key_cmp($key)) < 0) {
      $node = $fwd;
    }
  } while ((--$level>=0) && $cmp);

 $node = $fwd, unless ($cmp);

  return ($node, $cmp);
}

=begin internal

=item _search_with_finger

  ($node, $cmp, $finger) = $list->_search_with_finger( $key );

Searches for the node with a key.  If the key is found, that node is
returned along with a L</"header">.  If the key is not found, the previous
node from where the node would be if it existed is returned.

Note that the value of C<$cmp>

  $cmp = $node->key_cmp( $key )

is returned because it is already determined by L</_search>.

Search fingers may also be specified:

  ($node, $cmp, $finger) = $list->_search_with_finger( $key, $finger );

See the section L</"About Search Fingers"> below.

Note that as of version 2.00, the order of return values has been
changed.

=end internal

=cut

sub _search_with_finger {
  my ($key, $finger) = @args;

  use integer;

  my $list   = $self->list;
  my $level  = $self->level-1;

  my $node   = $finger->[ $level ] || $list;

  my $fwd;
  my $cmp = -1;

  do {
    while ( ($fwd = $node->get_child($level)) &&
	    ($cmp = $fwd->key_cmp($key)) < 0) {
      $node = $fwd;
    }
    $finger->[$level] = $node;
  } while (--$level>=0);

  # Ideally we could stop when $cmp == 0, but the update vector would
  # not be complete for levels below $level.

  $node = $fwd, unless ($cmp);

  return ($node, $cmp, $finger);
}

=item exists

  if ($list->exists( $key )) { ... }

Returns true if there exists a node associated with the key, false
otherwise.

This may also be used with  L<search fingers|/"About Search Fingers">:

  if ($list->exists( $key, $finger )) { ... }

=cut

sub exists {
  # my ($key, $finger) = @args;
  (($self->_search(@args))[1] == 0);
}

=item find_with_finger

  $value = $list->find_with_finger( $key );

Searches for the node associated with the key, and returns the value. If
the key cannot be found, returns C<undef>.

L<Search fingers|/"About Search Fingers"> may also be used:

  $value = $list->find_with_finger( $key, $finger );

To obtain the search finger for a key, call L</find_with_finger> in a
list context:

  ($value, $finger) = $list->find_with_finger( $key );

=cut

sub find_with_finger {
  ##my ($key, $finger) = @args;
  my ($node, $cmp);
     ($node, $cmp, $args[1]) = $self->_search_with_finger(@args);

  if ($cmp) {
    return;
  } else {
    return (wantarray) ? ($node->value, $args[1]) : $node->value;
  }
}

=item find

  $value = $list->find( $key );

  $value = $list->find( $key, $finger );

Searches for the node associated with the key, and returns the value. If
the key cannot be found, returns C<undef>.

This method is slightly faster than L</find_with_finger> since it does
not return a search finger when called in list context.

If you are searching for duplicate keys, you must use
L</find_with_finger> or L</find_duplicates>.

=cut

sub find {
  ## my ($key, $finger) = @args;
  my ($node, $cmp) = $self->_search(@args);

  if ($cmp) {
    return;
  } else {
    return $node->value;
  }
}

=item insert

  $list->insert( $key, $value );

Inserts a new node into the list.

Only alphanumeric keys are supported "out of the box".  To use numeric
or other types of keys, see L</"Customizing the Node Class"> below.

You may also use a L<search finger|/"About Search Fingers"> with insert,
provided that the finger is for a key that occurs earlier in the list:

  $list->insert( $key, $value, $finger );

Using fingers for inserts is I<not> recommended since there is a risk
of producing corrupted lists.

=cut

sub insert {
  my ($key, $value, $finger) = @args;

  use integer;

  # TODO: Track last node inserted and use it's update vector if the
  # key to be inserted is greater.

  my ($node, $cmp);
 ($node, $cmp, $finger) = $self->_search_with_finger($key, $finger);

  if ($cmp || $self->{allow_duplicates}) {

    my $level = $self->_new_node_level;
    $node = $self->node_class->new($level);
    $node->set_key($key);
    $node->set_value($value);

    my $list = $self->list;
    for(my $i=0; $i<$level; $i++) {
      $node->set_child($i, ($finger->[$i]||$list)->get_child($i));
      ($finger->[$i]||$list)->set_child($i, $node);
    }

    $self->{size}++;
    $self->_adjust_level_threshold;

    # Tracking the last node in the list. We cannot save the finger
    # since something could be inserted between $finger->[0] and the
    # last_node.

    $self->{last_node} = $node
      unless ($node->get_child(0));

  }
  else {
    $node->set_value($value);
  }
}

=item delete

  $value = $list->delete( $key );

Deletes the node associated with the key, and returns the value.  If
the key cannot be found, returns C<undef>.

L<Search fingers|/"About Search Fingers"> may also be used:

  $value = $list->delete( $key, $finger );

Calling L</delete> in a list context I<will not> return a search
finger.

=cut

sub delete {
  my ($key, $finger) = @args;

  use integer;

  my ($node, $cmp);
 ($node, $cmp, $finger) = $self->_search_with_finger(@args);

  if ($cmp) {
    return;
  }
  else {
    my $list = $self->list;
    for(my $i=0; $i<$node->child_count; $i++) {
      ($finger->[$i]||$list)->set_child($i, $node->get_child($i));
    }
    $self->{size}--;

    # It is only practical to adjust the level during inserts. If we
    # do this during deletes, we run into some problems.

    # $self->_adjust_level_threshold;

    $self->{last_node} = $finger->[0]
      unless ($node->get_child(0));

    return $node->value;
  }
}

=begin internal

  $list->_build_distribution;

This is an internal routine to update the probabilities for each node
level.  It is meant to be called each time L</p> or L</k> are updated.

=end internal

=cut

sub _build_distribution {
  no integer;

  my $p = $self->p;
  my $k = $self->k;

  $self->{p_levels} = [ (0) x MAX_LEVEL ];
  for my $i (0..MAX_LEVEL) {
    $self->{p_levels}->[$i] = $p**($i+$k);
  }
}

sub _set_p {
  no integer;

  my ($p) = @args;

  unless ( ($p>0) && ($p<1) ) {
    croak "Invalid value for P (must be between 0 and 1)";
  }

  $self->{p} = $p;
  $self->_build_distribution;
}

sub _set_k {

  my ($k) = @args;

  unless ( $k>=0 ) {
    croak "Invalid value for K (must be at least 0)";
  }

  $self->{k} = $k;
  $self->_build_distribution;
}

sub _set_min_level {
  my ($min_level) = @args;

  if ($self->size) {
    croak "min_level can only be set on an empty skip list";
  }

  if ( ($min_level < MIN_LEVEL) || ($min_level > MAX_LEVEL) ) {
    croak sprintf("Invalid value for min_level (must be between %d and %d)",
		  MIN_LEVEL, MAX_LEVEL);
  }

  $self->{min_level} = $min_level;
}

sub _set_max_level {
  my ($max_level) = @args;

  # We want to make sure that the user-supplied does not exceed the
  # maximum level of the list node (even though we specify that the
  # list node has MAX_LEVEL by default).

  my $max = MAX_LEVEL;
  if ((defined $self->list) && ($self->list->child_count < $max)) {
    $max = $self->list->child_count;
  }
  my $min = $self->min_level || MIN_LEVEL;

  if ( ($max_level < $min) || ($max_level > $max) ) {
    croak sprintf("Invalid value for max_level (must be between %d and %d)",
		  $min, $max);
  }
  $self->{max_level} = $max_level;
}

sub _adjust_level_threshold {
  use integer;

  if ($self->{size} == $self->{size_threshold}) {
    # $self->{last_size_threshold} = $self->{size_threshold};
    $self->{size_threshold}      += $self->{size_threshold};
    $self->{level}++,
      if ($self->{level} < $self->{max_level});
  }

#   elsif ($self->{size} < $self->{last_size_threshold}) {
#     $self->{size_threshold}  = $self->{last_size_threshold};
#     $self->{last_size_threshold} = $self->{last_size_threshold} / 2;
#
#     # We cannot practically decrease the level without readjusting the
#     # levels of all the nodes globally, which isn't worthwhile.
#
#     # $self->{level}--,
#     #   if ($self->{level} > MIN_LEVEL);
#   }
}

sub _new_node_level {
  no integer;

  my $n     = rand();
  my $level = 1;

  while (($n < $self->{p_levels}->[$level]) &&
	 ($level++ < $self->{level})) {
  }

  return $level;
}

sub _set_node_class {
  my ($node_class) = @args;
  unless ($node_class->isa( DEFAULT_NODE_CLASS )) {
    croak "$node_class is not a " . DEFAULT_NODE_CLASS;
  }
  $self->{node_class} = $node_class;
}

=item size

  $size = $list->size;

Returns the number of nodes in the list.

=cut

sub size {
  return $self->{size};
}

=item reset

  $list->reset;

Resets the iterator used by L</first_key> and L</next_key>.

=begin internal

=item _reset_iterator

This is the internal alias for L</reset>.

=end internal

=cut

sub _reset_iterator {
  $self->{iterator} = undef;
}

sub _set_iterator_by_key {
  ## my ($key, $finger) = @args;
  my ($node, $cmp) = $self->_search(@args);
  if ($cmp) {
    carp "key \'$args[0]\' not found" if (warnings::enabled);
    return $self->_reset_iterator;
  } else {
    return $self->{iterator} = $node;
  }
}

sub _first_node {
  $self->_reset_iterator;
  $self->_next_node;
}

sub _next_node {
  $self->{iterator} = ($self->{iterator} || $self->list)->get_child(0);
}

sub _last_node {
  return $self->{last_node};
}

=item first_key

  $key = $list->first_key;

Returns the first key in the list. Implicitly calls the iterator L</reset>
method.

=cut

sub first_key {
  my $node = $self->_first_node;
  return $node->key;
}

=item next_key

  $key = $list->next_key;

Returns the next key in the series.

  $key = $list->next_key($last_key);

Returns the key that follows the C<$last_key>.

  $key = $list->next_key($last_key, $finger);

Same as above, using the C<$finger> to search for the key.

=cut

sub next_key {
  my ($last_key, $finger) = @args;
  if (defined $last_key) {
    $self->_set_iterator_by_key($last_key, $finger);
  }

  my $node = $self->_next_node;
  return $node->key if ($node);
  return;
}


sub _error {
  croak "Method unimplemented";
}

BEGIN {
  *TIEHASH   = \&new;
  *STORE     = \&insert;
  *FETCH     = \&find;
  *EXISTS    = \&exists;
  *CLEAR     = \&clear;
  *DELETE    = \&delete;
  *FIRSTKEY  = \&first_key;
  *NEXTKEY   = \&next_key;

  *reset     = \&_reset_iterator;
  *search    = \&find;

    *merge   = \&_error;
    *find_duplicates = \&_error;
    *_node_by_index = \&_error;
    *key_by_index = \&_error;
    *index_by_key = \&_error;
    *value_by_index = \&_error;

  *_prev     = \&_error;
  *_prev_key = \&_error;

  _set_config_options();
  foreach my $field (CORE::keys %CONFIG_OPTIONS) {
    my $set_method = "_set_" . $field;
    no strict 'refs';
    *$field = sub {
      my $self = shift;
      if (@_) {
	$self->$set_method($field);
      } else {
	return $self->{$field};
      }
    };
    unless (__PACKAGE__->can($set_method)) {
      *$set_method = sub {
	my $self = shift;
        $self->{$field} = shift;
      };
    }
  }
}

1;

# __END__

=item least

  ($key, $value) = $list->least;

Returns the least key and value in the list, or C<undef> if the list
is empty.

=cut

sub least {
  my $node = $self->_first_node || return;
  return ($node->key, $node->value);
}

=item greatest

  ($key, $value) = $list->greatest;

Returns the greatest key and value in the list, or C<undef> if the list
is empty.

=cut

sub greatest {
  my $node = $self->_last_node || return;
  return ($node->key, $node->value);

}

=item next

  ($key, $value) = $list->next( $last_key, $finger );

Returns the next key-value pair.

C<$last_key> and C<$finger> are optional.

=cut

sub next {
  my ($last_key, $finger) = @args;
  if (defined $last_key) {
    $self->_set_iterator_by_key($last_key, $finger);
  }
  my $node = $self->_next_node;
  return ($node->key, $node->value);
}

=item keys

  @keys = $list->keys;

Returns a list of keys, in the order that they occur.

  @keys = $list->keys( $low, $high);

Returns a list of keys between C<$low> and C<$high>, inclusive. (This
is only available in versions 1.02 and later.)

=cut

sub keys {
  my ($low, $high, $finger) = @args;
  my @result = ( );
  if (defined $low) {
    push @result, $self->_set_iterator_by_key($low, $finger)->key;
  }
  else {
    $self->_reset_iterator;
  }

  my $node;
  while ( ($node = $self->_next_node) &&
	  ((!defined $high) || ($node->key_cmp($high) < 1) )) {
    push @result, $node->key;
  }
  return @result;
}

=item values

  @values = $list->values;

Returns a list of values corresponding to the keys returned by the
L</keys> method.  You can also request the values between a pair of
keys:

  @values = $list->values( $low, $high );

=cut

sub values {
  my ($low, $high, $finger) = @args;
  my @result = ( );
  if (defined $low) {
    push @result, $self->_set_iterator_by_key($low, $finger)->value;
  }
  else {
    $self->_reset_iterator;
  }

  my $node;
  while ( ($node = $self->_next_node) &&
	  ((!defined $high) || ($node->key_cmp($high) < 1) )) {
    push @result, $node->value;
  }
  return @result;
}


=item copy

  $list2 = $list1->copy;

Makes a copy of a list.  The configuration options passed to L</new> are
used, although the exact structure of node levels is not cloned.

  $list2 = $list1->copy( $key_from, $key_to, $finger );

Copy the list between C<$key_from> and C<$key_to> (inclusive).  If
C<$finger> is defined, it will be used as a search finger to find
C<$key_from>.  If C<$key_to> is not specified, then it will be assumed
to be the end of the list.

If C<$key_from> does not exist, C<undef> will be returned.

Note: the order of arguments has been changed since version 2.00!

=cut

sub copy {
  my ($low, $high, $finger) = @args;
  my %opts = map { $_ => $self->$_ } (CORE::keys %CONFIG_OPTIONS);
  my $copy = Algorithm::SkipList->new( %opts );

  if (defined $low) {
    my $node = $self->_set_iterator_by_key($low, $finger);
    $copy->insert($node->key, $node->value), if ($node);
  }
  else {
    $self->_reset_iterator;
  }

  my $node;
  while ( ($node = $self->_next_node) &&
	  ((!defined $high) || ($node->key_cmp($high) < 1) )) {
    $copy->insert($node->key, $node->value);
  }

  return $copy;
}

sub truncate {
  my ($key, $finger) = @args;

  my ($node, $cmp);
  ($node, $cmp, $finger) = $self->_search_with_finger($key, $finger);

  if ($cmp) {
    return;
  }
  else {
    my %opts = map { $_ => $self->$_ } (CORE::keys %CONFIG_OPTIONS);
    my $tail = Algorithm::SkipList->new( %opts );
    my $list = $tail->list;

    for(my $i=0; $i<@$finger; $i++) {
      $list->set_child($i, $finger->[$i]->get_child($i));
      $finger->[$i]->set_child($i, undef);
    }
    $self->{last_node} = $finger->[0];
    return $tail;
  }
}

sub append {
  my ($head, $tail) = @_;

  my $left  = $head->_last_node;
  my $right = $tail->_first_node;

  # Note: the behavior is not different when one of the skip lists is
  # empty. In particular, the tail is not cleared, although the user
  # should assume that it is.

  unless ($head->size) { return $tail; }
  unless ($tail->size) { return $head; }

  if ( (($left->key_cmp($right->key)<0) && ($right->key_cmp($left->key)>0)) ||
       ($head->allow_duplicates && ($left->key_cmp($right->key)==0)) ) {

    # We need to build an update vector for the last node on each
    # level. There's really no other way to do this but to use a
    # specialized search.

    my $finger = [ ($head->list) x $head->level ];
    {
      my $i = $head->level-1;
      my $node = $head->list->get_child($i);
      if ($node) {
	do {
	  while (my $fwd = $node->get_child($i)) {
	    $node = $fwd;
	  }
	  $finger->[$i] = $node;
	} while (--$i >= 0);
      }
    }

    for(my $i=0; $i<$head->level; $i++) {
      $finger->[$i]->set_child($i, $tail->list->get_child($i));
    }

    # If the tail has a greater height than the head, we increase it

    if ($tail->level > $head->level) {
      for (my $i=$head->level; $i<$tail->level; $i++) {
	$head->list->set_child($i, $tail->list->get_child($i));
      }
      $head->{level} = $tail->level;
    }
    $head->{size} += $tail->size;
    $tail->clear;

    return $head;
  }
  else {
    croak "Cannot append: first key of tail is less than last key of head";
  }
}

=begin internal

=item _debug

  $list->_debug;

This is an internal routine for dumping the contents and structure of
a skiplist to STDERR.  It is intended for debugging.

=end internal

=cut

sub _debug {
  my ($fh) = @args;

  $fh = \*STDERR, unless ($fh);

  my $node   = $self->list;

  while ($node) {
    if ($node->isa("Algorithm::SkipList::Header")) {
      print $fh "undef=undef (header) ", $node, "\n";
    }
    else {
      print $fh
	$node->key||'undef', "=", $node->value||'undef'," ", $node,"\n";
    }

    for(my $i=0; $i<$node->child_count; $i++) {
      print $fh " ", $i," ", $node->get_child($i)
	|| 'undef', "\n";
    }
    print $fh "\n";

    $node = $node->get_child(0);
  }
}

1;

__END__

=back

=cut




__END__

#### Old version here - delete!

sub find_duplicates {
  my ($self, $key, $finger) = @_;

  my ($node, $update_ref, $cmp) = $self->_search_with_finger($key, $finger);

  if ($cmp == 0) {
    my @values = ( $node->value );

    while ( ($node->header()->[0]) &&
	    ($node->header()->[0]->key_cmp($key) == 0) ) {
      $node = $node->header()->[0];
      push @values, $node->value;
    }

    return @values;
  }
  else {
    return;
  }
}


sub _greatest_node {
  my ($self) = @_;

  my $list = $self->{LIST_END} || $self->list;

  my $level = $self->level-1;
  do {
    while (my $next = $list->get_child($level)) {
      $list = $next;
    }
  } while (--$level >=0);

  $self->{LIST_END} = $list;
}


sub next {
  my $self = shift;

  my ($key, $finger, $value) = $self->next_key;

  if (defined $key) {
    return ($key, $value)
  } else {
    return;
  }
}

sub prev_key {
  my $self = shift;
  $self->_error;
  ## croak "unimplemented method";
}

sub prev {
  my $self = shift;
  $self->_error;
  ## croak "unimplemented method";
}

sub _search_nodes {
  my ($self, $low, $finger_low, $high ) = @_;
  my @nodes = ();

  $low  = $self->_first_node()->key(),  unless (defined $low);
  $high = $self->_greatest_node->key(), unless (defined $high);

  if ($self->_node_class->new($low,undef,[])->key_cmp($high) > 0) {
    carp "low > high";
    return;
  }

  my ($node, $finger, $cmp) = $self->_search($low, $finger_low);
  if ($cmp) {
    return;
  } else {
    while ((defined $node) && ($node->key_cmp($high) <= 0)) {
      push @nodes, $node;
      $node = $node->header()->[0];
    }
  }
  return @nodes;
}

sub keys {
  my ($self, $low, $finger_low, $high) = @_;

  my @keys = map { $_->key }
    $self->_search_nodes($low, $finger_low, $high);
  return @keys;
}

sub values {
  my ($self, $low, $finger_low, $high) = @_;

  my @values = map { $_->value }
    $self->_search_nodes($low, $finger_low, $high);
  return @values;
}

sub truncate {
  my $self = shift;

  my ($key, $finger) = @_;

  if (defined $key) {
    my ($node, $finger, $cmp) = $self->_search_with_finger( $key, $finger );
    if ($cmp == 0) {

      # This is the most braindead way to find the index of a node. We
      # could come up with more sophisticated way by saving the number
      # of "skips" in the forward pointers when we add nodes, but that
      # will significantly affect the speed.

      my $size = 1 + $self->index_by_key( $key );
#       {
# 	my $aux  = $self->list;
# 	while ($aux != $node) {
# 	  $size++;
# 	  $aux = $aux->header()->[0];
# 	}
#       }

      my $list = __PACKAGE__->new(
        max_level  => $self->max_level,
        p          => $self->p,
        node_class => $self->_node_class,
      );

      my $level   = $self->level;
      my $old_hdr = $self->list->header;
      my $new_hdr = $list->list->header;

      for (my $i=0; $i<$level; $i++) {

	if ($finger->[$i]) {
	  if ($finger->[$i] == $node) {
	    $new_hdr->[$i] = $finger->[$i];
	    $finger->[$i]  = undef;
	  }
	  else {
	    $new_hdr->[$i] = $finger->[$i]->header()->[$i];
	    $finger->[$i]->header()->[$i]  = undef;
	  }
	}
	elsif ($old_hdr->[$i]) {

	  if ($old_hdr->[$i] == $node) {
	    $new_hdr->[$i] = $old_hdr->[$i];
	    $old_hdr->[$i]  = undef;
	  }
	  else {
	    carp "unexpected situation",
	      if (warnings::enabled);
	    # If _search_with_finger does not stop on !$cmp but
	    # continues to remaining levels, then we should not
	    # need to worry about this.
	  }
	}


      }

      $list->{SIZE} = $self->size - $size;
      $self->{SIZE} = $size;

      $list->{LIST_END} = undef;
      $self->{LIST_END} = undef;

      $self->_adjust_level_threshold;
      $list->_adjust_level_threshold;

      return $list;
    }
    else {
    carp "key not found", if (warnings::enabled);
      return;
    }
  }
  else {
    croak "no key specified";
    return;
  }

}

sub merge {
  my $list1 = shift;

  my $list2 = shift;

  my ($finger1, $finger2);
  my ($node1) = $list1->_first_node;
  my ($node2) = $list2->_first_node;

  while ($node1 || $node2) {

    my $cmp = ($node1) ? (
      ($node2) ? $node1->key_cmp( $node2->key ) : 1 ) : -1;

    if ($cmp < 0) {                     # key1 < key2
      if ($node1) {
	$finger1 = $list1->insert( $node1->key, $node1->value, );
	$node1 = $node1->header()->[0];
      } else {
	$finger1 = $list1->insert( $node2->key, $node2->value, );
	$node2 = $node2->header()->[0];
      }
    } elsif ($cmp > 0) {                # key1 > key2
      if ($node2) {
	$finger1 = $list1->insert( $node2->key, $node2->value, );
	$node2 = $node2->header()->[0];
      } else {
	$finger1 = $list1->insert( $node1->key, $node1->value, );
	$node1 = $node1->header()->[0];
      }
    } else {                            # key1 = key2
      $node1 = $node1->header()->[0],
	if $node1;
      $node2 = $node2->header()->[0],
	if $node2;
    }
  }
}

sub append {
  my $list1 = shift;

  my $list2 = shift;

  unless (defined $list2) { return; }

  my $node = $list1->_greatest_node;
  if ($node) {

    my ($next) = $list2->_first_node;

    if ($list1->level > $list2->level) {

      if ($list1->level < $list1->max_level) {

	my $i = $list1->level;
	while (!defined $list1->list->get_child($i)) { $i--; }
	$list1->list->set_child($i+1, $next);
      } else {
	my $i = $list1->level-1;
	my $x = $list1->list->get_child($i);
	while (my $n = $x->get_child($i)) {
	  $x = $n;
	}
	$x->set_child($i, $next);
      }
      $node->set_child(0, $next);

    } else {
      for (my $i=0; $i<$node->level; $i++) {
	$node->header()->[$i] = $next;
      }
      for (my $i=$list1->level; $i<$list2->level; $i++) {
	$list1->list->set_child($i, $next);
      }
    }

    $list1->{SIZE}    += $list2->size;
    $list1->{LIST_END} = $list2->{LIST_END};
  } else {
    $list1->{LIST}     = $list2->list;
    $list1->{SIZE}     = $list2->size;
    $list1->{LIST_END} = $list2->{LIST_END};
  }
  $list1->_adjust_level_threshold;
}

sub _node_by_index {
  my ($self, $index) = @_;

  # Bug: for some reason, change $[ does not affect this module.

#   if ($index >= $[) {
#     $index -= $[;
#   }

  if ($index < 0) {
    $index += $self->size;
  }

  if (($index < 0) || ($index >= $self->size)) {
    carp "index out of range", if (warnings::enabled);
    return;
  }


  my ($node, $last_index) = @{ $self->{LASTKEY} || [ ] };

  if ((defined $last_index)  && ($last_index <= $index)) {
    ($last_index, $index) = ($index, $index - $last_index);
  }
  else {
    $last_index = $index;
    $node = undef;
  }

  $node ||= $self->_first_node;

  unless ($node) {
    return;
  }

  while ($node && $index--) {
    $node = $node->header()->[0];
  }

  $self->last_key( $node, $last_index );
  return $node;
}

sub key_by_index {
  my ($self, $index) = @_;

  my $node = $self->_node_by_index($index);
  if ($node) {
    return $node->key;
  } else {
    return;
  }
}

sub value_by_index {
  my ($self, $index) = @_;

  my $node = $self->_node_by_index($index);
  if ($node) {
    return $node->value;
  } else {
    return;
  }
}

sub index_by_key {
  my ($self, $key) = @_;

  my $node  = $self->_first_node;
  my $index = 0;
  while ($node && ($node->key_cmp($key) < 0)) {
    $node = $node->header()->[0];
    $index++;
  }

  if ($node->key_cmp($key) == 0) {
    $self->last_key( $node, $index );
    return $index;
  } else {
    return;
  }
}


sub _debug {

  my $self = shift;

  my $list   = $self->list;

  while ($list) {
    print STDERR
      $list->key||'undef', "=", $list->value||'undef'," ", $list,"\n";

    for(my $i=0; $i<$list->level; $i++) {
      print STDERR " ", $i," ", $list->header()->[$i]
	|| 'undef', "\n";
    }
#     print STDERR " P ", $list->prev() || 'undef', "\n";
    print STDERR "\n";

    $list = $list->header()->[0];
  }

}

=head2 Methods

A detailed description of the methods used is below.

=over

=item new

  $list = new Algorithm::SkipList();

Creates a new skip list.

If you need to use a different L<node class|/"Node Methods"> for using
customized L<comparison|/"key_cmp"> routines, you will need to specify a
different class:

  $list = new Algorithm::SkipList( node_class => 'MyNodeClass' );

See the L</"Customizing the Node Class"> section below.

Specialized internal parameters may be configured:

  $list = new Algorithm::SkipList( max_level => 32 );

Defines a different maximum list level.

The initial list (see the L</"list"> method) will be a
L<random|/"_new_node_level"> number of levels, and will increase over
time if inserted nodes have higher levels, up until L</max_level>
levels.  See L</max_level> for more information on this parameter.

You can also control the probability used to determine level sizes for
each node by setting the L<P|/"p"> and k values:

  $list = new Algorithm::SkipList( p => 0.25, k => 1 );

See  L<P|/p> for more information on this parameter.

You can enable duplicate keys by using the following:

  $list = new Algorithm::SkipList( duplicates => 1 );

This is an experimental feature. See the L</KNOWN ISSUES> section
below.

=item insert

  $list->insert( $key, $value );

Inserts a new node into the list.

You may also use a L<search finger|/"About Search Fingers"> with insert,
provided that the finger is for a key that occurs earlier in the list:

  $list->insert( $key, $value, $finger );

Using fingers for inserts is I<not> recommended since there is a risk
of producing corrupted lists.

=item exists

  if ($list->exists( $key )) { ... }

Returns true if there exists a node associated with the key, false
otherwise.

This may also be used with  L<search fingers|/"About Search Fingers">:

  if ($list->exists( $key, $finger )) { ... }

=item find_with_finger

  $value = $list->find_with_finger( $key );

Searches for the node associated with the key, and returns the value. If
the key cannot be found, returns C<undef>.

L<Search fingers|/"About Search Fingers"> may also be used:

  $value = $list->find_with_finger( $key, $finger );

To obtain the search finger for a key, call L</find_with_finger> in a
list context:

  ($value, $finger) = $list->find_with_finger( $key );

=item find

  $value = $list->find( $key );

  $value = $list->find( $key, $finger );

Searches for the node associated with the key, and returns the value. If
the key cannot be found, returns C<undef>.

This method is slightly faster than L</find_with_finger> since it does
not return a search finger when called in list context.

If you are searching for duplicate keys, you must use
L</find_with_finger> or L</find_duplicates>.

=item find_duplicates

  @values = $list->find_duplicates( $key );

  @values = $list->find_duplicates( $key, $finger );

Returns an array of values from the list.

This is an autoloading method.

=item search

Search is an alias to L</find>.

=item first_key

  $key = $list->first_key;

Returns the first key in the list.

If called in a list context, will return a
L<search finger|/"About Search Fingers">:

  ($key, $finger) = $list->first_key;

A call to L</first_key> implicitly calls L</reset>.

=item next_key

  $key = $list->next_key( $last_key );

Returns the key following the previous key.  List nodes are always
maintained in sorted order.

Search fingers may also be used to improve performance:

  $key = $list->next_key( $last_key, $finger );

If called in a list context, will return a
L<search finger|/"About Search Fingers">:

  ($key, $finger) = $list->next_key( $last_key, $finger );

If no arguments are called,

  $key = $list->next_key;

then the value of L</last_key> is assumed:

  $key = $list->next_key( $list->last_key );

Note: calls to L</delete> will L</reset> the last key.

=item next

  ($key, $value) = $list->next( $last_key, $finger );

Returns the next key-value pair.

C<$last_key> and C<$finger> are optional.

This is an autoloading method.

=item last_key

  $key = $list->last_key;

  ($key, $finger, $value) = $list->last_key;

Returns the last key or the last key and finger returned by a call to
L</first_key>, L</next_key>, L</index_by_key>, L</key_by_index> or
L</value_by_index>.  This is not the greatest key.

Deletions and inserts may invalidate the L</last_key> value.
(Deletions will actually L</reset> the value.)

Values for L</last_key> can also be set by including parameters,
however this feature is meant for I<internal use only>:

  $list->last_key( $node );

Note that this is a change form versions prior to 0.71.

=item reset

  $list->reset;

Resets the L</last_key> to C<undef>.

=item index_by_key

  $index = $list->index_by_key( $key );

Returns the 0-based index of the key (as if the list were an array).
I<This is not an efficient method of access.>

This is an autoloading method.

=item key_by_index

  $key = $list->key_by_index( $index );

Returns the key associated with an index (as if the list were an
array).  Negative indices return the key from the end.  I<This is not
an efficient method of access.>

This is an autoloading method.

=item value_by_index

  $value = $list->value_by_index( $index );

Returns the value associated with an index (as if the list were an
array).  Negative indices return the value from the end.  I<This is not
an efficient method of access.>

This is an autoloading method.

=item delete

  $value = $list->delete( $key );

Deletes the node associated with the key, and returns the value.  If
the key cannot be found, returns C<undef>.

L<Search fingers|/"About Search Fingers"> may also be used:

  $value = $list->delete( $key, $finger );

Calling L</delete> in a list context I<will not> return a search
finger.

=item clear

  $list->clear;

Erases existing nodes and resets the list.

=item size

  $size = $list->size;

Returns the number of nodes in the list.

=item copy

  $list2 = $list1->copy;

Makes a copy of a list.  The L</"p">, L</"max_level"> and
L<node class|/"_node_class"> are copied, although the exact structure of node
levels is not copied.

  $list2 = $list1->copy( $key_from, $finger, $key_to );

Copy the list between C<$key_from> and C<$key_to> (inclusive).  If
C<$finger> is defined, it will be used as a search finger to find
C<$key_from>.  If C<$key_to> is not specified, then it will be assumed
to be the end of the list.

If C<$key_from> does not exist, C<undef> will be returned.

This is an autoloading method.

=item merge

  $list1->merge( $list2 );

Merges two lists.  If both lists share the same key, then the valie
from C<$list1> will be used.

Both lists should have the same L<node class|/"_node_class">.

This is an autoloading method.

=item append

  $list1->append( $list2 );

Appends (concatenates) C<$list2> after C<$list1>.  The last key of
C<$list1> must be less than the first key of C<$list2>.

Both lists should have the same L<node class|/"_node_class">.

This method affects both lists.  The L</"header"> of the last node of
C<$list1> points to the first node of C<$list2>, so changes to one
list may affect the other list.

If you do not want this entanglement, use the L</merge> or L</copy>
methods instead:

  $list1->merge( $list2 );

or

  $list1->append( $list2->copy );

This is an autoloading method.

=item truncate

  $list2 = $list1->truncate( $key );

Truncates C<$list1> and returns C<$list2> starting at C<$key>.
Returns C<undef> is the key does not exist.

It is asusmed that the key is not the first key in C<$list1>.

This is an autoloading method.

=item least

  ($key, $value) = $list->least;

Returns the least key and value in the list, or C<undef> if the list
is empty.

This is an autoloading method.

=item greatest

  ($key, $value) = $list->greatest;

Returns the greatest key and value in the list, or C<undef> if the list
is empty.

This is an autoloading method.

=item keys

  @keys = $list->keys;

Returns a list of keys (in sorted order).

  @keys = $list->keys( $low, $high);

Returns a list of keys between C<$low> and C<$high>, inclusive. (This
is only available in versions 1.02 and later.)

This is an autoloading method.

=item values

  @values = $list->values;

Returns a list of values (corresponding to the keys returned by the
L</keys> method).

This is an autoloading method.

=back

=head2 Internal Methods

Internal methods are documented below. These are intended for
developer use only.  These may change in future versions.

=over

=item _search_with_finger

  ($node, $finger, $cmp) = $list->_search_with_finger( $key );

Searches for the node with a key.  If the key is found, that node is
returned along with a L</"header">.  If the key is not found, the previous
node from where the node would be if it existed is returned.

Note that the value of C<$cmp>

  $cmp = $node->key_cmp( $key )

is returned because it is already determined by L</_search>.

Search fingers may also be specified:

  ($node, $finger, $cmp) = $list->_search_with_finger( $key, $finger );

Note that the L</"header"> is actually a
L<search finger|/"About Search Fingers">.

=item _search

  ($node, $finger, $cmp) = $list->_search( $key, [$finger] );

Same as L</_search_with_finger>, only that a search finger is not returned.
(Actually, an initial "dummy" finger is returned.)

This is useful for searches where a finger is not needed.  The speed
of searching is improved.

=item k

  $k = $list->k;

Returns the I<k> value.

  $list->k( $k );

Sets the I<k> value.

Higher values will on the average have less pointers per node, but
take longer for searches.  See the section on the L<P|/p> value.

=item p

  $plevel = $list->p;

Returns the I<P> value.

  $list->p( $plevel );

Changes the value of I<P>.  Lower values will on the average have less
pointers per node, but will take longer for searches.

The probability that a particular node will have a forward pointer at
level I<i> is: I<p**(i+k-1)>.

For more information, consult the references below in the
L</"SEE ALSO"> section.

=item max_level

  $max = $list->max_level;

Returns the maximum level that L</_new_node_level> can generate.

  eval {
    $list->max_level( $level );
  };

Changes the maximum level.  If level is less than L</MIN_LEVEL>, or
greater than L</MAX_LEVEL> or the current list L</level>, this will fail
(hence the need for setting it in an C<eval> block).

The value defaults to L</MAX_LEVEL>, which is 32.  There is usually no
need to change this value, since the maximum level that a new node
will have will not be greater than it actually needs, up until 2^32
nodes.  (The current version of this module is not designed to handle
lists larger than 2^32 nodes.)

Decreasing the maximum level to less than is needed will likely
degrade performance.

=item _new_node_level

  $level = $list->_new_node_level;

This is an internal function for generating a random level for new nodes.

Levels are determined by the L<P|/"p"> value.  The probability that a
node will have 1 level is I<P>; the probability that a node will have
2 levels is I<P^2>; the probability that a node will have 3 levels is
I<P^3>, et cetera.

The value will never be greater than L</max_level>.

Note: in earlier versions it was called C<_random_level>.

=item list

  $node = $list->list;

Returns the initial node in the list, which is a
L<Tree::Node>.

The key and value for this node are undefined.

=item _first_node

  $node = $list->_first_node;

Returns the first node with a key (the second node) in a list.  This
is used by the L</first_key>, L</least>, L</append> and L</merge>
methods.

=item _greatest_node

  $node = $list->_greatest_node;

Returns the last node in the list.  This is used by the L</append> and
L</greatest> methods.

=item _node_class

  $node_class_name = $list->_node_class;

Returns the name of the node class used.  By default this is the
L<Tree::Node>.

=item _build_distribution

  $list->_build_distribution;

Rebuilds the probability distribution array C<{P_LEVELS}> upon calls
to L</_set_p> and L</_set_k>.

=item _set_node_class

=item _set_max_level

=item _set_p

=item _set_k

These methods are used during initialization of the object.

=item _debug

  $list->_debug;

Used for debugging skip lists by developer.  The output of this
function is subject to change.

=back

=head1 SPECIAL FEATURES

=head2 Tied Hashes

Hashes can be tied to C<Algorithm::SkipList> objects:

  tie %hash, 'Algorithm::SkipList';
  $hash{'foo'} = 'bar';

  $list = tied %hash;
  print $list->find('foo'); # returns bar

See the L<perltie> manpage for more information.

=head2 About Search Fingers

A side effect of the search function is that it returns a I<finger> to
where the key is or should be in the list.

We can use this finger for future searches if the key that we are
searching for occurs I<after> the key that produced the finger. For
example,

  ($value, $finger) = $list->find('Turing');

If we are searching for a key that occurs after 'Turing' in the above
example, then we can use this finger:

  $value = $list->find('VonNeuman', $finger);

If we use this finger to search for a key that occurs before 'Turing'
however, it may fail:

  $value = $list->find('Goedel', $finger); # this may not work

Therefore, use search fingers with caution.

Search fingers are specific to particular instances of a skip list.
The following should not work:

  ($value1, $finger) = $list1->find('bar');
  $value2            = $list2->find('foo', $finger);

One useful feature of fingers is with enumerating all keys using the
L</first_key> and L</next_key> methods:

  ($key, $finger) = $list->first_key;

  while (defined $key) {
    ...
    ($key, $finger) = $list->next_key($key, $finger);
  }

See also the L</keys> method for generating a list of keys.

=head2 Similarities to Tree Classes

This module intentionally has a subset of the interface in the
L<Tree::Base> and other tree-type data structure modules, since skip
lists can be used in place of trees.

Because pointers only point forward, there is no C<prev> method to
point to the previous key.

Some of these methods (least, greatest) are autoloading because they
are not commonly used.

One thing that differentiates this module from other modules is the
flexibility in defining a custom node class.

=for readme continue

=head1 KNOWN ISSUES

=over

=item Developer Release

This is a developer release, with many changes to improve performance.
Some of these changes may cause incompatabilities.  See the F<Changes>
file.

L<Algorithm::SkipList::PurePerl> is not included with this release, and
code which relies on it may fail.

The documentation has largely been copied from the 1.02 release, and
may not accurately reflect changes in this release.

=item Undefined Values

Certain methods such as L</find> and L</delete> will return the the
value associated with a key, or C<undef> if the key does not exist.
However, if the value is C<undef>, then these functions will appear to
claim that the key cannot be found.

In such circumstances, use the L</exists> method to test for the
existence of a key.

=item Duplicate Keys

Duplicate keys are an experimental feature in this module, since most
methods have been designed for unique keys only.

Access to duplicate keys is akin to a stack.  When a duplicate key is
added, it is always inserted I<before> matching keys.  In searches, to
find duplicate keys one must use L</find_with_finger> or the
L</find_duplicates> method.

The L</copy> method will reverse the order of duplicates.

The behavior of the L</merge> and L</append> methods is not defined
for duplicates.

=item Non-Determinism

Skip lists are non-deterministic.  Because of this, bugs in programs
that use this module may be subtle and difficult to reproduce without
many repeated attempts.  This is especially true if there are bugs in
a L<custom node|/"Customizing the Node Class">.

=back

Additional issues may be listed on the CPAN Request Tracker at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Algorithm-SkipList> or
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=List-SkipList>.

=head1 AUTHOR

Robert Rothenberg <rrwo at cpan.org>

=head2 Acknowledgements

Carl Shapiro for introduction to skip lists.

=head2 Suggestions and Bug Reporting

Feedback is always welcome.  Please use the CPAN Request Tracker at
L<http://rt.cpan.org> to submit bug reports.

=head1 LICENSE

Copyright (c) 2003-2005, 2008-2010 Robert Rothenberg. All rights
reserved.  This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

See the article by William Pugh, "A Skip List Cookbook" (1989), or
similar ones by the author at L<http://www.cs.umd.edu/~pugh/> which
discuss skip lists.

Another article worth reading is by Bruce Schneier, "Skip Lists:
They're easy to implement and they work",
L<Doctor Dobbs Journal|http://www.ddj.com>, January 1994.

L<Tie::Hash::Sorted> maintains a hash where keys are sorted.  In many
cases this is faster, uses less memory (because of the way Perl5
manages memory), and may be more appropriate for some uses.

If you need a keyed list that preserves the order of insertion rather
than sorting keys, see L<List::Indexed> or L<Tie::IxHash>.

=cut
