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
use YAML qw(DumpFile);
use FindBin qw($Bin);

my $ldap_uri = 'ldap://dsw.att.sch.gr:389';
my $bind_dn = 'uid=searchuser,dc=sch,dc=gr';
my $bind_passwd = 'searchpass';
my $search_base = 'ou=att-peiraia,ou=units,dc=sch,dc=gr';
my $output = $Bin.'/../tmp.tmp';

GetOptions(
	'h=s'=> \$ldap_uri , 
	'D=s' => \$bind_dn,
	'W=s' => \$bind_passwd,
	'b=s' => \$search_base,
);

my $filter = shift // '(umdobject=schunit)';

my $attributes = \@ARGV;

$attributes = [ qw( businesscategory title ) ] unless @{$attributes};

my $ldap = Net::LDAP->new( $ldap_uri , debug => 0 ) or die $!;

my $mesg = $ldap->bind( $bind_dn , password=>$bind_passwd );
$mesg->code && die $mesg->error; #just to make sure everything went ok

while(<>) {
	chomp;
	my ($dn,$framed,$delegated) = split("\t");	
	#exit;
	$mesg = $ldap->modify( $dn , replace => { FramedIPv6Prefix => $framed, DelegatedIPv6Prefix => $delegated, } );
	$mesg->code && die $mesg->error;
	exit;
}



###$mesg = $ldap->search( 
###	base => $search_base, 
###	scope => 'sub',
###	attrs=> $attributes, 
###	filter => $filter, #or should it be objectclass=gsnUnit ? 
###	raw => qr/(?i:^jpegPhoto|;binary)/,
###); 
###$mesg->code && die $mesg->error;
###
###
###my $data;
###
###foreach my $entry ($mesg->entries) { 
###	my $ret;
###	for my $attr ($entry->attributes) {
###		#push @{ $ret->{lc($attr)} },map { decode('utf8',$_) } ( $entry->get_value($attr) );		
###		push @{ $ret->{lc($attr)} }, $entry->get_value($attr) ;		
###	}	
###	$data->{ $entry->dn } = $ret;
###}
###
###DumpFile($output,$data);
###
###$mesg = $ldap->unbind;
###$mesg->code && die $mesg->error;
###
