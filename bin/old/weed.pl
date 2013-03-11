#!/usr/bin/perl -w

use v5.14; #implies use feature 'unicode_strings'

use utf8;
use locale;
use open qw(:std :utf8);
use charnames qw(:full :short);
use warnings qw(FATAL utf8);
use strict;

use Net::LDAP;
use Data::Printer;
use Data::Dump qw(pp);
use Getopt::Long;
use Storable qw(nstore retrieve);

use lib $Bin.'/../lib/';
use Heuristics;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $filename = shift // die 'missing filename';

my $units = retrieve $filename;

my %counter;

for my $unit ( keys %{$units} ) {
	
	if ( $unit =~ /\P{ASCII}/ ) {
		say STDERR "WARNING: dn: $unit contains non-ASCII characters";
	}
	#say $unit;
	#p $units->{$unit} ; 
	my $cat = eval { 
		Heuristics::classify( $units->{$unit} ) 
	};
	if($@) {
		say STDERR "WARNING: Cannot classify $unit.\nError was: $@";
	} 
	else {
		if( $cat ) {
			print $unit."\t".$cat;
			print "\t";
			if ( exists( $units->{$unit}->{gsnunitcode} ) && @{$units->{$unit}->{gsnunitcode}} ) {
				print $units->{$unit}->{gsnunitcode}->[0];
			}
			else {
				#say STDERR "gsnunitcode missing from $unit";
			}
			print "\t";
			if( exists $units->{$unit}->{accounts} ) {
				print join(',',map { $_->{uid} } @{ $units->{$unit}->{accounts} } );
			}
			print "\t".$units->{$unit}->{description}->[0];
			print "\t";
			if ( exists( $units->{$unit}->{title} ) && @{$units->{$unit}->{title}} ) {
				print $units->{$unit}->{title}->[0];
			}
			else {
				#say STDERR "title missing from $unit";
			}
			print "\n";
			$counter{ $cat } += 1;
			#p $unit;
			#p $units->{$unit}; 
		} 
		else {
			die "ERROR: for $unit, category is $cat";
		}
	}
}

p %counter;
