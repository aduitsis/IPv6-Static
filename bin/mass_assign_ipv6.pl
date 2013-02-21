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


IPv6::Static::map_over_entries( $dbh, sub {
	p $_; #FUUUUUUU this will not work if it's the last statement
	1;
} ) ;

#my $sth = $dbh->prepare('select * from ipv6_static where group_id=(select id from groups where name=?)') or confess $dbh->errstr;
#$sth->execute( $group_name ) or confess $sth->errstr;
#
#while( my $row = $sth->fetchrow_hashref ) {
#	#p $row;
#	my $r =  Pools::get_prefixes( $dbh , $row->{username} ) ;
#	say join("\t",($row->{username},$r->{framed},$r->{delegated}));
#	if( $write ) {
#		my $sth2 = $dbh->prepare('replace into ipv6_units set dn=?,framed=?,delegated=?') or do { die DBI::errstr };
#		$sth2->execute( $row->{username} , $r->{framed} , $r->{delegated} );
#	}
#}
