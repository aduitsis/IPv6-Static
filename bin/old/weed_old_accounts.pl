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

use Encode qw(decode);

use FindBin qw( $Bin ) ;

use lib $Bin.'/../lib';
use IPv6::Static;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $filename = shift // die 'missing filename';

my $units = retrieve $filename;

my $db_host = 'localhost';
my $db_username;
my $db_password;
my $db_name='sch_ipv6';

my $DEBUG = 0;
my $yes = 0;

GetOptions('y' => \$yes, 'd' => \$DEBUG , 'host|h=s' => \$db_host , 'user|u=s' => \$db_username, 'password|p:s' => \$db_password , 'db=s' => \$db_name);





if( defined( $db_password) && ( $db_password eq '' ) ) {
        ReadMode 2;
        my $term = Term::ReadLine->new('password prompt');
        my $prompt = 'password:';
        $db_password = $term->readline($prompt);
        ReadMode 0;
	print "\n";
}
        
defined ( my $dbh = DBI->connect ("DBI:mysql:database=$db_name;host=$db_host", $db_username, $db_password ,{mysql_enable_utf8 => 1}) ) or do { die DBI::errstr };

my $db_units = IPv6::Static::get_all_usernames( $dbh ) ;

###p $db_units;

for my $unit ( @{$db_units} ) {
	#no longer needed -- my $unit = decode('utf8',$_);
	if( ! exists $units->{ $unit } ) {
		say STDERR "$unit no longer exists";
		if( $yes ) {
			eval { IPv6::Static::delete_account_blind( $dbh , $unit ) } ;
			if( $@ ) {
				say STDERR "Cannot delete $unit. Error was: $@";
			}
			else {
				say STDERR "$unit deleted succesfully";
			}
		}
	}
	
}
