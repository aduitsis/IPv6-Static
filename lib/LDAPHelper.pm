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

my $ldap_uri;
my $ldap_bind_dn;
my $ldap_bind_passwd;
my $ldap_search_base;
my $ldap_units_base;
my $ldap_units_filter;
my @ldap_units_attributes;
my $ldap_accounts_base;
my $ldap_accounts_filter;
my @ldap_accounts_attributes;

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

sub new {
	my $class = shift(@_) // die 'incorrect call';

	my $ldap = Net::LDAP->new( $ldap_uri , debug => 0 ) or die $!;

	my $mesg = $ldap->bind( $ldap_bind_dn , password=>$ldap_bind_passwd );
	$mesg->code && die $mesg->error; #just to make sure everything went ok

	return bless { ldap => $ldap }, $class;
}


sub search {
	my $self = shift(@_) // die 'incorrect call';
	my $base = shift(@_) // $ldap_search_base;
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
	my $mesg = $self->{ldap}->modify( $dn , @_ );
	$mesg->code && die $mesg->error;
}

sub DESTROY {
	my $mesg = $_[0]->{ ldap }->unbind;
	$mesg->code && die $mesg->error;
}

sub get_units_entries { 
	$_[0]->search( $ldap_units_base , 'sub' , \@ldap_units_attributes, $ldap_units_filter ) ;
}

sub get_accounts_entries {
	$_[0]->search( $ldap_accounts_base, 'sub', \@ldap_accounts_attributes, $ldap_accounts_filter );
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

sub get_combination {
	my $self = shift( @_ ) // die 'incorrect call';

	my $units = $self->get_units;
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

sub write_attributes {
	my $self = shift( @_ ) // die 'incorrect call';
	my $entry = shift( @_ ) // die 'missing entry';

	my %attributes = ( @_ );

	my $modifications = {};

	for my $attribute ( keys %attributes ) {
		if( grep { ( $_ eq $attribute ) && grep { $attributes{ $attribute } eq $_ } ( $entry->get_value( $attribute ) ) } ( $entry->attributes) ) {
			#say STDERR "\t$attribute already set";
		}
		else {
			#say STDERR "\tsetting $attribute = ".$attributes{ $attribute };
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
