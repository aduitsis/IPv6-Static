#!/usr/bin/perl -w

use v5.14;

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


my $units_file = shift // die 'missing units filename';
my $accounts_file = shift // die 'missing accounts filename';
my $target_file = shift // die 'missing target filename';

my $units = retrieve $units_file;
my $accounts = retrieve $accounts_file;


my %locality;

for my $account ( keys %{$accounts} ) {
	for my $locality ( @{ $accounts->{$account}->{l} } ) {
		push @{ $locality{ $locality } } , { account => $account , uid => $accounts->{$account}->{uid}->[0] } ; 
	}
}

for my $unit ( keys %{$units} ) {
	if( exists( $locality{ $unit } ) ) {
		$units->{$unit}->{accounts} = $locality{ $unit } ; 
	}
	else {
		print STDERR "Warning: unit $unit does not have a corresponding account \n";
	}
}

nstore $units,$target_file;

