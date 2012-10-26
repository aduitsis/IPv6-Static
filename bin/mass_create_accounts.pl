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
use Term::ReadKey;
use Term::ReadLine;

use FindBin qw( $Bin ) ;

use lib $Bin.'/../IPv6-Static/lib';
use IPv6::Static;

use Heuristics;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $filename = shift // die 'missing filename';

my $units = retrieve $filename;

my %counter;

#legend:
# 1: πρωτοβάθμια εκπαιδευτική μονάδα
# 2: δευτεροβάθμια εκπαιδευτική
# 3: διοικητική μονάδα 
# 4: τριτοβάθμια (sic) μονάδα
# 5: εκπαιδευτική μονάδα ανεξ βαθμίδας
# 7: unknown


my $cat_map = {
	1 => 'elementary',
	2 => 'highschool',
	3 => 'administrative',
	4 => 'administrative',
	5 => 'administrative',
	7 => 'administrative',
};

my $db_host = 'localhost';
my $db_username;
my $db_password;
my $db_name='sch_ipv6';

my $DEBUG = 0;

GetOptions('d' => \$DEBUG , 'host|h=s' => \$db_host , 'user|u=s' => \$db_username, 'password|p:s' => \$db_password , 'db=s' => \$db_name);


if( defined( $db_password) && ( $db_password eq '' ) ) {
        ReadMode 2;
        my $term = Term::ReadLine->new('password prompt');
        my $prompt = 'password:';
        $db_password = $term->readline($prompt);
        ReadMode 0;
	print "\n";
}
        
defined ( my $dbh = DBI->connect ("DBI:mysql:database=$db_name;host=$db_host", $db_username, $db_password ) ) or do { die DBI::errstr };

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
			say $unit."\t".$cat;
			if( ! exists( $cat_map->{ $cat } ) ) {
				die "Missing mapping for category $cat. Please add it to \%cat_map ";
			}
			my $sth = $dbh->prepare('REPLACE INTO units SET dn=?,group_id=(select id from groups where name=?)') or confess $dbh->errstr;
			$sth->execute($unit,$cat_map->{ $cat }) or confess $sth->errstr;

			
			my $ret = eval { 
				IPv6::Static::create_account($dbh,$cat_map->{ $cat },$unit) 
			};
			if($@) {
				print STDERR 'Cannot create new user '.$unit."\nError was: $@\n";
			} 
			else {
				say STDERR $ret->{status} ;
			}

			if ( exists $units->{$unit}->{accounts} ) {
				#IPv6::Static::create_account( $units->{$unit}->{account}->{uid} , $cat );			
				for my $account ( @{ $units->{$unit}->{accounts} } )  {
					$sth = $dbh->prepare('REPLACE INTO accounts SET uid=?,account_dn=?,dn=?') or confess $dbh->errstr;
					$sth->execute( $account->{ uid } , $account->{ account } , $unit );
				}
			}
			else {
				#nothing to do
			}
			$counter{ $cat } += 1;
		} 
		else {
			die "ERROR: for $unit, category is $cat";
		}
	}
}

p %counter;
