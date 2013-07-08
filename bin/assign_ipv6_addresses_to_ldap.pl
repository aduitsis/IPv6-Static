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

my $usernames_file;

GetOptions('help|?'=> \$help, 'd|debug' => \$DEBUG , 's|save=s' => \$save_filename , 'l|load=s' => \$load_filename , 'delete' => \$delete , 'yes|y' => \$yes, 'n' => \$dry , 'usernames=s' => \$usernames_file );

pod2usage(-verbose => 2) if $help;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $ldap = LDAPHelper->new;
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

UNIT: 
for my $unit (keys %{ $units } ) {

	
	$DEBUG && p $units->{ $unit } ;
	say STDERR BOLD GREEN $unit;

	# warn if there are non-ascii characters in the unit name
	if ( $unit =~ /\P{ASCII}/ ) {
		say STDERR RED "\tWARNING: '$unit' contains non-ASCII characters";
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

	#maintain stats
	$counter{ $category } += 1;

	#check database for record
	if( ! $p->exists_entry( $unit ) )  {
		say STDERR "\t$unit not in database";
		if( ! $dry ) {
			my $ret = $p->create_entry($unit,$category);
			say STDERR BOLD BLACK "\t".$ret->{status};
		}
		else {
			say STDERR YELLOW "\tskipping to the next unit since we in dry run mode";
			next UNIT
		}
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
						
		}
	}

	my $r =  $p->get_prefixes( $unit ) ;
	say STDERR BOLD BLACK "\tFramed: ".RESET.WHITE.$r->{framed}.BOLD.BLACK.' Delegated: '.RESET.WHITE.$r->{delegated};

	my @accounts = @{ $units->{ $unit }->{accounts} };
	$overall_accounts += scalar( @accounts );
	$account_counter{ scalar( @accounts ) }++;

	my @used_accounts;
	my $all_accounts_same_prefix = 0;

	if( @accounts == 0 ) { 
		say STDERR RED "\tWARNING: unit $unit has no accounts";
		next UNIT;
	}
	elsif( @accounts == 1 ) {
		say STDERR GREEN "\tOK:".RESET.WHITE.' unit has exactly 1 account';
		@used_accounts = @accounts;
	} 
	else {
		if( $have_accounting  ) { 
			@used_accounts = grep { $acct_usernames{ $_->{uid} } } @accounts;
			if( ! @used_accounts ) { 
				say STDERR YELLOW "\tNo accounting for any known account ... will apply the same prefixes to all accounts";
				$all_accounts_same_prefix = 1;
				@used_accounts = @accounts;
			}
		} 
		else { 
			@used_accounts = @accounts;
		}
		#if( @used_accounts == 1 ) {
		#	say "\tOK: unit $unit uses only account $used_accounts[1]";
		#}
		#else { 
		#	say "\tNOTICE: unit $unit uses ".scalar(@used_accounts).' accounts';
		#}
		say STDERR GREEN "\t".scalar(@used_accounts)." accounts found in accounting records";
		#p @accounts;
		#p @used_accounts;
		if( @used_accounts > 8 ) {
				
		}
	}		

	my @unused_accounts = grep { my $a = $_; ! grep { $_->{uid} eq $a->{uid} } @used_accounts } @accounts;

	say STDERR BOLD BLACK "\tLDAP accounts: ".YELLOW.join ' , ',map { $_->{uid} } @accounts;
	say STDERR BOLD BLACK "\tused accounts: ".YELLOW.join ' , ',map { $_->{uid} } @used_accounts;
	say STDERR BOLD BLACK "\tunused accounts: ".YELLOW.join ' , ',map { $_->{uid} } @unused_accounts;

	my (@framed,@delegated);

	my $n_accounts = scalar @used_accounts;

	if( @used_accounts ) {
		my $split_delegated = ceil( log( $n_accounts ) / log( 2 ) );
		say STDERR GREEN "\tneed ".2**$split_delegated.' '.(($split_delegated == 0)? 'prefix' : 'prefixes');
		
		# keep statistics
		$account_in_use_counter{ $n_accounts }++;
		$accounts_in_use += $n_accounts;

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

	say '';
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

	say STDERR "\n\nNow finding entries in the database that are missing in the directory or have changed group in the directory\n\n";

	$p->map_over_entries( sub { 
		my $group_id = $_->{ group_id } ;
		my $unit = $_->{ username };
		my $db_category = $p->get_category( $unit );
		say STDERR BOLD BLACK $unit.' '.$db_category;

		if( ! exists $units->{ $unit } ) {
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
