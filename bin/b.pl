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
use Carp;

my $save_filename;
my $load_filename;
my $DEBUG;
my $delete;
my $yes;
my $help;
my $dry;

my $usernames_file;

GetOptions('help|?'=> \$help, 'd|debug' => \$DEBUG , 's|save=s' => \$save_filename , 'l|load=s' => \$load_filename , 'delete' => \$delete , 'yes|y' => \$yes, 'n' => \$dry , 'usernames=s' => \$usernames_file );

pod2usage(-verbose => 2) if $help;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $ldap = LDAPHelper->new;
my $dbh = db_connect;
my $p = Pools->new( $dbh );

my %acct_usernames;
if( $usernames_file ) {
	open(my $file,'<',$usernames_file ) or confess $!;
	for(<$file>) {
		chomp;
		$acct_usernames{ $_ } = 1;	
	}
	close $file;
}

#p %acct_usernames;
	
my $units; 


my %unit_to_category;

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
my $overall_accounts = 0;
my $accounts_in_use = 0;
my %account_counter;
my %account_in_use_counter;

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
		say STDERR "WARNING: Cannot classify $unit.\nSkipping to the next unit.\n\tError returned follows:\n $@";
		next UNIT
	} 

	my $category = DBHelper::categorize( $cat ) // confess 'internal error';

	say STDERR "\t$category";

	# store it for future use
	$unit_to_category{ $unit } = $category;
	

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
			say STDERR "\t$unit does not exist in database, so skipping to the next unit";
			next UNIT
		}
	} 
	else {
		say STDERR "\trecord already exists";
	}

	my $r =  $p->get_prefixes( $unit ) ;
	say STDERR "\t".$r->{framed}.' '.$r->{delegated};

	my @accounts = @{ $units->{ $unit }->{accounts} };
	$overall_accounts += scalar( @accounts );
	$account_counter{ scalar( @accounts ) }++;

	my @used_accounts;

	if( @accounts == 0 ) { 
		say STDERR "\tWARNING: unit $unit has no accounts";
		next UNIT;
	}
	elsif( @accounts == 1 ) {
		say STDERR "\tOK: unit $unit has 1 account";
		@used_accounts = @accounts;
	} 
	else {
		@used_accounts = grep { $acct_usernames{ $_->{uid} } } @accounts;
		#if( @used_accounts == 1 ) {
		#	say "\tOK: unit $unit uses only account $used_accounts[1]";
		#}
		#else { 
		#	say "\tNOTICE: unit $unit uses ".scalar(@used_accounts).' accounts';
		#}
		say STDERR "\t".scalar(@used_accounts)." accounts found in use";
		#p @accounts;
		#p @used_accounts;
		if( @used_accounts > 8 ) {
				
		}
	}		


	my @unused_accounts = grep { my $a = $_; grep { $_ ne $a  } @used_accounts } @accounts;

	my $n_accounts = scalar @used_accounts;

	say "\taccounts: ".join ',',map { $_->{uid} } @accounts;
	say "\tused accounts: ".join ',',map { $_->{uid} } @used_accounts;
	say "\tunused accounts: ".join ',',map { $_->{uid} } @unused_accounts;

	my (@framed,@delegated);

	if( @used_accounts ) {
		my $split_delegated = ceil( log( $n_accounts ) / log( 2 ) );
		say STDERR "\t2^$split_delegated accounts for $unit";
		
		# keep statistics
		$account_in_use_counter{ $n_accounts }++;
		$accounts_in_use += $n_accounts;

		my $split_framed = 64 - $r->{framed}->get_prefixlen;

		@framed = $r->{framed}->split( $split_framed );
		@delegated = $r->{delegated}->split( $split_delegated );

		if( $split_delegated > $split_framed ) { 
			say STDERR "\tEXTREME CAUTION: Unit $unit requires 2^$split_delegated /64 and /56 pairs, but we can only provide 2^$split_framed";
			next UNIT
		}	
	}
	
	if( $yes ) {
		ACCOUNT:
		for my $account ( sort @used_accounts ) {	
			my ( $framed , $delegated  ) = ( shift @framed , shift @delegated  );
			if( ! defined( $framed ) ) { 
				die 'internal error! there should always be a framed prefix available';
			}
			if( ! defined( $delegated ) ) { 
				die 'internal error! there should always be a delegated prefix available';
			}
			say STDERR "\taccount ". $account->{ account } .' '.$framed->to_string.' '.$delegated->to_string;		
			#my $mods = $ldap->write_attributes( $account->{ ldap_object } , radiusFramedIPv6Prefix => $framed->to_string , radiusDelegatedIPv6Prefix => $delegated->to_string ) ;
			#say STDERR "\tchanges: ".join(',',map { $_ . '=' . $mods->{$_} } (keys %{$mods})) if( $mods );
		}
		for my $account ( @unused_accounts ) {
			#$ldap->delete_attributes( $account->{ ldap_object } , 'radiusFramedIPv6Prefix', 'radiusDelegatedIPv6Prefix' );
		}
	}

	$counter{ $category } += 1;
}

say STDERR 'Number of units: '.scalar(keys %{ $units } );
say STDERR 'Number of accounts: '.$overall_accounts;
say STDERR 'Number of accounts in use: '.$accounts_in_use;
say STDERR 'Category breakdown: ';
p %counter;
say STDERR 'Unit counts grouped by account number:';
p %account_counter;
say STDERR 'Unit counts grouped by account in use number:';
p %account_in_use_counter;

DELETE:
if( $delete ) {

	IPv6::Static::map_over_entries( $dbh , sub { 
		my $username = $_->{username};
		my $group_id = $_->{group_id};
	
		my $group_name = DBHelper::categorize( $_->{ group_id } );

		$DEBUG && say STDERR $unit_to_category{ $username };
		$DEBUG && say STDERR DBHelper::categorize( $_->{ group_id }  );
		$DEBUG && say STDERR $username;

		if( ( ! exists( $units->{ $username } ) ) || ( $unit_to_category{ $username } ne $group_name ) ) {
			if( ! exists( $units->{ $username } ) ) { 
				say STDERR "Unit $username is missing from the directory";
			}
			else {
				say STDERR "Unit $username has jumped from $group_name to $unit_to_category{ $username }";
			}
			my $ret = eval { IPv6::Static::delete_account( $dbh, $group_name, $username ) };
			if( $yes ) {
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
	});
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
