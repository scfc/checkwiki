#!/usr/bin/perl -T

###########################################################################
##
##         FILE: checkwiki_bots.pl
##
##        USAGE: ./checkwiki_bots.pl
##
##  DESCRIPTION: Method for WikipediaCleaner tor retrieve articles
##
##       AUTHOR: Stefan Kühn, Nicolas Vervelle, Bryan White
##      LICENCE: GPLv3
##      VERSION: 08/01/2013
##
###########################################################################

use strict;
use warnings;

use CGI qw(:standard);
use DBI;

our $MAX_LIMIT = 500;

###########################################################################
## GET PARAMETERS FROM CGI
###########################################################################

our $param_project = param('project');    # Project
our $param_action  = param('action');     # Action requested: list, mark
our $param_id      = param('id');         # Error number requested
our $param_offset  = param('offset');     # Offset for the list of articles
our $param_limit   = param('limit');      # Limit number of articles in the list
our $param_title   = param('title');      # Article title

$param_project = q{} unless defined $param_project;
$param_action  = q{} unless defined $param_action;
$param_id      = q{} unless defined $param_id;
$param_offset  = q{} unless defined $param_offset;
$param_limit   = q{} unless defined $param_limit;
$param_title   = q{} unless defined $param_title;

if ( $param_offset =~ /^[0-9]+$/ ) { }
else {
    $param_offset = 0;
}

if ( $param_limit =~ /^[0-9]+$/ ) { }
else {
    $param_limit = 25;
}

if ( $param_limit > $MAX_LIMIT ) {
     $param_limit = $MAX_LIMIT;
}

##########################################################################
## MAIN PROGRAM
##########################################################################

# List articles
if (    $param_project ne q{}
    and $param_action  eq 'list'
    and $param_id      =~ /^[0-9]+$/ )
{
    list_articles();
}

# Mark error as fixed
elsif ( $param_project ne q{}
    and $param_action  eq 'mark'
    and $param_id      =~ /^[0-9]+$/
    and $param_title   ne q{} )
{
    mark_article_done();
}
else {
    show_usage();
}

##########################################################################
## LIST ARTICLES
##########################################################################

sub list_articles {
    my $dbh = connect_database();

    print "Content-type: text/text;charset=UTF-8\n\n";

    my $sql_text =
        "SELECT title FROM cw_error WHERE error = "
      . $param_id
      . " AND project = '"
      . $param_project
      . "' AND ok=0 LIMIT "
      . $param_offset . ","
      . $param_limit . ";";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my $title_sql;
    $sth->bind_col( 1, \$title_sql );

    while ( $sth->fetchrow_arrayref ) {
        print 'title=' . $title_sql . "\n";
    }

    return ();
}

##########################################################################
## MARK ARTICLE AS DONE
##########################################################################

sub mark_article_done {
    my $dbh = connect_database();

    my $sql_text =
        "UPDATE cw_error SET ok=1 WHERE title="
      . $param_title
      . " AND error="
      . $param_id
      . " AND project = '"
      . $param_project . "';";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    print "Content-type: text/text\n\n";
    print 'Article ' . $param_title . ' has been marked as done.';

    return ();
}

##########################################################################
##  SHOW SCRIPT USAGE
##########################################################################

sub show_usage {

    print "Content-type: text/text\n\n";
    print "This script can be used with the following parameters:\n";
    print "  project=  : name of the project (enwiki, ...)\n";
    print "  id=       : Error number (04, 10, 80, ...)\n";
    print "  title=    : title of the article that has been fixed\n";
    print "  action=   : action requested, among the following values:\n";
    print "    list: list articles for the given improvement. The following parameters can also be used:\n";
    print "    mark: mark an article as fixed for the given improvement. The following parameters can also be used:\n";
    print "  offset=   : offset in the list of articles\n";
    print "  limit=    : maximum number of articles in the list\n";

    return ();
}

##########################################################################
##  CONNECT TO THE DATABASE
##########################################################################

sub connect_database {

    my ( $dbh, $dsn, $user, $password );

    $dsn =
"DBI:mysql:p50380g50450__checkwiki_p:tools-db;mysql_read_default_file=../replica.my.cnf";
    $dbh = DBI->connect(
        $dsn, $user,
        $password,
        {
            RaiseError        => 1,
            AutoCommit        => 1,
            mysql_enable_utf8 => 1,
        }
    ) or die( "Could not connect to database: " . DBI::errstr() . "\n" );

    return ($dbh);
}
