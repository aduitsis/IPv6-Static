package Accounting;

use v5.14;

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
use Pod::Usage;
use autodie qw(open close);

my ( $db_host, $db_username, $db_password, $db_name, $db_table, $db_field, $db_date_field, $interval, $dbh );

my $settings_file = $Bin.'/../etc/accounting.rc' ; 
if( -f $settings_file ) {
	open( my $cfg_file , '<' , $settings_file );
	my $slurp = do { local $/ ; <$cfg_file> };
	close $cfg_file;
	eval $slurp;
	die $@ if($@);
}
else {
	die "settings file $settings_file missing"
}

sub get_usernames {
	$dbh = DBI->connect("DBI:mysql:database=$db_name;host=$db_host", $db_username, $db_password, {mysql_enable_utf8 => 1} ) // do { die DBI::errstr };
	my $sth = $dbh->prepare("select distinct( $db_field ) as username from $db_table where $db_date_field > ( now() - interval $interval )") or confess $dbh->errstr;
        $sth->execute or confess $sth->errstr;

        my @usernames =  map { $_->{ username } } @{ $sth->fetchall_arrayref({}) };
	return \@usernames;
}


1;
