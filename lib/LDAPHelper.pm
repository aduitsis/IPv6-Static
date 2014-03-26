package LDAPHelper;

use utf8;
use Encode qw(decode);

use v5.14;

use warnings;
use strict;
use Net::LDAP;
use Net::LDAP::Entry; #why do I do that you ask, right? 
use Data::Printer;
use Data::Dump qw(pp);
use Getopt::Long;
use YAML qw(Dump);
use FindBin qw($Bin);
use Carp;

my $DEBUG;

my $ldap_uri;
my $ldap_bind_dn;
my $ldap_bind_passwd;
my $ldap_search_base;
my $ldap_units_base;
my $ldap_units_filter;
my $ldap_units_attributes;
my $ldap_accounts_base;
my $ldap_accounts_filter;
my $ldap_accounts_attributes;

my $output = $Bin.'/../tmp.tmp';

my $settings_file = $Bin.'/../etc/ldap_settings.rc' ;
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

my %settings;
$settings{ uri } = $ldap_uri;
$settings{ bind_dn } = $ldap_bind_dn;
$settings{ bind_passwd } = $ldap_bind_passwd;
$settings{ search_base } = $ldap_search_base;
$settings{ units_base } = $ldap_units_base;
$settings{ units_filter } = $ldap_units_filter;
$settings{ units_attributes } = $ldap_units_attributes;
$settings{ accounts_base } = $ldap_accounts_base;
$settings{ accounts_filter } = $ldap_accounts_filter;
$settings{ accounts_attributes } = $ldap_accounts_attributes;

sub new {
	my $class = shift(@_) // die 'incorrect call';
	my %options = ( @_ );

	$DEBUG = 1 if ( $options{ DEBUG } || $options{ debug } || $options{ Debug } );

	my $self = {};

	for ( qw( uri bind_dn bind_passwd search_base units_base units_filter accounts_base accounts_filter units_attributes accounts_attributes ) ) {
		$self->{$_} = ( exists $options{ $_ } )? $options{ $_ } : $settings{ $_ } ;
	}

	$self->{ 'robust_delete' } = 1 if ( $options{ 'robust_delete' } );

	$self->{ldap} = Net::LDAP->new( $self->{uri} , debug => 0 ) or die $!;

	my $mesg = $self->{ldap}->bind( $self->{bind_dn} , password=>$self->{bind_passwd} );
	$mesg->code && die $mesg->error; #just to make sure everything went ok

	return bless $self, $class;
}


sub search {
	my $self = shift(@_) // die 'incorrect call';
	my $base = shift(@_) // $self->{search_base};
	my $scope = shift(@_) // 'sub';
	my $attributes = shift(@_) // [ qw( ) ] ;
	my $filter = shift(@_) // 'objectclass=*';

	my $mesg = $self->{ldap}->search(
		base => $base,
		scope => $scope,
		attrs=> $attributes,
		filter => $filter, #or should it be objectclass=gsnUnit ?
		raw => qr/(?i:^jpegPhoto|;binary)/,
	); 
	$mesg->code && die $mesg->error;
	
	#careful, this will return 0,1 or many Net::LDAP::Entry items, always use list context
	return $mesg->entries ; 

	

}

sub modify { 
	my $self = shift(@_) // die 'incorrect call';
	my $dn = shift(@_) // die 'incorrect call';
	### $DEBUG && p @_;
	my $mesg = $self->{ldap}->modify( $dn , @_ );
	$mesg->code && confess $mesg->error;
}

sub DESTROY {
	my $mesg = $_[0]->{ ldap }->unbind;
	$mesg->code && die $mesg->error;
}

sub get_units_entries { 
	my $self = shift // die 'incorrect call';
	$self->search( $self->{units_base} , 'sub' , $self->{ units_attributes }, $self->{ units_filter } ) ;
}

sub get_accounts_entries {
	my $self = shift // die 'incorrect call';
	$self->search( $self->{accounts_base}, 'sub', $self->{ accounts_attributes }, $self->{ accounts_filter } );
}

