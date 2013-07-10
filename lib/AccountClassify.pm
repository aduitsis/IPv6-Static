package AccountClassify;

use v5.14;

use utf8;
use locale;
use open qw(:std :utf8);
use charnames qw(:full :short);
use Encode qw(decode);
use warnings qw(FATAL utf8);
use strict;
use Data::Printer;
use FindBin qw($Bin);
use lib $Bin.'/../lib/';
use LDAPHelper;
use Storable qw(nstore retrieve);
use Getopt::Long;
use Heuristics;
use DBHelper;
use Pod::Usage;
use IPv6::Static;
use Pools;
use POSIX;
use Carp;
use Term::ANSIColor qw(:constants);


sub weed {
	my $accounts = shift // confess 'incorrect call';
	my @ppp_accounts = grep { 
		(	
			exists( $_->{ attributes }->{ umdobject } ) 
			&& 
			( 
				( lc($_->{ attributes }->{ umdobject }->[0])  eq 'router' )
				||
				( lc($_->{ attributes }->{ umdobject }->[0])  eq 'adslaccount' ) 
			)
		)
		||
		(
			exists( $_->{ attributes }->{ physicaldeliveryofficename } )
			&&
			grep { $_ =~ /ΕΠΙΣΗΜΟΣ ΛΟΓΑΡΙΑΣΜΟΣ/i } @{ $_->{ attributes }->{ physicaldeliveryofficename } }
		)
	} @{ $accounts }; 
	say STDERR BOLD BLACK "\tfound ".scalar(@ppp_accounts)." router or official accounts";
	return @ppp_accounts;
	
	### if( @router_accounts == 1 ) {
	### 	return @router_accounts;
	### }
	### elsif( @router_accounts == 0 ) {
	### 	my @official_accounts = grep { 
	### 		exists( $_->{ attributes }->{ physicaldeliveryofficename } ) 
	### 		&& 
	### 		grep { $_ =~ /ΕΠΙΣΗΜΟΣ ΛΟΓΑΡΙΑΣΜΟΣ/i } @{ $_->{ attributes }->{ physicaldeliveryofficename } };
	### 	} @{ $accounts };
	### 	say STDERR BOLD BLACK "\tfound ".scalar(@official_accounts)." official accounts";
	### 	if( @official_accounts == 1 ) {
	### 		return @official_accounts
	### 	} 
	### 	elsif( @official_accounts == 0 ) {
	### 		return;	
	### 	}
	### 	else {
	### 		return @official_accounts
	### 	}
	### }
	### else {
	### 	return @router_accounts;
	### }
	
}

1;


