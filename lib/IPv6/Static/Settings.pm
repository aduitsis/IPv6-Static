package IPv6::Static::Settings;
use strict;
use warnings;

require Exporter;
use base 'Exporter';
our @EXPORT_OK = qw(GROUPS TABLE LOG_TABLE JOURNAL_TABLE IN_USE_WHERE IN_USE_SET W SLACK ENABLE_SLACK WARRANTY DOUBLE_LOGIN_CHECK_LEVEL);

use constant GROUPS => { some_group => { id=> 1, limit => 2000 } };
use constant TABLE => 'ipv6_static';
use constant JOURNAL_TABLE => '';
use constant LOG_TABLE => 'ipv6_log';
use constant W => 60; #period in seconds over which the statistics are calculated 
use constant SLACK => 3600; #update changetime only if it is older than SLACK seconds
use constant ENABLE_SLACK => 1;

#in case the in_use attribute is actually implemented, this constant should be like:
use constant IN_USE_WHERE => ' AND in_use=0 ';
use constant IN_USE_SET => ' , in_use=1 ';
#if the attribute is not used, then set these constants to ''

# no record newer than WARRANTY should be deleted
# to deactivate, just set WARRANTY => '';
use constant WARRANTY => 'AND UNIX_TIMESTAMP()-UNIX_TIMESTAMP(changetime) >= 10 ';

# check for double logins every time a user tries to authenticate 
# this check is based on whether the in_use flag is true.
# if the in_use flag is 1, then if DOUBLE_LOGIN_CHECK_LEVEL is :
# 	set to 2, the code will die() and not return an address
# 	set to 1, a warning will be emitted but the address will be returned normally
# 	set to 0, no double login check takes place
use constant DOUBLE_LOGIN_CHECK_LEVEL => 1;


1;
