#!/usr/bin/perl -w

use v5.14;

use utf8;
use locale;
use open qw(:std :utf8);
use charnames qw(:full :short);
use Encode qw(decode);
use warnings qw(FATAL utf8);
use strict;
use Data::Printer;
use FindBin qw($Bin);
use lib $Bin.'/../lib/';
use LDAPHelper;
use Storable qw(nstore retrieve);
use Getopt::Long;
use Heuristics;
use DBHelper;
use Pod::Usage;
use IPv6::Static;
use Pools;
use POSIX;

my $save_filename;
my $load_filename;
my $DEBUG;
my $delete;
my $yes;
my $help;
my $dry;

GetOptions('help|?'=> \$help, 'd|debug' => \$DEBUG , 's|save=s' => \$save_filename , 'l|load=s' => \$load_filename , 'delete' => \$delete , 'yes|y' => \$yes, 'n' => \$dry );

pod2usage(-verbose => 2) if $help;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $ldap = LDAPHelper->new;
my $dbh = db_connect;
my $p = Pools->new( $dbh );

my $units; 

if( defined( $load_filename ) ) {
	say STDERR 'loading LDAP units from '.$load_filename;
	$units = retrieve( $load_filename ) ;
} 
else {
	say STDERR 'retrieving units from LDAP';
	$units = $ldap->get_combination ;
}

if ( defined( $save_filename ) ) {
	say STDERR 'saving units into '.$save_filename;
	nstore($units,$save_filename)
}


my %counter;

UNIT: 
for my $unit (keys %{ $units } ) {
	$DEBUG && p $units->{ $unit } ;
	say STDERR $unit;

	if ( $unit =~ /\P{ASCII}/ ) {
		say STDERR "WARNING: '$unit' contains non-ASCII characters";
	}

	my $cat = eval { 
		Heuristics::classify( $units->{$unit} ) 
	};
	if($@) {
		say STDERR "WARNING: Cannot classify $unit.\nError was: $@";
	} 

	my $category = DBHelper::categorize( $cat );

	say STDERR "\t$category";

	if( ! $p->exists_entry( $unit ) )  {
		if( ! $dry ) {
			my $ret = eval {
				IPv6::Static::create_account($dbh,$category,$unit)
			};
			if($@) {
				say STDERR "Cannot create new user $unit. Error was: $@";
			}
			else {
				say STDERR "\t".$ret->{status} ;
			}
		}
		else {
			say STDERR "$unit does not exist in database, so skipping to the next unit";
			next UNIT
		}
	} 
	else {
		say STDERR "\trecord already exists";
	}

	my $r =  $p->get_prefixes( $unit ) ;
	say STDERR "\t".$r->{framed}.' '.$r->{delegated};

	my $n_accounts = scalar @{ $units->{ $unit }->{accounts} };
	if( $n_accounts == 0 ) { 
		say STDERR "WARNING: unit $unit has no accounts";
		next UNIT;
	}			
	my $split_delegated = ceil( log( $n_accounts ) / log( 2 ) );
	say STDERR "2^$split_delegated accounts for $unit";

	my $split_framed = 64 - $r->{framed}->get_prefixlen;

	my @framed = $r->{framed}->split( $split_framed );
	my @delegated = $r->{delegated}->split( $split_delegated );

	if( $split_delegated > $split_framed ) { 
		say STDERR "\tEXTREME CAUTION: Unit $unit requires 2^$split_delegated /64 and /56 pairs, but we can only provide 2^$split_framed. Skipping this one";
		next UNIT;
	}	
	
	if( $yes ) {
		ACCOUNT:
		for my $account ( sort @{ $units->{ $unit }->{accounts} } ) {	
			my ( $framed , $delegated  ) = ( shift @framed , shift @delegated  );
			if( ! defined( $framed ) ) { 
				say STDERR 'No framed prefix left for '.$account->{ account };
				next ACCOUNT;
			}
			if( ! defined( $delegated ) ) { 
				die 'internal error! there should always be a delegated prefix available';
			}
			say STDERR "\taccount ". $account->{ account } .' '.$framed->to_string.' '.$delegated->to_string;		
			#my $mods = $ldap->write_attributes( $account->{ ldap_object } , radiusFramedIPv6Prefix => $r->{framed}->to_string , radiusDelegatedIPv6Prefix => $r->{delegated}->to_string ) ;
			#say STDERR "\tchanges: ".join(',',map { $_ . '=' . $mods->{$_} } (keys %{$mods})) if( $mods );
		}
	}

	$counter{ $category } += 1;
}

p %counter;

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

assign_ipv6_addresses_to_ldap.pl -- assign IPv6 prefixes to every account in the directory

=head1 SYNOPSIS

 assign_ipv6_addresses_to_ldap.pl [ options ] 

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exit.

=item B<-n>

Dry run, i.e. do not apply changes to database. Unless this option is used, 
changes *WILL* be made to the database by default

=item B<-d>

Enable debug output

=item B<--delete> 

When finished with the directory contents, examine whether there are any
accounts in the static address database that are not in the directory.
If the --yes option is set, delete those accounts from the static address
database

=item B<--yes | -y>

Actually do whatever changes are needed to the directory and the static
address database. If set, new accounts will be inserted as needed in the
database, accounts not present in the directory (if using --delete) will
be pruned, IPv6 prefixes will be updated in the directory.

=item B<-s | --save FILE>

Save a copy of the directory contents into FILE. FILE is a Perl Storable
and can be used later by using the -l option.

=item B<-l | --load FILE>

Insted of exhaustively querying the directory, use a cached copy of its
contents which is stored in FILE. See also -s.

=back

=head1 DESCRIPTION 

The purpose of this program is to return the assigned IPv6 prefixes for
a specific user identifier which is supplied as the argument. If the
user identifier does not exist, the program will emit an error message
and exit. Otherwise, one would expect a couple of prefixes to be
printed, one line each.

=cut
