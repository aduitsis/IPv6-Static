#!/usr/local/bin/perl -w

use v5.14;
use strict;
use warnings;
use Data::Printer;

my $DEBUG = 0;

use integer;

sub mapping { 
	my $range = 4;
	my $sum = 0;
	DOWN: 
	for my $i ( reverse 0 .. $range ) {
		my $m = 2**($range-$i+1);
		my $n = $m - $sum;
		my $mod = 2**($i-1) ; 
		$DEBUG && say "testing mod = $mod";
		if ($_[0] % $mod == 0) {
			my $q = $_[0] / $mod;
			$DEBUG && say $_[0].' i='.$i."\tn=".$n."\tsum=".$sum."\tmod=".$mod."\tq=".$q;
			my $decr = ($i == $range )? 0 : ( $_[0] / 2**$i ) + 1 ;
			$DEBUG && say "q is $q";
			$DEBUG && say "decr is $decr";
			$DEBUG && say $sum + $q - $decr;
			return $q + $sum - $decr;
		}
		$sum += $n;
	}
}


#say _mapping(12);

#say _mapping(2);
say $_ . "\t" . mapping($_) for (0..15);
