package SparseMapper;

use v5.14;
use warnings;
use Data::Printer;

my $DEBUG = 0;

use integer;

sub analyze_2s_powers {
	my $e = 0;
	reverse map { my $ret = ($_)? $e : undef ; $e++ ; defined($ret)? $ret : ()   } reverse split '' , ( unpack 'B*', pack 'N',$_[0] ) 
}
	

#sub mapping { 
#	my $number = shift // die 'incorrect call, exponent missing';
#	my $range = shift // die 'incorrect call, range missing';
#	$DEBUG && say "$number map to ".(2**$range);
#	die "number cannot be more than 2^$range-1" if( $number >= 2**$range );
#	return 0 if( $range == 0 ) ; #trivial case, no need to calculate anything
#	my $sum = 0;
#	for my $i ( reverse 0 .. $range ) {
#		my $m = 2**($range-$i+1);
#		my $n = $m - $sum;
#		my $mod = 2**($i-1) ; 
#		$DEBUG && say "i=$i , level $m, items in this level $n, testing mod = $mod";
#		if ($number % $mod == 0) {
#			$DEBUG && say "$mod divides $number";
#			my $q = $number / $mod;
#			$DEBUG && say $number.' i='.$i."\tn=".$n."\tsum=".$sum."\tmod=".$mod."\tq=".$q;
#			my $decr = ($i == $range )? 0 : ( $number / 2**$i ) + 1 ;
#			$DEBUG && say "q is $q";
#			$DEBUG && say "decr is $decr";
#			$DEBUG && say $sum + $q - $decr;
#			return $q + $sum - $decr;
#		}
#		$sum += $n;
#	}
#	die 'internal error, I should not have managed to get here'
#}

sub fullmap { 
	my $range = shift // die 'incorrect call, range missing';
	my $result = {} ; 
	$DEBUG && say (2**$range);
	my $max = 2**$range;
	return { 0 => 0 } if( $range == 0 ) ; #trivial case, no need to calculate anything
	my $previous = 0;
	my $counter;
	for my $i ( reverse 0 .. $range ) {
		my $m = 2**($i);
		#my $n = ( $max / $m ) - $previous;
		$DEBUG && say "level $m";
		for my $j ( 0 .. ( $max / $m )-1 ) {
			my $item = $j * $m;
			$result->{ $item } = $counter++ unless exists $result->{ $item };
		}
		#$previous += $n;
	}
	return $result
}

my %cache;
sub mapping {
	$cache{ $_[1] } = fullmap( $_[1] ) unless exists $cache{ $_[1] } ; 
	$cache{ $_[1] }->{$_[0]};
}
	


sub map_number {
	my $number = shift // die 'missing input number';
	my $maximum = shift // die 'missing input maximum';
	die 'number cannot exceed maximum ' unless ( $maximum > $number );
	my $offset = 0;
	for my $part ( analyze_2s_powers( $maximum ) ) {
		my $range = 2**$part;
		if( $number < $range ) { 
			$DEBUG && say "\tmapping $number to $range";
			return mapping( $number , $part ) + $offset;
		}
		else {
			$offset += $range;
			$number -= $range
		}
	}
	die 'internal error, I should not have managed to get here'
}


1;
