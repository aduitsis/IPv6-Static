#!/usr/bin/perl -w

use warnings;
use strict;
use Carp;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use IPv6::Static;
use Time::HiRes qw(time);
use List::Util qw(sum);
use Data::Dumper;
use Term::ReadKey;
use Term::ReadLine;
use Getopt::Long;

my $db_host = 'localhost';
my $db_username;
my $db_password;
my $db_name='test';

my $group = 'some_group';

my $iterations = 1;

my $users = 100000;

my $DEBUG = 0;

GetOptions('d' => \$DEBUG , 'group=s'=>\$group,'i=i'=>\$iterations,'host|h=s' => \$db_host , 'user|u=s' => \$db_username, 'password|p:s' => \$db_password , 'db=s' => \$db_name, 'users=i' => \$users );

if( defined( $db_password) && ( $db_password eq '' ) ) {
        ReadMode 2;
        my $term = Term::ReadLine->new('password prompt');
        my $prompt = 'password:';
        $db_password = $term->readline($prompt);
        ReadMode 0;
}


defined ( my $dbh = DBI->connect ("DBI:mysql:database=$db_name;host=$db_host", $db_username, $db_password ) ) or do { die DBI::errstr };


my @svc_time;

for(1..$iterations) {
	my $user = 'user'.int(rand($users));
	print $user."\n";
	eval {
		my $t0 = time;
		my $n = IPv6::Static::handle_user_login($dbh,$group,$user) ;
		my $t1 = time;
		printf STDERR "%.4f seconds\n", $t1-$t0;
		push @svc_time,($t1-$t0);

		#user logs out - put this in an eval block separately before going into production
		IPv6::Static::handle_user_logout($dbh,$group,$user);
		print $n->{record}->{address}."\n";
		print $n->{logger}->to_string."\n";
	};
	if($@) {
		print "failed to handle user. Reason: $@ \n";
		exit;
	}
	
	#just a precaution, normally this should noop
	$dbh->do('UNLOCK TABLES') or die $dbh->errstr;
}

print Dumper(\%IPv6::Static::stats)."\n";
	

print scalar(sum(@svc_time)/ @svc_time)."\n";
