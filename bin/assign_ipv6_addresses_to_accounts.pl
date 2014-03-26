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
use Accounting;
use Pod::Usage;
use IPv6::Static;
use Pools;
use POSIX;
use Carp;
use Term::ANSIColor qw(:constants);
use autodie qw(open close);


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
my $skip;
my $accounts_per_unit_limit = 3;

my $all;

my $usernames_file;
my $save_usernames_file;

GetOptions(
	'help|?'=> \$help, 
	'd|debug' => \$DEBUG , 
	's|save|store=s' => \$save_filename, 
	'l|load=s' => \$load_filename, 
	'delete' => \$delete , 
	'yes|y' => \$yes, 
	'n' => \$dry , 
	'usernames|username|accounting|acct:s' => \$usernames_file , 
	'all' => \$all, 
	'skip' => \$skip, 
	'accounts_per_unit_limit=i' => \$accounts_per_unit_limit, 
	'save_usernames_file|save_usernames=s' => \$save_usernames_file,
);

pod2usage(-verbose => 2) if $help;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $robust_delete = defined( $load_filename )? 1 : 0;
my $ldap = LDAPHelper->new( DEBUG => 1 , robust_delete => $robust_delete );

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
	say STDERR BOLD BLACK "Retrieving accounting from $usernames_file ... ";
	open(my $file,'<',$usernames_file ) or confess $!;
	for(<$file>) {
		chomp;
		$acct_usernames{ $_ } = 1;	
	}
	$have_accounting = 1;
	close $file;
}
elsif( defined($usernames_file) && ( $usernames_file eq '' ) ) {
	say STDERR BOLD BLACK "Retrieving accounting directly ... this will take a while";
	%acct_usernames = ( map { $_ => 1 } @{ &Accounting::get_usernames } );
	$have_accounting = 1;
	if( $save_usernames_file ) {
		say STDERR BOLD BLACK "Saving a copy in $save_usernames_file";
		open( my $output_usernames, '>' , $save_usernames_file );
		for( sort keys %acct_usernames ) {
			say { $output_usernames } $_
		}
		close $output_usernames;
	}
}
else {
	say STDERR BOLD BLACK "No accounting records available...will try to best guess"
}		

if( $have_accounting && ( scalar keys %acct_usernames <= 1 ) ) {
	say STDERR BOLD RED "Too few usernames in accounting...this is probably a serious error ... aborting";
	exit
}

my $units; 

if ( defined( $load_filename ) && defined( $save_filename ) ) {
	say STDERR "Please do not use both the -s and the -l options at the same time";
	exit
}

