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
use AccountClassify;
use Storable qw(nstore retrieve);
use Getopt::Long;
use Heuristics;
use DBHelper;
use Pod::Usage;
use IPv6::Static;
use Pools;
use POSIX;
use Carp;
use Term::ANSIColor qw(:constants);


if( -t STDERR ) {
	$Term::ANSIColor::AUTORESET = 1;
}
else {
	$ENV{ANSI_COLORS_DISABLED} = 1 
}

my $save_filename;
my $load_filename;
my $DEBUG;
my $delete;
my $yes;
my $help;
my $dry;

my $all;

my $usernames_file;

GetOptions('help|?'=> \$help, 'd|debug' => \$DEBUG , 's|save|store=s' => \$save_filename , 'l|load=s' => \$load_filename , 'delete' => \$delete , 'yes|y' => \$yes, 'n' => \$dry , 'usernames|username|accounting|acct=s' => \$usernames_file , 'all' => \$all );

pod2usage(-verbose => 2) if $help;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $ldap = LDAPHelper->new;

my $exact_unit;
if( defined( $exact_unit = shift ) ) {
	$ldap->additional_account_filter('&','l='.$exact_unit);
	$ldap->set_units_base( $exact_unit );
}
else {
	if( ! $all ) {
		say STDERR 'Cannot work on all the units unless the --all option is specified';
		exit
	}
}

my $p = Pools->new( db_connect );

my %acct_usernames;
my $have_accounting;
if( $usernames_file ) {
	open(my $file,'<',$usernames_file ) or confess $!;
	for(<$file>) {
		chomp;
		$acct_usernames{ $_ } = 1;	
	}
	$have_accounting = 1;
	close $file;
}

#p %acct_usernames;
	
my $units; 

if( defined( $load_filename ) ) {
	say STDERR BOLD BLACK 'loading LDAP units from '.$load_filename;
	$units = retrieve( $load_filename ) ;
} 
else {
	say STDERR BOLD BLACK 'retrieving units from LDAP';
	$units = $ldap->get_combination ;
}

if ( defined( $save_filename ) ) {
	say STDERR BOLD BLACK 'saving units into '.$save_filename;
	nstore($units,$save_filename)
}


my %counter;
my $overall_accounts = 0;
my $accounts_in_use = 0;
my %account_counter;
my %account_in_use_counter;
my %account_in_use;

my $statistics;

