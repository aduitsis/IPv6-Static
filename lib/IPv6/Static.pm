package IPv6::Static;

use warnings;
use strict;
use DBI;
use Carp;
use Time::HiRes qw(time);

use IPv6::Static::Settings qw(GROUPS TABLE LOG_TABLE JOURNAL_TABLE IN_USE_WHERE IN_USE_SET W SLACK ENABLE_SLACK WARRANTY DOUBLE_LOGIN_CHECK_LEVEL);
 
require Exporter;
use base 'Exporter';
our @EXPORT_OK = qw();

our %stats;

=over 4

=item B<update_stat ($name,$value)>

Takes a key and a numeric value, calculates an exponential moving average 
over a period of W. W is defined in IPv6::Static::Settings and is a numeric 
value in seconds over which the moving average is calculated.

=cut

sub update_stat {
	defined( my $name = shift )  or confess 'incorrect call';
	defined( my $value = shift )  or confess 'incorrect call';

	if ( ! exists( $stats{$name} ) ) {
		$stats{$name}->{previous_time} = time;
		$stats{$name}->{average} = $value; # we initialize the average to the first observation 
		$stats{$name}->{counter} = 0; # we initialize the counter to (what else?) zero
	} 
	else {
		my $now = time;
		my $delta_t = $now - $stats{$name}->{previous_time} ;
		$stats{$name}->{previous_time} = $now;
		my $a = ( 1 - exp( - $delta_t / W ) );
		# we use an exponential moving average and a which is a function of delta_t
		# see http://en.wikipedia.org/wiki/Moving_average#Application_to_measuring_computer_performance
		$stats{$name}->{average} = $a * $value   +   ( 1 - $a ) * $stats{$name}->{average} ; 
		$stats{$name}->{counter} ++ ;
	}
	return;
}
	

=item B<get_group ($group_name)>

Utility function, takes in a group name, returns a unique number for that group.
Current implementation based on a constant from IPv6::Static::Settings.
In the future, implement using a database as necessary

=cut 

sub get_group {
	return GROUPS->{$_[0]} if exists(GROUPS->{$_[0]});
	confess 'invalid group $_[0] requested';
}

=item B<get_user_record ($dbh,$group_id,$username)>

Returns the user record with group_id and username, if it exists. If not, undef is returned.

=cut 

sub get_user_record {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';

	my $t1 = time;
	my $sth = $dbh->prepare('SELECT *,UNIX_TIMESTAMP()-UNIX_TIMESTAMP(changetime) as slack FROM '.TABLE.' WHERE group_id=? AND username=?') or confess $dbh->errstr;
	$sth->execute($group_id,$username) or confess $sth->errstr;
	my $dt = time - $t1;
	update_stat('get user record query',$dt);
	update_stat('all queries',$dt);
	
	return $sth->fetchrow_hashref; 
}

=item B<get_address_record ($dbh,$group_id,$address)>

This sub is used by consistency checks only. 

=cut

sub get_address_record {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';
	defined( my $address = shift ) or confess 'incorrect call';

	my $t1 = time;
	my $sth = $dbh->prepare('SELECT * FROM '.TABLE.' WHERE group_id=? AND address=?') or confess $dbh->errstr;
	$sth->execute($group_id,$address) or confess $sth->errstr;
	my $dt = time - $t1;
	update_stat('get address record query',$dt);
	update_stat('all queries',$dt);
	return $sth->fetchrow_hashref; 
}

sub get_record_count {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';

	my $t1 = time;
	my $sth = $dbh->prepare('SELECT * FROM '.TABLE.' WHERE group_id=? ORDER BY address DESC LIMIT 1') or confess $dbh->errstr;
	$sth->execute($group_id) or confess $sth->errstr;

	my $dt = time - $t1;
	update_stat('get record count query',$dt);
	update_stat('all queries',$dt);

	my $result = $sth->fetchrow_hashref;
	if( ! defined($result) ) {
		return 0;
	} 
	else {
		return $result->{address} + 1;
	}	
}	

sub create_new_record {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';
	defined( my $address = shift ) or confess 'incorrect call';

	my $t1 = time;

	my $sth = $dbh->prepare('INSERT INTO '.TABLE.' SET group_id=? , username=? , address = ? , createtime=NOW() ') or confess $dbh->errstr;
	$sth->execute($group_id,$username,$address) or confess $sth->errstr;

	my $dt = time - $t1;
	update_stat('create new record query',$dt);
	update_stat('all queries',$dt);

	return;
}

=item B<update_record> ($dbh,$group_id,$old_username,$new_username)

