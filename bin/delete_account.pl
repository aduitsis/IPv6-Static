#!/usr/bin/perl -w

use warnings;
use strict;
use Carp;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use IPv6::Static;
use Time::HiRes qw(time);
use List::Util qw(sum);
use Getopt::Long;
use Term::ReadKey;
use Term::ReadLine;

my $group = '';

my $db_host = 'localhost';
my $db_username;
my $db_password;
my $db_name='sch_ipv6';

my $DEBUG = 0;

GetOptions('d' => \$DEBUG , 'host|h=s' => \$db_host , 'user|u=s' => \$db_username, 'password|p:s' => \$db_password , 'db=s' => \$db_name);


defined( my $username = shift ) or die 'missing username';

if( defined( $db_password) && ( $db_password eq '' ) ) {
	ReadMode 2;
	my $term = Term::ReadLine->new('password prompt');
	my $prompt = 'password:';
	$db_password = $term->readline($prompt);
	ReadMode 0;
	print "\n";
}

	
defined ( my $dbh = DBI->connect ("DBI:mysql:database=$db_name;host=$db_host", $db_username, $db_password ) ) or do { die DBI::errstr };

my $ret = eval { IPv6::Static::delete_account_blind($dbh,,$username) } ;
if($@) {
	print "Cannot delete user $username. Error was: $@\n";
	exit(1);
} 
else {
	print $ret->{status} . " - log follows: \n".$ret->{logger}->to_string;
	exit(0);
}



