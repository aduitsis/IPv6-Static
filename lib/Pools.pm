package Pools;

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
use lib $Bin.'/../../ip6prefix/lib';
use IPv6::Static;
use IPv6::Address;

my $db_host = 'localhost';
my $db_username;
my $db_password;
my $db_name='sch_ipv6';

my $DEBUG = 0;

sub calculate_all_prefixes { 
	my $dbh = shift // die 'incorrect call';
	my %data = @{ IPv6::Static::map_over_entries( $dbh ,
		sub {
			$DEBUG && p $_;
			return $_->{ username } => Pools::get_prefixes( $dbh , $_->{ username } ) ;
		},
	) } ;
	\%data;
}


sub exists_entry {
	my $dbh = shift // die 'incorrect call';
	my $username = shift // die 'incorrect call';
	
	IPv6::Static::get_in_use_record( $dbh , $username ) // return;

	return 1;
}		
	
sub get_prefixes { 
	my $dbh = shift // die 'incorrect call';
	my $username = shift // die 'incorrect call';

	my $record = IPv6::Static::get_in_use_record( $dbh , $username ) // die 'this user does not exist';

	return { 
		framed => calculate_prefix( $dbh, $record->{address}, $record->{group_id}, 'framed' ),
		delegated => calculate_prefix( $dbh, $record->{address}, $record->{group_id}, 'delegated' ), 
	};

}

sub calculate_prefix {
	my $dbh = shift // die 'incorrect call';
	my $address = shift // die 'incorrect call';
	my $group_id = shift // die 'incorrect call';
	my $purpose = shift // die 'incorrect call';

	my $sth = $dbh->prepare('select * from pools where active=1 and group_id=? and purpose=?;') or confess $dbh->errstr;
	$sth->execute($group_id,$purpose) or confess $sth->errstr;

	return IPv6::Address::increment_multiple_prefixes( $address , map { $_->{first_prefix} => $_->{length} } @{ $sth->fetchall_arrayref({}) } );
}	

1;
