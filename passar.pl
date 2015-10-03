#!/usr/bin/perl
use strict;
use warnings;

# passar.pl
my @foo = qw(one two three);
my @bar = qw (four five six);

sub afun {
	my @arr1 = @{$_[0]};
	my @arr2 = @{$_[1]};
	print join(',',@arr1,@arr2);
	print $main::gv;
}
my $gv = "bar";

afun(\@foo,\@bar);