UNIT: 
for my $unit (keys %{ $units } ) {

	$statistics->{ 'unit count' } ++;
	
	$DEBUG && p $units->{ $unit } ;
	say STDERR BOLD GREEN $unit;

	# warn if there are non-ascii characters in the unit name
	if ( $unit =~ /\P{ASCII}/ ) {
		say STDERR RED "\tWARNING: '$unit' contains non-ASCII characters";
		#push @{ $statistics->{ 'units with non-ASCII characters in DN' } }, $unit;
	}

	# classify the unit using the Heuristics library
	my $cat = eval { 
		Heuristics::classify( $units->{$unit} ) 
	};
	if($@) {
		say STDERR RED "WARNING: Cannot classify $unit.\nSkipping to the next unit.\n\tError returned follows:\n $@";
		next UNIT
	} 

	# convert the integer category to string 
	my $category = DBHelper::categorize( $cat ) // confess 'internal error';
	say STDERR YELLOW "\t$category";

	$statistics->{ 'unit category count' }->{ $category }++;

	#check database for record
	if( ! $p->exists_entry( $unit ) )  {
		say STDERR "\t$unit not in database";
		if( ! $dry ) {
			my $ret = $p->create_entry($unit,$category);
			say STDERR BOLD BLACK "\t".$ret->{status};
		}
		else {
			say STDERR YELLOW "\tskipping to the next unit since we are in dry run mode";
			next UNIT
		}
		$statistics->{'units found for the first time'}++;
	} 
	else {
		my $db_category = $p->get_category( $unit );
		if( $db_category eq $category ) {
			say STDERR BOLD BLACK "\trecord already exists in database in the correct category";
		} 
		else {
			say STDERR RED "\trecord exists, but in category $db_category instead of $category";
			if( ! $dry ) {
				say STDERR RED "\tDeleting $unit of $db_category from the database...";
				my $ret = $p->delete_entry( $unit, $db_category );
				say "\t".$ret->{status};
				$ret = $p->create_entry($unit,$category);
				say "\t".$ret->{status};
			} 
			else {
				say STDERR RED "\t$unit of $db_category should be deleted but we are on dry run mode";
				next UNIT
			}
			push @{ $statistics->{ 'units that changed category' } }, $unit;
		}
	}

	my $r =  $p->get_prefixes( $unit ) ;
	say STDERR BOLD BLACK "\tFramed: ".RESET.WHITE.$r->{framed}.BOLD.BLACK.' Delegated: '.RESET.WHITE.$r->{delegated};

	my @accounts = @{ $units->{ $unit }->{accounts} };


	$statistics->{ 'overall accounts in directory'} += scalar( @accounts );
	$statistics->{'overall accounts per unit'}->{ scalar( @accounts ) }++;

	my @used_accounts;
	my $all_accounts_same_prefix = 0;

	if( @accounts == 0 ) { 
		say STDERR RED "\tWARNING: unit $unit has no accounts";
		say STDERR '';
		next UNIT;
	}

	say STDERR BOLD BLACK "\tLDAP accounts: ".YELLOW.join ' , ',map { $_->{uid} } @accounts;

	if( @accounts == 1 ) {
		say STDERR GREEN "\tOK:".RESET.WHITE.' unit has exactly 1 account';
		@used_accounts = @accounts;
	} 
	else {
		if( $have_accounting  ) { 
			@used_accounts = grep { $acct_usernames{ $_->{uid} } } @accounts;
			push @{ $account_in_use{ scalar @used_accounts } }, $unit;
			
			$statistics->{'accounting accounts'} += scalar @used_accounts;
			$statistics->{'accounting accounts per unit'}->{ scalar @used_accounts }++;

			if( ! @used_accounts ) { 
				say STDERR YELLOW "\tNo accounting for any known account ... will apply the same prefixes to all accounts";
				$all_accounts_same_prefix = 1;
				@used_accounts = @accounts;

			} 
			elsif( @used_accounts > 1 ) {
				# we only wanted one account, but we got more than 1
				# why don't pass it over to AccountClassify and see if it can sort it out?
				# TODO: make sure that leaving out accounts that are connecting is ok
				# @used_accounts = AccountClassify::weed( \@used_accounts );
				say STDERR YELLOW "\tAccounting has more than 1 acount connecting from this unit";
			}
		} 
		else { 
			@used_accounts = AccountClassify::weed( \@accounts );
			$statistics->{'accounts number returned from classifier'} += scalar @used_accounts;
			$statistics->{'accounts per unit according to classifier'}->{ scalar @used_accounts }++;
			if( ! @used_accounts ) {
				say STDERR BOLD RED "\tERROR: cannot find any router or official accounts for $unit";
				say STDERR '';
				next UNIT;
			}
			elsif( @used_accounts > 1 ) {
				say STDERR BOLD RED "\tmore than 1 router or official accounts";
			}
		}

		say STDERR GREEN "\t".scalar(@used_accounts)." used accounts found";

		say STDERR BOLD BLACK "\tused accounts: ".YELLOW.join ' , ',map { $_->{uid} } @used_accounts;

		if( @used_accounts > 3 && ! $all_accounts_same_prefix ) {
			push @{ $statistics->{'units exceeding account limit'} },$unit;
			say STDERR BOLD RED "\tERROR: account limit 4 exceeded (found ".scalar(@used_accounts).") for $unit";
			say STDERR '';
			next UNIT;
		}
	}		

	$statistics->{'effective accounts'} += scalar @used_accounts;
	$statistics->{'effective acounts per unit'}->{ scalar @used_accounts }++;
	$statistics->{'effective acounts per category'}->{ $category } += scalar @used_accounts;

	my @unused_accounts = grep { my $a = $_; ! grep { $_->{uid} eq $a->{uid} } @used_accounts } @accounts;

	say STDERR BOLD BLACK "\tunused accounts: ".YELLOW.join ' , ',map { $_->{uid} } @unused_accounts;

	my (@framed,@delegated);

	my $n_accounts = scalar @used_accounts;

	if( @used_accounts ) {
		my $split_delegated = ceil( log( $n_accounts ) / log( 2 ) );
		say STDERR GREEN "\tneed ".2**$split_delegated.' '.(($split_delegated == 0)? 'prefix' : 'prefixes');
		
		my $split_framed = 64 - $r->{framed}->get_prefixlen;

		@framed = ( $all_accounts_same_prefix )?
			map { ( $r->{framed}->split( $split_framed ) )[0] }  @used_accounts   #everyone gets the same framed prefix
			:
			$r->{framed}->split( $split_framed ); #everyone gets a fair share
		@delegated = ( $all_accounts_same_prefix )? 
			map { $r->{delegated} }  @used_accounts   #everyone gets the same delegated prefix
			: 
			$r->{delegated}->split( $split_delegated ); #everyone gets a fair share

		if( $split_delegated > $split_framed ) { 
			say STDERR RED "\tEXTREME CAUTION: Unit $unit requires 2^$split_delegated /64 and /56 pairs, but we can only provide 2^$split_framed";
			next UNIT
		}	
	}
	else {
		say STDERR RED "\tWARNING: No used accounts for this unit";
	}
	
	for my $account ( sort @used_accounts ) {	
		my ( $framed , $delegated  ) = ( shift @framed , shift @delegated  );
		if( ! defined( $framed ) ) { 
			die 'internal error! there should always be a framed prefix available';
		}
		if( ! defined( $delegated ) ) { 
			die 'internal error! there should always be a delegated prefix available';
		}
		say STDERR CYAN "\t\t". 'ASSIGN: '. $account->{ uid } .' '.$framed->to_string.' '.$delegated->to_string;		
		if( $yes  ) {
			#my $mods = $ldap->write_attributes( $account->{ ldap_object } , radiusFramedIPv6Prefix => $framed->to_string , radiusDelegatedIPv6Prefix => $delegated->to_string ) ;
			#say STDERR "\tchanges: ".join(',',map { $_ . '=' . $mods->{$_} } (keys %{$mods})) if( $mods );
		}
	}
	for my $account ( @unused_accounts ) {
		say STDERR CYAN "\t\t".'DELETE: all prefixes of '.$account->{uid}.' in the directory';
		if( $yes ) {
			#$ldap->delete_attributes( $account->{ ldap_object } , 'radiusFramedIPv6Prefix', 'radiusDelegatedIPv6Prefix' );
		}
	}

	say STDERR '';
}


