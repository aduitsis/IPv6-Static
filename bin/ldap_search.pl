#!/usr/bin/perl -w

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

GetOptions(
        'h=s'=> \$ldap_uri ,
        'D=s' => \$ldap_bind_dn,
        'W=s' => \$ldap_bind_passwd,
        'b=s' => \$ldap_search_base,
        'output=s' => \$output,
);

my $filter = shift // '(umdobject=schunit)';

my $attributes = \@ARGV;

$attributes = [ qw( businesscategory title ) ] unless @{$attributes};


my $ldap = Net::LDAP->new( $ldap_uri , debug => 0 ) or die $!;

my $mesg = $ldap->bind( $ldap_bind_dn , password=>$ldap_bind_passwd );
$mesg->code && die $mesg->error; #just to make sure everything went ok

$mesg = $ldap->search(
        base => $ldap_search_base,
        scope => 'sub',
        attrs=> $attributes,
        filter => $filter, #or should it be objectclass=gsnUnit ?
	raw => qr/(?i:^jpegPhoto|;binary)/,
); 
$mesg->code && die $mesg->error;


my $data;

foreach my $entry ($mesg->entries) { 
	my $ret;
	for my $attr ($entry->attributes) {
		#push @{ $ret->{lc($attr)} },map { decode('utf8',$_) } ( $entry->get_value($attr) );		
		push @{ $ret->{lc($attr)} }, $entry->get_value($attr) ;		
	}	
	$data->{ $entry->dn } = $ret;
}

print Dump($data);

$mesg = $ldap->unbind;
$mesg->code && die $mesg->error;

