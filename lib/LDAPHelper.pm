package LDAPHelper;

use utf8;
use Encode qw(decode);

use v5.14;

use warnings;
use strict;
use Net::LDAP;
use Data::Printer;
use Data::Dump qw(pp);
use Getopt::Long;
use YAML qw(Dump);
use FindBin qw($Bin);

my $ldap_uri;
my $ldap_bind_dn;
my $ldap_bind_passwd;
my $ldap_search_base;
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
        say STDERR 'settings file missing'
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
	
	#careful, this will return 0,1 or many Net::LDAP::Entry items, return forces list context
	return $mesg->entries ; 

	

}

sub modify { 
	my $self = shift(@_) // die 'incorrect call';
	my $dn = shift(@_) // die 'incorrect call';
	my $mesg = $self->{ldap}->modify( $dn , add => { @_ } );
	$mesg->code && die $mesg->error;
}

sub DESTROY {
	my $mesg = $_[0]->{ ldap }->unbind;
	$mesg->code && die $mesg->error;
}


1;