Changes the record with username=$old_username to $new_username. 
Creatime is updated, since this is a "new" record as well as changetime
which is updated automatically by the db. If the IN_USE_SET is set
appropriately, the in_use field will be set to 1 as well. 

=cut

sub update_record {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';
	defined( my $old_username = shift ) or confess 'incorrect call';
	defined( my $new_username = shift ) or confess 'icorrect call';

	my $t1 = time;

	#changetime will be updated automatically by the database
	my $sth = $dbh->prepare('UPDATE '.TABLE.' SET username=?, createtime=NOW()'. IN_USE_SET .'  WHERE group_id=? AND username=?') or confess $dbh->errstr;
	$sth->execute($new_username,$group_id,$old_username) or confess $sth->errstr;

	my $dt = time - $t1;
	update_stat('update record query',$dt);
	update_stat('all queries',$dt);

	return;
}

sub find_oldest_record {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';

	my $t1 = time;
	
	my $sth = $dbh->prepare('SELECT * FROM '.TABLE.' WHERE group_id=? ' . IN_USE_WHERE . WARRANTY . 'ORDER BY changetime ASC LIMIT 1') or confess $dbh->errstr;
	$sth->execute($group_id) or confess $sth->errstr;

	my $dt = time - $t1;
	update_stat('find oldest record query',$dt);
	update_stat('all queries',$dt);

	my $result = $sth->fetchrow_hashref;
	if( ! defined($result) ) {
		confess 'No records at all in the database !'; 
	}
	else {
		return $result; 
	}	
}

=item B<refresh_record ($dbh, $group_id, $username)>

Updates the record with the group_id,username pair. The update sets the changetime to the current
timestamp and, B<may> do something to the in_use field depending on the IN_USE_SET constant. I.e. if
IN_USE_SET==',in_use=1' the field will be set to 1 (true).

=cut

sub refresh_record {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';

	my $t1 = time;


	my $sth = $dbh->prepare('UPDATE '.TABLE.' SET changetime=NOW()'. IN_USE_SET . ' WHERE group_id=? AND username=?') or confess $dbh->errstr;
	$sth->execute($group_id,$username) or confess $sth->errstr;

	my $dt = time - $t1;
	update_stat('refresh record query',$dt);
	update_stat('all queries',$dt);

	return;
}	

sub dump_record {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';

	my $t1 = time;

	my $sth = $dbh->prepare('SELECT * FROM '.TABLE.' WHERE group_id=? AND username=?') or confess $dbh->errstr;
	$sth->execute($group_id,$username) or confess $sth->errstr;

	my $dt = time - $t1;
	update_stat('dump record query',$dt);
	update_stat('all queries',$dt);

	my $result = $sth->fetchrow_hashref; 
	if( ! defined($result) ) {
		return;
	}
	else {
		return $result;
	}
}

sub set_in_use_user {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';
	defined( my $in_use = shift ) or confess 'incorrect call';

	my $t1 = time;

	my $sth = $dbh->prepare('UPDATE '.TABLE.' SET in_use=? WHERE group_id=? AND username=?') or confess $dbh->errstr;
	$sth->execute($in_use,$group_id,$username) or confess $sth->errstr;

	my $dt = time - $t1;
	update_stat('update in_use query',$dt);
	update_stat('all queries',$dt);
	
	return;
}

sub set_in_use_user_quick {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';
	defined( my $in_use = shift ) or confess 'incorrect call';

	my $t1 = time;

	my $sth = $dbh->prepare('UPDATE '.TABLE.' SET in_use=? WHERE username=?') or confess $dbh->errstr;
	$sth->execute($in_use,$group_id,$username) or confess $sth->errstr;

	my $dt = time - $t1;
	update_stat('QUICK update in_use query',$dt);
	update_stat('all queries',$dt);
	
	return;
}
	

sub record2str {
	defined( my $record = shift ) or confess 'incorrect call';
	if(defined($record)) { 
		return join(',',map { $_.'='.$record->{$_} } (sort keys %{$record}) );
	} 
	else {
		return 'empty record';
	}
}

sub journal_entry {
	return unless JOURNAL_TABLE;
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';
	defined( my $address = shift ) or confess 'incorrect call';
	defined( my $end = shift ) or confess 'incorrect call';

	my $t1 = time;

	my $sth = $dbh->prepare('INSERT INTO '.JOURNAL_TABLE.' SET group_id=? , username=? , address=? , end=?') or confess $dbh->errstr;
	$sth->execute($group_id,$username,$address,$end) or confess $sth->errstr;

	my $dt = time - $t1;
	update_stat('journal entry query',$dt);
	update_stat('all queries',$dt);

	return;
}	

