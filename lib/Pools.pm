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

my $DEBUG = 0;

sub new {
	my $class = shift // die 'incorrect call';
	my $dbh = shift // die 'missing database handle';
	my $self = bless { dbh => $dbh },$class;
	$self->{ pools } = $self->get_pools;
	return $self;
}

sub pool {
	my $self = shift // die 'incorrect call';
	my $pool = shift // die 'pool id missing';
	my $purpose = shift // die 'pool id missing';
	if( ! exists( $self->{ pools }->{$pool} ) ) {
		die "pool $pool purpose $purpose does not exist"
	}
	$self->{ pools }->{$pool}->{$purpose};
}

sub prefixes {
	my $self = shift // die 'incorrect call';
	my $pool = shift // die 'pool id missing';
	my $purpose = shift // die 'pool id missing';
	if( ! exists($self->pool( $pool , $purpose )->{ prefixes }) ) {
		die "pool $pool purpose $purpose has no prefixes"
	}
	$self->pool( $pool , $purpose )->{ prefixes }
}

sub dbh {
	$_[0]->{dbh}
}

sub calculate_all_prefixes { 
	my $self = shift // die 'incorrect call';
	my %data = @{ IPv6::Static::map_over_entries( $self->dbh ,
		sub {
			$DEBUG && p $_;
			return $_->{ username } => $self->get_prefixes(  $_->{ username } ) ;
		},
	) } ;
	\%data;
}


sub exists_entry {
	my $self = shift // die 'incorrect call';
	my $username = shift // die 'incorrect call';
	
	IPv6::Static::get_in_use_record( $self->dbh , $username ) // return;

	return 1;
}		
	
sub get_prefixes { 
	my $self = shift // die 'incorrect call';
	my $username = shift // die 'incorrect call';

	my $record = IPv6::Static::get_in_use_record( $self->dbh , $username ) // die 'this user does not exist';

	return { 
		framed => $self->calculate_prefix( $record->{address}, $record->{group_id}, 'framed' ),
		delegated => $self->calculate_prefix( $record->{address}, $record->{group_id}, 'delegated' ), 
	};

}

sub calculate_prefix {
	my $self = shift // die 'incorrect call';
	my $address = shift // die 'incorrect call';
	my $group_id = shift // die 'incorrect call';
	my $purpose = shift // die 'incorrect call';

	IPv6::Address::increment_multiple_prefixes( $address , %{ $self->prefixes($group_id,$purpose) } );
}	

sub get_pools {
	my $self = shift // die 'incorrect call';
	
	my $result;
	
	$DEBUG && say STDERR 'querying prefix pools';
	my $sth = $self->dbh->prepare('select * from pools where active=1') or confess $self->dbh->errstr;
	$sth->execute or confess $sth->errstr;

	for my $row ( @{ $sth->fetchall_arrayref({}) } ) {
		$result->{ $row->{ group_id } }->{ $row->{purpose} } = {};
		my $pointer = $result->{ $row->{ group_id } }->{ $row->{purpose} };
		$pointer->{ prefixes }->{ $row->{first_prefix} } = $row->{'length'} ; 
		$pointer->{ size } += $row->{'length'};
	}

	$result;
}

1;
