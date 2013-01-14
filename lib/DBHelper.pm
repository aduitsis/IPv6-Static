package DBHelper;

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

use parent qw(Exporter);

our @EXPORT = qw( &db_getoptions &db_connect );

my $db_host = 'localhost';
my $db_username;
my $db_password;
my $db_name='sch_ipv6';
my $dbh;

my %getopt_db_args = ( 
	'host|h=s' => \$db_host, 
	'user|u=s' => \$db_username,
	'password|p:s' => \$db_password ,
	'db=s' => \$db_name
);

sub db_getoptions {
	GetOptions( @_ , %getopt_db_args );
}

sub db_connect { 
	if( defined( $db_password) && ( $db_password eq '' ) ) {
		ReadMode 2;
		my $term = Term::ReadLine->new('password prompt');
		my $prompt = 'password:';
		$db_password = $term->readline($prompt);
		ReadMode 0;
		say '';
		say STDERR '';
	}
	defined ( my $dbh = DBI->connect ("DBI:mysql:database=$db_name;host=$db_host", $db_username, $db_password, {mysql_enable_utf8 => 1} ) ) or do { die DBI::errstr };
	return $dbh;
}

1;