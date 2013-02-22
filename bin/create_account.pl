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
use DBHelper;

my $group = '';

my $db_host = 'localhost';
my $db_username;
my $db_password;
my $db_name='sch_ipv6';

my $DEBUG = 0;

db_getoptions('d' => \$DEBUG , 'group=s'=>\$group  );

my $dbh = db_connect;

defined( my $username = shift ) or die 'missing username';

my $ret = eval { 
	IPv6::Static::create_account($dbh,$group,$username) 
};
if($@) {
	print "Cannot create new user $username.\nError was: $@\n";
	exit(1);
} 
else {
	print $ret->{status} . "\nlog follows: \n".$ret->{logger}->to_string;
	exit(0);
}