sub log_entry {
	return unless LOG_TABLE;
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_id = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';
	defined( my $address = shift ) or confess 'incorrect call';
	defined( my $starttime = shift ) or confess 'incorrect call';

	my $t1 = time;

	my $sth = $dbh->prepare('INSERT INTO '.LOG_TABLE.' SET group_id=? , username=? , address=? , starttime=?, stoptime=NOW()') or confess $dbh->errstr;
	$sth->execute($group_id,$username,$address,$starttime) or confess $sth->errstr;

	my $dt = time - $t1;
	update_stat('log entry query',$dt);
	update_stat('all queries',$dt);

	return;
}	

sub lock_tables {
	defined( my $dbh = shift ) or confess 'incorrect call';
	#$dbh->do('LOCK TABLES '.TABLE.' WRITE, '.LOG_TABLE.' WRITE') or confess $dbh->errstr;
	$dbh->do('LOCK TABLES '.TABLE.' WRITE') or confess $dbh->errstr;
}

sub unlock_tables {
	defined( my $dbh = shift ) or confess 'incorrect call';
	$dbh->do('UNLOCK TABLES') or confess $dbh->errstr; 
}


=item B<handle_user_logout ($dbh,$group_name,$username)>

Handles the event of a user logout. It should only be used in the case where 
the is_use field is actually used. Otherwise, it is not required to call this
function at all. 

=cut

sub handle_user_logout {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_name = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';

	# setup a logger
	my $logger = IPv6::Static::Logger->new('DEBUG');

	my $t1 = time;
	
	my $group_id = get_group($group_name)->{id};

	if(! defined( $group_id ) ) {
		confess "no group id for $group_name";
	}

	if(IN_USE_SET) { # this is called only if the IS_USE_SET is evaluated to true
		if( defined( my $user_record = get_user_record($dbh, $group_id, $username) ) ) {
			$logger->debug('about to logout record: '.record2str($user_record) );
			if( $user_record->{in_use} == 0 ) { 
				confess 'user already logged out. Log was: '.$logger->to_string;
			}
			else {
				$logger->info('Setting in_use=0 for: '.record2str($user_record) );
				set_in_use_user($dbh,$group_id,$username,0);

				my $dt = time - $t1;
				update_stat('user logout path',$dt);

				return { record => $user_record , logger => $logger };
			}
		}
		else {
			confess "User $username of $group_name does not exist in our records";
		}
	}
	else {
		confess 'handle_user_logout is not really needed since IN_USE_SET evaluates to false';
	}
	confess 'I should not had made it here';
	
}

=item B<handle_user_logout_quick ($dbh,$group_name,$username)>

The _quick version just nukes the in_use field to 0 blindly. B<It also assumes 
that each username is unique, regardless of group.>
Please use the C<handle_user_logout> proper unless you really do not want to 
know about errors and you are really certain that each username is unique
in your problem domain regardless of group.

=cut

sub handle_user_logout_quick {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_name = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';

	# setup a logger
	my $logger = IPv6::Static::Logger->new('DEBUG');

	my $t1 = time;
	
	set_in_use_user_quick($dbh,$username,0);
	my $dt = time - $t1;
	update_stat('QUICK user logout path',$dt);	

	return;	
}

