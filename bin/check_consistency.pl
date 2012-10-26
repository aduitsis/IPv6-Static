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

my $fix = 0;
my $group = '';
my $max_addr;

my $db_host = 'localhost';
my $db_username;
my $db_password;
my $db_name='test';

my $DEBUG = 0;

GetOptions('d' => \$DEBUG , 'fix'=>\$fix,'group=s'=>\$group,'max=i'=>\$max_addr,'host|h=s' => \$db_host , 'user|u=s' => \$db_username, 'password|p:s' => \$db_password , 'db=s' => \$db_name);


if( defined( $db_password) && ( $db_password eq '' ) ) {
	ReadMode 2;
	my $term = Term::ReadLine->new('password prompt');
	my $prompt = 'password:';
	$db_password = $term->readline($prompt);
	ReadMode 0;
}

	
defined ( my $dbh = DBI->connect ("DBI:mysql:database=$db_name;host=$db_host", $db_username, $db_password ) ) or do { die DBI::errstr };

my $group_ref = IPv6::Static::get_group($dbh,$group);
my $group_id = $group_ref->{id};
my $group_limit = $group_ref->{limit};

$max_addr = (defined($max_addr))? $max_addr : $group_limit ;


for(0..($max_addr-1)) {
	my $record = IPv6::Static::get_address_record($dbh,$group_id,$_);#careful! this query is not indexed...
	if( ! defined($record) ) {
		print "Missing: Record with address number:\t$_ is missing";
		if ($fix) {
			print "...fixing";
			IPv6::Static::lock_tables($dbh);
			IPv6::Static::create_new_record($dbh,$group_id,'anonymous coward'.$_,$_);
			IPv6::Static::set_in_use_user($dbh,$group_id,'anonymous coward'.$_,0);
			IPv6::Static::unlock_tables($dbh);
		}
		print "\n";
	}
	else {
		$DEBUG && print STDERR 'OK: Record '.IPv6::Static::record2str($record)."\n";
	}
}

my $sth = $dbh->prepare('SELECT * FROM '.IPv6::Static::Settings::TABLE.' WHERE group_id=? AND address>?') or confess $dbh->errstr;
$sth->execute($group_id,$max_addr) or confess $dbh->errstr;
while( my $record = $sth->fetchrow_hashref ) {
	print "Record found beyond $max_addr limit: ".IPv6::Static::record2str($record)."\n";
}



