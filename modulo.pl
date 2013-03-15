#!/usr/local/bin/perl -w

use v5.14;
use warnings;
use Data::Printer;

my $DEBUG = 1;

use integer;

sub analyze_2s_powers {
	my $e = 0;
	reverse map { my $ret = ($_)? $e : undef ; $e++ ; defined($ret)? $ret : ()   } reverse split '' , ( unpack 'B*', pack 'N',$_[0] ) 
}
	

sub mapping { 
	my $number = shift // die 'incorrect call, exponent missing';
	my $range = shift // die 'incorrect call, range missing';
	$DEBUG && say "$number map to 2 ** $range";
	die "number cannot be more than 2^$range-1" if( $number >= 2**$range );
	return 0 if( $range == 0 ) ;
	my $sum = 0;
	for my $i ( reverse 0 .. $range ) {
		my $m = 2**($range-$i+1);
		my $n = $m - $sum;
		my $mod = 2**($i-1) ; 
		$DEBUG && say "i=$i , m=$m, n=$n, testing mod = $mod";
		if ($number % $mod == 0) {
			my $q = $number / $mod;
			$DEBUG && say $number.' i='.$i."\tn=".$n."\tsum=".$sum."\tmod=".$mod."\tq=".$q;
			my $decr = ($i == $range )? 0 : ( $number / 2**$i ) + 1 ;
			$DEBUG && say "q is $q";
			$DEBUG && say "decr is $decr";
			$DEBUG && say $sum + $q - $decr;
			return $q + $sum - $decr;
		}
		$sum += $n;
	}
	die 'internal error, I should not have managed to get here'
}


#say _mapping(12);

#say _mapping(2);
# say $_ . "\t" . mapping($_) for (0..15);

#my @a = analyze_2s_powers( 18 );
#p @a; 

sub map_number {
	my $number = shift // die 'missing input number';
	my $maximum = shift // die 'missing input maximum';
	die 'number cannot exceed maximum ' unless ( $maximum > $number );
	my $offset = 0;
	for my $part ( analyze_2s_powers( $maximum ) ) {
		my $range = 2**$part;
		if( $number < $range ) { 
			say "\tmapping $number to $range";
			return mapping( $number , $part )
		}
		else {
			$offset += $range;
			$number -= $range
		}
	}
	die 'internal error, I should not have managed to get here'
}

say $_ . '===>' . map_number($_, 15)."\n\n" for(0..14);
