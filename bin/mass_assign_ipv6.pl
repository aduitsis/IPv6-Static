#!/usr/bin/perl -w

use v5.14; #implies use feature 'unicode_strings'

use utf8;
use locale;
use open qw(:std :utf8);
use charnames qw(:full :short);
use warnings qw(FATAL utf8);
use strict;

use Data::Printer;
use Net::LDAP;
use Getopt::Long;
use Storable qw(nstore retrieve);
use Term::ReadKey;
use Term::ReadLine;

use FindBin qw( $Bin ) ;

use lib $Bin.'/../lib';
use IPv6::Static;
use DBHelper;
use Heuristics;
use Pools;

use LDAPHelper;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

use IO::Handle;
STDERR->autoflush(1);
STDOUT->autoflush(1);

my $DEBUG = 0;
my $help;
my $write;

db_getoptions('d' => \$DEBUG , 'write' => \$write );

#my $group_name = shift // die 'please supply a group name';

my $dbh = db_connect;

my $file = shift // die 'Missing input storable filename';

my $data = retrieve $file;

#p $data;

my %modifications;

my $ldap;
if( $write ) {
	$ldap = LDAPHelper->new;
}

for my $unit ( keys %{$data} ) {
	say STDERR $unit;
	if( Pools::exists_entry( $dbh, $unit ) ) {
		my $r =  Pools::get_prefixes( $dbh , $unit ) ;		
		for my $account ( @{ $data->{$unit}->{accounts} } ) {
			my $account_id = $account->{account} ; 
			say STDERR "\t".$account_id.' '.$r->{framed}.' '.$r->{delegated};
			$modifications{ $account_id } = { radiusFramedIPv6Prefix => $r->{framed}->to_string , radiusDelegatedIPv6Prefix => $r->{delegated}->to_string };
			if( $write ) {
				my @entries = ( $ldap->search( $account_id , 'base', ['uid','radiusFramedIPv6Prefix','radiusDelegatedIPv6Prefix'], 'objectclass=*'  ) );
				for my $entry ( @entries ) {
					$DEBUG && p $entry;
					$DEBUG && p $modifications{ $account_id } ; 
					$ldap->modify( $entry , replace => $modifications{ $account_id } ) ;	
				}
				die 'empty entries for '.$account_id unless @entries;
			}		
		}
	}
	else {
		say STDERR 'User record does NOT exist for '.$unit;
		say STDERR 'Please run mass_create_accounts so that all units will have a valid record';
	}
}


###if( $write ) {
###	my $ldap = LDAPHelper->new;
###	for my $account ( keys %modifications ) {
###		my @entries = ( $ldap->search( $account , 'base', ['uid','radiusFramedIPv6Prefix','radiusDelegatedIPv6Prefix'], 'objectclass=*'  ) );
###		for my $entry ( @entries ) { 
###			p $entry;
###			$ldap->modify( $entry , %{ $modifications{ $account } } ) ; 
###		}
###		die 'empty entries' unless @entries;
###	}
###}

#IPv6::Static::map_over_entries( $dbh, sub {
#	p $_; #FUUUUUUU this will not work if it's the last statement
#	1;
#} ) ;

