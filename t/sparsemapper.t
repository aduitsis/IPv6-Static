#!/usr/bin/perl

use v5.14;

use warnings;
use strict;
use Test::More qw(no_plan);

BEGIN {
        use Data::Dumper;
        use Carp;
        use_ok('SparseMapper');
}

my @a1 = SparseMapper::analyze_2s_powers( 100 );
my @a2 = SparseMapper::analyze_2s_powers( 0 );
my @a3 = SparseMapper::analyze_2s_powers( 1 );
my @a4 = SparseMapper::analyze_2s_powers( 2 );
my @a5 = SparseMapper::analyze_2s_powers( 4294967295 );
my @a6 = SparseMapper::analyze_2s_powers( 4294967296 );
my @a7 = SparseMapper::analyze_2s_powers( 4294967297 );


is_deeply( \@a1 , [6,5,2],'analyze 100 into powers of two' );
is_deeply( \@a2 , [],'analyze 0 into powers of two' );
is_deeply( \@a3 , [0],'analyze 1 into powers of two' );
is_deeply( \@a4 , [1],'analyze 2 into powers of two' );
is_deeply( \@a5 , [ reverse 0 .. 31 ],'analyze 2^32 into powers of two' );
is_deeply( \@a6 , [],'2^32 + 1 should wraparound to 0' );
is_deeply( \@a7 , [ 0 ],'2^32 +2 should wraparound to 1' );


my $test_map = {
	0 => { 0 => 0 },
	1 => { 0 => 0, 1=>1 },
	2 => { 0 => 0, 2=>1, 1=>2, 3=>3 },
	3 => { 0 => 0, 1=>4, 2=>2, 3=>5 , 4=>1, 5=>6, 6=>3, 7=>7 },
	4 => { 0 => 0, 1=>8, 2=>4, 3=>9 , 4=>2, 5=>10, 6=>5, 7=>11, 8=>1, 9=>12, 10=>6, 11=>13, 12=>3, 13=>14, 14=>7, 15=>15 },
	5 => { 0=>0,1=>16,2=>8,3=>17,4=>4,5=>18,6=>9,7=>19,8=>2,9=>20,10=>10,11=>21,12=>5,13=>22,14=>11,15=>23,16=>1,17=>24,18=>12,19=>25,20=>6,21=>26,22=>13,23=>27,24=>3,25=>28,26=>14,27=>29,28=>7,29=>30,30=>15,31=>31 },
};


is_deeply( SparseMapper::fullmap($_), $test_map->{$_}, 'mapping size 2^'.$_) for (0..5);

for my $i (0..5) {
	for my $j (0..2**$i-1) {
		is( $test_map->{$i}->{$j} , SparseMapper::mapping( $j, $i ), "test_map for 2^$i and $j" );
	}
}


is( SparseMapper::map_number( 0, 1000 ) , 0, 'size 1000, index 0 maps to 0' );
is( SparseMapper::map_number( 100, 1000 ) , 76, 'size 1000, index 100 maps to 76' );
is( SparseMapper::map_number( 511, 1000 ) , 511, 'size 1000, index 511 maps to 511' );
is( SparseMapper::map_number( 512, 1000 ) , 512, 'size 1000, index 512 maps to 512' );
is( SparseMapper::map_number( 513, 1000 ) , 512+128, 'size 1000, index 513 maps to 640' );
is( SparseMapper::map_number( 767, 1000 ) , 512+255, 'size 1000, index 767 maps to 767' );
is( SparseMapper::map_number( 768, 1000 ) , 512+255+1, 'size 1000, index 768 maps to 768' );
is( SparseMapper::map_number( 999, 1000 ) , 999, 'size 1000, index 999 maps to 999' );