#for (sort { $a <=> $b } keys %account_in_use) {
#	say $_.' '.join(' ',@{ $account_in_use{ $_ } } );
#}

DELETE:
if( $delete ) {

	say STDERR "\n\nNow finding entries in the database that are missing in the directory or have changed group in the directory\n\n";

	$p->map_over_entries( sub { 
		my $group_id = $_->{ group_id } ;
		my $unit = $_->{ username };
		my $db_category = $p->get_category( $unit );
		say STDERR BOLD BLACK $unit.' '.$db_category;

		if( ! exists $units->{ $unit } ) {
			push @{ $statistics->{ 'deleted units from database' } },$unit;
			say STDERR RED "\t$unit is missing from the directory";
			if( ! $dry ) {
				say STDERR CYAN "\tDeleting $unit of $db_category from the database...";
				my $ret = $p->delete_entry( $unit, $db_category ) ;
				say STDERR BOLD BLACK "\t".$ret->{ status } ;
			} 
			else {
				say STDERR CYAN "\t".$unit.' should be deleted but we are on dry run mode';
			}
			say '';
		}
		else {
			$DEBUG && say STDERR GREEN "\teverything ok";
		}
	});
}

p $statistics unless $exact_unit;

__END__

=head1 NAME

assign_ipv6_addresses_to_ldap.pl -- assign IPv6 prefixes to every account in the directory

=head1 SYNOPSIS

 assign_ipv6_addresses_to_ldap.pl [ options ] [ unit DN ]

=head1 MODES OF OPERATION

If the unit DN is specified in the command line, the program will work
only on the specified unit and all the accounts that point to it. The
--delete option does not apply in this case. 

If a unit DN is not supplied, the program will query and work on all the
units in the directory. To actually work on all the units, the --all
option must also be present to avoid accidental invocations.

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exit.

=item B<-n>

Dry run, i.e. do not apply changes to database. Unless this option is used, 
changes *WILL* be made to the database by default

=item B<-d>

Enable debug output

=item B<--all>

Actually work on all the units that can be found in the directory.


=item B<--usernames FILE>

Read a usernames that have been used from FILE. FILE is line separated,
one line per username. Typically, these usernames will be used to cross
reference which of the accounts have actually been used.

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
