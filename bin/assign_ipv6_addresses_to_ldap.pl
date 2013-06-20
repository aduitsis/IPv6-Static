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

my $save_filename;
my $load_filename;
my $DEBUG;
my $delete;
my $yes;
my $help;

GetOptions('help|?'=> \$help, 'd|debug' => \$DEBUG , 's|save=s' => \$save_filename , 'l|load=s' => \$load_filename , 'delete' => \$delete , 'yes|y' => \$yes);

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
		if( $yes ) {
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
	} 
	else {
		say STDERR "\trecord already exists";
	}

	my $r =  $p->get_prefixes( $unit ) ;
	say STDERR "\t".$r->{framed}.' '.$r->{delegated};
	
	if( $yes ) {
		for my $account ( @{ $units->{ $unit }->{accounts} } ) {	
			say STDERR "\taccount ".$account->{account};
			my $mods = $ldap->write_attributes( $account->{ ldap_object } , radiusFramedIPv6Prefix => $r->{framed}->to_string , radiusDelegatedIPv6Prefix => $r->{delegated}->to_string ) ;
			say STDERR "\tchanges: ".join(',',map { $_ . '=' . $mods->{$_} } (keys %{$mods})) if( $mods );
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