if( defined( $load_filename ) ) {
	say STDERR BOLD BLACK 'loading LDAP units from '.$load_filename;
	$units = retrieve( $load_filename ) ;
} 
else {
	say STDERR BOLD BLACK 'retrieving units from LDAP (this will probably take a while)';
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

my %accounts;

#if the user has chosen to --skip
$units = {} if $skip;

UNIT: 
for my $unit (keys %{ $units } ) {

	$statistics->{ 'unit count' } ++;
	
	$DEBUG && p $units->{ $unit } ;
	say STDERR BOLD GREEN $unit;

	# warn if there are non-ascii characters in the unit name
	if ( $unit =~ /\P{ASCII}/ ) {
		say STDERR RED "\tWARNING: '$unit' contains non-ASCII characters";
		push @{ $statistics->{ 'units with non-ASCII characters in DN' } }, $unit;
	}

	# classify the unit using the Heuristics library
	my $cat = eval { 
		Heuristics::classify( $units->{$unit} ) 
	};
	if( $@ ) {
		say STDERR RED "WARNING: Cannot classify $unit.\nSkipping to the next unit.\n\tError returned follows:\n $@";
		push @{ $statistics->{ 'unclassifiable units' } }, $unit;
		next UNIT
	} 

	# convert the integer category to string 
	my $category = DBHelper::categorize( $cat ) // confess 'internal error';
	say STDERR YELLOW "\t$category";

	$statistics->{ 'units per category' }->{ $category }++;

	my @accounts = @{ $units->{ $unit }->{accounts} };


	$statistics->{ 'overall number of accounts in directory'} += scalar( @accounts );
	$statistics->{'accounts per unit distribution in directory'}->{ scalar( @accounts ) }++;

	my @used_accounts;
	my $all_accounts_same_prefix = 0;

	if( @accounts == 0 ) { 
		say STDERR RED "\tWARNING: unit $unit has no accounts";
		push @{ $statistics->{ 'units with no accounts in directory' } }, $unit;
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
			
			$statistics->{'overall used accounts'} += scalar @used_accounts;
			$statistics->{'used accounts per unit distribution'}->{ scalar @used_accounts }++;

			if( ! @used_accounts ) { 
				say STDERR YELLOW "\tNo accounting for any known account ... will apply the same prefixes to all accounts";
				$all_accounts_same_prefix = 1;
				@used_accounts = @accounts;
				$statistics->{'units with no accounting for any account'} += 1;
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

		if( ( @used_accounts > $accounts_per_unit_limit ) && ( ! $all_accounts_same_prefix ) ) {
			$statistics->{'units exceeding account limit of '.$accounts_per_unit_limit}->{ $unit } = scalar @used_accounts;
			say STDERR BOLD RED "\tERROR: account limit $accounts_per_unit_limit exceeded (found ".scalar(@used_accounts).") for $unit";
			say STDERR '';
			next UNIT;
		}

	}		

	$statistics->{'used accounts'} += scalar @used_accounts;
	$statistics->{'used acounts per unit'}->{ scalar @used_accounts }++;
	$statistics->{'used acounts per category'}->{ $category } += scalar @used_accounts;

	my @unused_accounts = grep { my $a = $_; ! grep { $_->{uid} eq $a->{uid} } @used_accounts } @accounts;

	say STDERR BOLD BLACK "\tunused accounts: ".YELLOW.join ' , ',map { $_->{uid} } @unused_accounts;

	my $n_accounts = scalar @used_accounts;

	ACCOUNT:
	for my $account ( sort @used_accounts ) {	
		my $uid = $account->{ uid };

		# save the value indexed by uid for later
		$accounts{ $uid } = $account;

		say STDERR BOLD BLACK "\tassigning IPv6 to ".BOLD.WHITE.$uid.RESET." ... ";

		if( ! $p->exists_entry( $uid ) )  {
			say STDERR "\t\t$uid not in database...";
			if( ! $dry ) {
				eval { 
					my $ret = $p->create_entry($uid,$category);
					say STDERR BOLD BLACK "\t\t".$ret->{status}
				};
				if( $@ ) { 
					say STDERR BOLD RED "\t\tCannot create a new entry";
					next ACCOUNT
				}
			}
			else {
				say STDERR YELLOW "\t\tskipping to the next account since we are in dry run mode";
				next ACCOUNT;
			}
		 	$statistics->{'accounts found for the first time'}++;
		}
		else {
			$statistics->{'accounts already known to us'}++;
			my $db_category = $p->get_category( $uid );
			if( $db_category eq $category ) {
				say STDERR BOLD BLACK "\t\trecord already exists in database in the correct category";
			}
			else {
				say STDERR RED "\t\trecord exists, but in category $db_category instead of $category";
				if( ! $dry ) {
					say STDERR RED "\tDeleting $uid of $db_category from the database...";
					my $ret = $p->delete_entry( $uid, $db_category );
					say "\t\t".$ret->{status};
					$ret = $p->create_entry($uid,$category);
					say "\t\t".$ret->{status}
				}
				else {
					say STDERR RED "\t\t$uid of $db_category should be deleted but we are on dry run mode";
					next ACCOUNT
				}
				$statistics->{ 'accounts that changed category' }->{ $uid } = "from $db_category to $category";
			}
		}
	
		my $r =  $p->get_prefixes( $uid ) ;				

		say STDERR BOLD BLACK "\t\tFramed: ".RESET.WHITE.$r->{framed}.BOLD.BLACK.' Delegated: '.RESET.WHITE.$r->{delegated};
			

		say STDERR CYAN "\t\t". 'ASSIGN: '. $uid .' '.$r->{ framed }->to_string.' '.$r->{ delegated }->to_string;		
		if( $yes  ) {
			my $mods = $ldap->write_attributes( $account->{ ldap_object } , radiusFramedIPv6Prefix => $r->{ framed }->to_string , radiusDelegatedIPv6Prefix => $r->{ delegated }->to_string ) ;
			say STDERR "\t\tchanges: ".join(',',map { $_ . '=' . $mods->{$_} } (keys %{$mods})) if( $mods );
		}
	}
	for my $account ( @unused_accounts ) {
		say STDERR CYAN "\t\t".'DELETE: all prefixes of '.$account->{uid}.' in the directory';
		if( $yes ) {
			# if we are using a cached copy of the LDAP, we may eventually
			# try to delete something that has already been deleted in the
			# real LDAP. So we need to make sure that there actually is
			# an attibute before we try to delete it. So we will set it to
			# a dummy value and then delete it right after

			$ldap->delete_attributes( $account->{ ldap_object } , 'radiusFramedIPv6Prefix', 'radiusDelegatedIPv6Prefix' );
		}
	}

	say STDERR '';
}


#for (sort { $a <=> $b } keys %account_in_use) {
#	say $_.' '.join(' ',@{ $account_in_use{ $_ } } );
#}

DELETE:
if( $delete ) {

	say STDERR "\n\nNow finding entries in the database that are missing in the directory\n\n";

	$p->map_over_entries( sub { 
		### is this needed? ### my $group_id = $_->{ group_id } ;
		my $uid = $_->{ username };
		my $db_category = $p->get_category( $uid );
		say STDERR BOLD BLACK $uid.' '.$db_category;

		if( ! exists $accounts{ $uid } ) {
			push @{ $statistics->{ 'deleted accounts from database' } },$uid;
			say STDERR RED "\t$uid is missing from the directory";
			if( ! $dry ) {
				say STDERR CYAN "\tDeleting $uid of $db_category from the database...";
				my $ret = $p->delete_entry( $uid, $db_category ) ;
				say STDERR BOLD BLACK "\t".$ret->{ status } ;
			} 
			else {
				say STDERR CYAN "\t".$uid.' should be deleted but we are on dry run mode';
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


=item B<--usernames [FILE]>

Try to ascertain which accounts are actually used by looking at actual
accounting records. 

If this option is used without a password, the program will try to read
settings from the etc/accounting.rc and connect to an appropriate 
accounting database/table and retrieve the usernames.

If FILE is supplied, read a usernames that have been used from FILE. 
FILE is line separated, one line per username. Typically, these usernames 
will be used to cross reference which of the accounts have actually been 
used.

=item B<--save_usernames FILE>

If the --usernames option is used without the optional argument to retrieve
the usernames from a database directly, then this option can be used to
save the retrieved usernames in FILE.

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

Instead of exhaustively querying the directory, use a cached copy of its
contents which is stored in FILE. See also -s.

=item B<--skip>

Skip the creation and updating of addresses and go to the deletion phase directly. 
The B<--delete> option should also be used, otherwise the script will do nothing

=item B<--accounts_per_unit_limit>

Number of used accounts for a unit beyond which the unit will be considered abnormal 
and a warning will be generated. Default is 3. Note that the unit will still get IPv6 
prefixes for all the accounts

=back

=head1 DESCRIPTION 

The purpose of this program is to return the assigned IPv6 prefixes for
a specific user identifier which is supplied as the argument. If the
user identifier does not exist, the program will emit an error message
and exit. Otherwise, one would expect a couple of prefixes to be
printed, one line each.

=cut
