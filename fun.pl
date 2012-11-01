#!/usr/bin/perl -w
@arr1 = 1..5;
fun(\@arr1);

sub fun {
	($ref_arr1) = @_;
	print $#{$ref_arr1};
}