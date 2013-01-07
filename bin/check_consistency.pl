#!/usr/bin/perl -w

use warnings;
use strict;
use Carp;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use IPv6::Static;
use Time::HiRes qw(time);
use List::Util qw(sum);
use Getopt::Long;
use Term::ReadKey;
use Term::ReadLine;
use Pod::Usage;
use DBHelper;

my $fix = 0;
my $group = '';
my $max_addr;

my $DEBUG = 0;

my $help;

db_getoptions('help|?' => \$help, 'd' => \$DEBUG , 'fix'=>\$fix,'group=s'=>\$group,'max=i'=>\$max_addr,);

pod2usage(1) if $help;

my $dbh = db_connect; 


my $group_ref = IPv6::Static::get_group($dbh,$group);
my $group_id = $group_ref->{id};
my $group_limit = $group_ref->{limit};

$max_addr = (defined($max_addr))? $max_addr : $group_limit ;


for(0..($max_addr-1)) {
	my $record = IPv6::Static::get_address_record($dbh,$group_id,$_);#careful! this query is not indexed...
	if( ! defined($record) ) {
		print "Missing: Record with address number:\t$_ is missing";
		if ($fix) {
			print "...fixing";
			IPv6::Static::lock_tables($dbh);
			IPv6::Static::create_new_record($dbh,$group_id,'anonymous person'.$_,$_);
			IPv6::Static::set_in_use_user($dbh,$group_id,'anonymous person'.$_,0);
			IPv6::Static::unlock_tables($dbh);
		}
		print "\n";
	}
	else {
		$DEBUG && print STDERR 'OK: Record '.IPv6::Static::record2str($record)."\n";
	}
}

my $sth = $dbh->prepare('SELECT * FROM '.IPv6::Static::Settings::TABLE.' WHERE group_id=? AND address>?') or confess $dbh->errstr;
$sth->execute($group_id,$max_addr) or confess $dbh->errstr;
while( my $record = $sth->fetchrow_hashref ) {
	print "Record found beyond $max_addr limit: ".IPv6::Static::record2str($record)."\n";
}


__END__

=head1 NAME

check_consistency.pl -- check ipv6 prefix database consistency

=head1 SYNOPSIS

 check_consistency.pl [ options ]

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-d>

Enable more verbose output

=item B<-fix>

Actually fix whatever errors are encountered. Without this option,
the program will not make no changes whatsoever to the database.

=item B<-group>

Check items belonging to this specific group. Omitting this option 
will select a default '' group. So it is probably pointless to run this
program without supplying the group. 

=item B<-max>

Check all items up to this numeric index. Omitting this option will
cause the program to calculate and use the default group maximum index.

=item B<-host|-h> 

Connect to mysql on this hostname.

=item B<-user|-u>

Use this mysql username when connecting.

=item B<-p|-password>

Use this mysql password when connecting.

=item B<-db> 

Use this database when connecting.

=back

=head1 DESCRIPTION

Checks consistency of a static address database. 

=cut
