#!perl -w
# vim: ft=perl

use Test::More;
use DBI;
use DBI::Const::GetInfoType;
use strict;

use vars qw($test_dsn $test_user $test_password);
use lib 't', '.';
require 'lib.pl';

my @common_safe_methods = qw/
can                    err   errstr    parse_trace_flag    parse_trace_flags
private_attribute_info trace trace_msg visit_child_handles
/;

my @db_safe_methods   = (@common_safe_methods, qw/
clone mysql_async_ready
/);

my @db_unsafe_methods = qw/
data_sources       do                 last_insert_id     selectrow_array
selectrow_arrayref selectrow_hashref  selectall_arrayref selectall_hashref
selectcol_arrayref prepare            prepare_cached     commit
rollback           begin_work         disconnect         ping
get_info           table_info         column_info        primary_key_info
primary_key        foreign_key_info   statistics_info    tables
type_info_all      type_info          quote              quote_identifier 
/;

my @st_safe_methods   = qw/
fetchrow_arrayref fetch            fetchrow_array fetchrow_hashref
fetchall_arrayref fetchall_hashref finish         rows
/;

my @st_unsafe_methods = qw/
bind_param bind_param_inout bind_param_array execute execute_array
execute_for_fetch bind_col bind_columns
/;

my %dbh_args = (
    can                 => ['can'],
    parse_trace_flag    => ['SQL'],
    parse_trace_flags   => ['SQL'],
    trace_msg           => ['message'],
    visit_child_handles => [sub { }],
    quote               => ['string'],
    quote_identifier    => ['Users'],
    do                  => ['SELECT 1'],
    last_insert_id      => [undef, undef, undef, undef],
    selectrow_array     => ['SELECT 1'],
    selectrow_arrayref  => ['SELECT 1'],
    selectrow_hashref   => ['SELECT 1'],
    selectall_arrayref  => ['SELECT 1'],
    selectall_hashref   => ['SELECT 1', '1'],
    selectcol_arrayref  => ['SELECT 1'],
    prepare             => ['SELECT 1'],
    prepare_cached      => ['SELECT 1'],
    get_info            => [$GetInfoType{'SQL_DBMS_NAME'}],
    column_info         => [undef, undef, '%', '%'],
    primary_key_info    => [undef, undef, 'async_test'],
    primary_key         => [undef, undef, 'async_test'],
    foreign_key_info    => [undef, undef, 'async_test', undef, undef, undef],
    statistics_info     => [undef, undef, 'async_test', 0, 1],
);

my %sth_args = (
    fetchall_hashref => [1],
);

my $dbh;
eval {$dbh= DBI->connect($test_dsn, $test_user, $test_password,
                      { RaiseError => 0, PrintError => 0, AutoCommit => 0 });};

unless($dbh) {
    plan skip_all => "ERROR: $DBI::errstr Can't continue test";
}
unless($dbh->get_info($GetInfoType{'SQL_ASYNC_MODE'})) {
    plan skip_all => "Async support wasn't built into this version of DBD::mysql";
}
plan tests => 
  2 * @db_safe_methods   +
  2 * @db_unsafe_methods +
  2 * @st_safe_methods   +
  3;

$dbh->do(<<SQL);
CREATE TEMPORARY TABLE async_test (
    value INTEGER
)
SQL

foreach my $method (@db_safe_methods) {
    $dbh->do('SELECT 1', { async => 1 });
    my $args = $dbh_args{$method} || [];
    $dbh->$method(@$args);
    ok !$dbh->errstr, "Testing method '$method' on DBD::mysql::db during asynchronous operation";

    ok defined($dbh->mysql_async_result);
}

$dbh->do('SELECT 1', { async => 1 });
ok defined($dbh->mysql_async_result);

foreach my $method (@db_unsafe_methods) {
    $dbh->do('SELECT 1', { async => 1 });
    my $args = $dbh_args{$method} || [];
    my @values = $dbh->$method(@$args); # some methods complain unless they're called in list context
    like $dbh->errstr, qr/Calling a synchronous function on an asynchronous handle/, "Testing method '$method' on DBD::mysql::db during asynchronous operation";

    ok defined($dbh->mysql_async_result);
}

## try common_safe_methods on sth
## check these during an async operation on a DBH
## what about checking DBH methods during an STH operation?
foreach my $method (@st_safe_methods) {
    my $sth = $dbh->prepare('SELECT 1', { async => 1 });
    $sth->execute;
    my $args = $sth_args{$method} || [];
    diag "Testing method '$method'";
    $sth->$method(@$args);
    ok !$sth->errstr, "Testing method '$method' on DBD::mysql::st during asynchronous operation";

    # statement safe methods clear async state
    ok !defined($sth->mysql_async_result), "Testing DBD::mysql::st method '$method' clears async state";
}

my $sth = $dbh->prepare('SELECT 1', { async => 1 });
$sth->execute;
ok defined($sth->mysql_async_ready);
ok $sth->mysql_async_result;

$dbh->disconnect;