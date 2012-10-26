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

use lib $Bin.'../lib';
use lib $Bin.'/../IPv6-Static/lib';
use lib $Bin.'/../../ip6prefix/lib';
use IPv6::Static;
use IPv6::Address;
use Pools;

use Heuristics;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

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

my $username = shift // die 'missing username';
        
defined ( my $dbh = DBI->connect ("DBI:mysql:database=$db_name;host=$db_host", $db_username, $db_password ) ) or do { die DBI::errstr };

my $r =  Pools::get_prefixes( $dbh , $username ) ;
say $r->{framed};
say $r->{delegated};