sub handle_user_login {
	defined( my $dbh = shift ) or confess 'incorrect call';
	defined( my $group_name = shift ) or confess 'incorrect call';
	defined( my $username = shift ) or confess 'incorrect call';

	# setup a logger
	my $logger = IPv6::Static::Logger->new('DEBUG');

	my $t1 = time;
	
	my $group_id = get_group($group_name)->{id};

	if(! defined( $group_id ) ) {
		confess "no group id for $group_name";
	}

	#first of all, we lock completely so that nodody else reads or writes while we work
	lock_tables($dbh);

	if( defined( my $user_record = get_user_record($dbh, $group_id, $username) ) ) {

		#check for double logins
		if(IN_USE_WHERE) { #only needed if we check the value of in_use 
			if( $user_record->{in_use} == 1 ) { 
				if( DOUBLE_LOGIN_CHECK_LEVEL == 2 ) {
					confess 'Double login: '.record2str($user_record).' log was: '.$logger->to_string;
				}
				elsif( DOUBLE_LOGIN_CHECK_LEVEL == 1 ) {
					$logger->warn('Double login (but I will continue): '.record2str($user_record));
				} 
					
			} 
		}

		if(IN_USE_SET) { #update in_use all the time
			refresh_record($dbh, $group_id, $username);
			$logger->info('refreshed '.record2str($user_record));
		}
		elsif( ENABLE_SLACK && ( SLACK < $user_record->{slack} ) ) { #update record, but not too often
			refresh_record($dbh, $group_id, $username); #update the changetime 
			$logger->info('refreshed '.record2str($user_record));
		} 
		else { 
			$logger->info('no need to refresh yet: '.record2str($user_record));
		}

		# now the table can be unlocked
		unlock_tables($dbh);

		my $dt = time - $t1;
		update_stat('get existing record login path',$dt);

		return { record => $user_record , logger => $logger } ;

	} 
	else {
		#at this point we have decided that we don't have an address to give
		$logger->info("No record found for $username of $group_name");

		#so, we'll do some changes to the database

		#find the number of addresses in the database, addresses are from 0...n-1, we get n
		my $next_address = get_record_count($dbh,$group_id);

		#if we have reached the limit
		if( get_group($group_name)->{limit} <= $next_address ) {
			$logger->info("Limit $next_address for $group_name reached. Reusing an old record");
			#find the oldest row in the tabe	
			my $old_record = find_oldest_record($dbh,$group_id);	
			confess 'ERROR! we should have been able to find at least one record!' unless(defined($old_record));

			$logger->info('record to be updated: ' . record2str($old_record));
			# MAJOR WARNING: update_record has a (intentional) side-effect, it sets in_use = 1
			update_record($dbh,$group_id,$old_record->{username},$username);


			#if we were extra confident, we could just return now ... 
			#but, we are not. So here is a more careful verification that everything went ok
			if( defined( my $new_record = get_user_record($dbh, $group_id, $username) ) ) {
				unlock_tables($dbh);

				#make sure that we updated the correct record!
				if ( $old_record->{address} != $new_record->{address} ) {
					confess 'ERROR! old record:'.record2str($old_record).' and new record:'.record2str($new_record).' should have the same address. Log was: '.$logger->to_string;
				}
				$logger->info('replace successful, new record is '.record2str($new_record));

				#close the old record's journal entry
				journal_entry($dbh,$group_id,$old_record->{username},$old_record->{address},1);
				#and open a new journal entry
				journal_entry($dbh,$group_id,$username,$old_record->{address},0);

				#create a log entry for the row that was changed
				log_entry($dbh,$group_id,$username,$old_record->{address},$old_record->{createtime});

				my $dt = time - $t1;
				update_stat('update record login path',$dt);

				return { record => $new_record , logger => $logger };
			}
			else {
				unlock_tables($dbh);
				confess "ERROR! Just created a new record for $username of $group_name and next it wasn't there. Log was: ".$logger->to_string;
			}
				
		} 	
		else { #create a new row
			$logger->info("next free address is $next_address, will create a record for it");	

			create_new_record($dbh,$group_id,$username,$next_address);
			# remember, the table has a in_use = 1 default for all new records. 
			
			if( defined( my $user_record = get_user_record($dbh, $group_id, $username) ) ) {
				unlock_tables($dbh);
				journal_entry($dbh,$group_id,$username,$user_record->{address},0);

				$logger->info('new record created: '.record2str($user_record));

				my $dt = time - $t1;
				update_stat('create record login path',$dt);

				return { record => $user_record , logger => $logger } ;
			}
			else {
				unlock_tables($dbh);
				confess "ERROR! Just created a new record for $username of $group_name and next moment it wasn't there. Log was: ".$logger->to_string;
			}
		}
		unlock_tables($dbh);
		confess 'Internal error! This line should had not been reached';
	}
	unlock_tables($dbh);
	confess 'Internal error! This line should had not been reached';
}

=back

=cut

package IPv6::Static::Logger;
use warnings;
use strict;
use Carp;

sub new {
	defined( my $class = shift ) or confess 'incorrect call';
	defined( my $level = shift ) or confess 'incorrect call';
	my $self = { msgs => [] };
	$self->{level} = ( $level eq 'DEBUG' )? 2 : ($level eq 'INFO')? 1 : 0; #anything other than DEBUG or INFO defaults to WARN
	return bless $self, $class;
}

sub msg_log {
	defined( my $self = shift ) or confess 'incorrect call';
	defined( my $level = shift ) or confess 'incorrect call';
	defined( my $msg = shift ) or confess 'incorrect call';
	my $str = "$level: $msg";
	####print STDERR $str . "\n";
	push @{ $self->{msgs} }, $str;
}

sub to_string { 
	return join( "\n", @{ $_[0]->{msgs} } ); 
}

sub warn {
	$_[0]->msg_log('WARNING',$_[1]) if($_[0]->{level} >= 0);
}

sub info {
	$_[0]->msg_log('INFO',$_[1]) if($_[0]->{level} >= 1);
}

sub debug {
	$_[0]->msg_log('DEBUG',$_[1]) if($_[0]->{level} >= 2);
}

1;
