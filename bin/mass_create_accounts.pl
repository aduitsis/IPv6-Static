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

use lib $Bin.'/../lib';
use IPv6::Static;

use DBHelper;
use Pod::Usage;

use Heuristics;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $help;
my $delete;
my $do_not_create;
my $yes;

my $DEBUG = 0;
db_getoptions('help|?' => \$help, 'delete'=> \$delete, 'd' => \$DEBUG , 'nocreate' => \$do_not_create, 'y|yes' => \$yes );
pod2usage(-verbose => 2) if $help;

my $filename = shift // die 'missing filename';

my $units = retrieve $filename;

my %counter;


#legend:
# 1: πρωτοβάθμια εκπαιδευτική μονάδα
# 2: δευτεροβάθμια εκπαιδευτική
# 3: διοικητική μονάδα 
# 4: τριτοβάθμια (sic) μονάδα
# 5: εκπαιδευτική μονάδα ανεξ βαθμίδας
# 7: unknown


my $cat_map = {
	1 => 'elementary',
	2 => 'highschool',
	3 => 'administrative',
	4 => 'administrative',
	5 => 'administrative',
	7 => 'administrative',
};

my $dbh = db_connect;

if( ! $do_not_create ) {
	for my $unit ( keys %{$units} ) {
		
		$DEBUG && say STDERR 'Inspecting unit '.$unit;
		$DEBUG && p $units->{$unit} ; 

		if ( $unit =~ /\P{ASCII}/ ) {
			say STDERR "WARNING: dn: $unit contains non-ASCII characters";
		}
		my $cat = eval { 
			Heuristics::classify( $units->{$unit} ) 
		};
		if($@) {
			say STDERR "WARNING: Cannot classify $unit.\nError was: $@";
		} 
		else {
			if( $cat ) {
				if( ! exists( $cat_map->{ $cat } ) ) {
					die "Missing mapping for category $cat. Please add it to \%cat_map ";
				}
				else {
					$DEBUG && say STDERR 'unit '.$unit.' classified as '.$cat_map->{ $cat } ; 
				}

			#	my $sth = $dbh->prepare('REPLACE INTO units SET dn=?,group_id=(select id from groups where name=?)') or confess $dbh->errstr;
			#	$sth->execute($unit,$cat_map->{ $cat }) or confess $sth->errstr;

				
				my $ret = eval { 
					IPv6::Static::create_account($dbh,$cat_map->{ $cat },$unit) 
				};
				if($@) {
					print STDERR 'Cannot create new user '.$unit."\nError was: $@\n";
				} 
				else {
					say STDERR $unit."\t".$cat_map->{ $cat }."\t".$ret->{status} ;
				}
			#	if ( exists $units->{$unit}->{accounts} ) {
			#		#IPv6::Static::create_account( $units->{$unit}->{account}->{uid} , $cat );			
			#		for my $account ( @{ $units->{$unit}->{accounts} } )  {
			#			$sth = $dbh->prepare('REPLACE INTO accounts SET uid=?,account_dn=?,dn=?') or confess $dbh->errstr;
			#			$sth->execute( $account->{ uid } , $account->{ account } , $unit );
			#		}
			#	}
			#	else {
			#		#nothing to do
			#	}
				$counter{ $cat } += 1;
			} 
			else {
				die "ERROR: for $unit, category is $cat";
			}
		}
	}
}

$DEBUG && p %counter;

if( $delete ) {
	my $usernames = IPv6::Static::get_all_usernames( $dbh ) ; 
	for my $username ( @{$usernames} ) {
		if( ! exists( $units->{ $username } ) ) {
			if( $yes ) {
				my $ret = eval { IPv6::Static::delete_account_blind($dbh,,$username) } ;
				if($@) {
					say "Cannot delete user $username. Error was: $@";
				} 
				else {
					say $ret->{status};
				}
			}
			else {
				say $username.' should be deleted ';
			}
		}
	}
}

__END__

=head1 NAME

mass_create_accounts -- safely create entries into the static address
database for a set of user identifiers

=head1 SYNOPSIS

 mass_create_accounts.pl [ options ] filename

=head1 OPTIONS

The filename contains all the user identifiers that must be inserted
into the static address database. The format of the file is YML. Its
structure is the same as the output of the combine.pl command. 

=over 8

=item B<-nocreate>

Do not run the loop to create user identifiers in the static address
database. 

=item B<--delete>

Try to identify whatever usernames are in the static address database
but are missing from the source YML file.

=item B<-yes|-y> 

Actually delete usernames that are in the static address database but
are missing from the source YML file 

=item B<-help>

Print a brief help message and exit.

=item B<-d>

Enable more verbose output

=item B<-host|-h> 

Connect to mysql on this hostname.

=item B<-user|-u>

Use this mysql username when connecting.

=item B<-p|-password>

Use this mysql password when connecting.

=item B<-db> 

Use this database when connecting.


=back

=head1 DESCRIPTION 

The purpose of this program is to take a list of user identifiers,
classify them into a suitable category and then insert a corresponding
record into the static address database. If the user identifier already
has an entry in the static address database, then the entry is
maintained, thus user identifier maintains the same address(es). So it
is perfectly safe to run the program as many times as desired, since
user identifiers that already have assigned address(es) will not be
affected. 

=cut