sub entries_to_data {
	my $data;
	for my $entry (@_) {
		$data->{ $entry->dn }->{ attributes }  = entry_to_data( $entry );
		$data->{ $entry->dn }->{ ldap_entry } = $entry;
	}
	return $data;	
}

sub entry_to_data {
	my $entry = shift( @_ ) // die 'missing entry';
	my $ret;
	for my $attr ($entry->attributes) {
		push @{ $ret->{lc($attr)} }, $entry->get_value($attr) ;
	}
	return $ret;
}

sub get_units {
	entries_to_data( $_[0]->get_units_entries );
}
sub get_accounts {
	entries_to_data( $_[0]->get_accounts_entries );
}

sub additional_account_filter {
	$_[0]->{ accounts_filter } = '('. $_[1] .'(' . $_[2] . ')' . $_[0]->{ accounts_filter } . ')'
}

sub set_units_base {
	$_[0]->{ units_base } = $_[1];
}
	

sub get_combination {
	my $self = shift( @_ ) // die 'incorrect call';

	my $accounts = $self->get_accounts;

	my %locality;

	for my $account ( keys %{$accounts} ) {
		for my $locality ( @{ $accounts->{$account}->{ attributes }->{l} } ) {
			push @{ $locality{ $locality } } , 
				{ 
				account => $account , 
				uid => $accounts->{$account}->{attributes}->{uid}->[0], 
				ldap_object => $accounts->{$account}->{ ldap_entry } , 
				attributes => $accounts->{$account}->{ attributes },
			 	} 
			; 
		}
	}

	my $units = $self->get_units;

	for my $unit ( keys %{$units} ) {
		if( exists( $locality{ $unit } ) ) {
			$units->{$unit}->{ accounts } = $locality{ $unit } ; 
		}
		else {
			print STDERR "Warning: unit $unit does not have a corresponding account \n";
			$units->{$unit}->{ accounts } = [];
		}
	}

	return $units;
}

sub delete_attributes {
	my $self = shift( @_ ) // die 'incorrect call';
	my $entry = shift( @_ ) // die 'missing entry';

	my @attributes = ( @_ );

	my $delete_attributes = [];
	
	for my $attribute ( @attributes ) {
		if( grep {  $_ eq $attribute  } ( $entry->attributes ) ) {
			push @{$delete_attributes}, $attribute;
			say STDERR "\t\tdeleting $attribute";
		}
		else {
			say STDERR "\t\t$attribute not set";
		}
	}
		
	if ( $self->{ robust_delete } ) {
		my $replacements = { map { $_ => 'dummy' } @{$delete_attributes} };
		if( %{ $replacements } ) {
			$self->modify( $entry, replace => $replacements );
		}
	}
	$self->modify( $entry, delete => $delete_attributes ) if @{ $delete_attributes }; #the array evaluates to true only when there is at least one element

	return 1;
}
	
sub write_attributes {
	my $self = shift( @_ ) // die 'incorrect call';
	my $entry = shift( @_ ) // die 'missing entry';

	my %attributes = ( @_ );

	my $modifications = {};

	for my $attribute ( keys %attributes ) {
		#iterate over each attribute, then over each of its values, then see if there is a match
		if( grep { ( $_ eq $attribute ) && grep { $attributes{ $attribute } eq $_ } ( $entry->get_value( $attribute ) ) } ( $entry->attributes) ) {
			$DEBUG && say STDERR "\t\t$attribute already set";
		}
		else {
			$DEBUG && say STDERR "\t\tsetting $attribute = ".$attributes{ $attribute };
			$modifications->{ $attribute } = $attributes{ $attribute } ;
		}		
	}
	if( %{ $modifications } ) {  #if the hash is emtpy, evaluates false in boolean context
		$self->modify( $entry , replace => $modifications );

		return $modifications
	}
	else {
		return
	}
}


1;
