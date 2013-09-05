#!/usr/bin/env perl

###########################################################################
##
##         FILE: delete-done-articles.pl
##
##        USAGE: ./delete-done-articles.pl -c checkwiki.cfg
##
##  DESCRIPTION: Deletes articles from the database that have been fixed.
##
##       AUTHOR: Stefan Kühn, Bryan White
##      LICENCE: GPLv3
##      VERSION: 08/15/2013
##
###########################################################################

use strict;
use warnings;

use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);

binmode( STDOUT, ":encoding(UTF-8)" );

our @Projects;

#Database configuration
our $DbName;
our $DbServer;
our $DbUsername;
our $DbPassword;
our $dbh;

##########################################################################
## MAIN PROGRAM
##########################################################################

my @Options = (
    'database|d=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
);

GetOptions(
    'c=s' => sub {
        my $f = IO::File->new( $_[1], '<' )
          or die( "Can't open " . $_[1] . "\n" );
        local ($/);
        my $s = <$f>;
        $f->close();
        my ( $Success, $RemainingArgs ) = GetOptionsFromString( $s, @Options );
        die unless ( $Success && !@$RemainingArgs );
    }
);

#--------------------

open_db();
get_projects();

foreach (@Projects) {
    delete_done_article_from_db($_);
}

close_db();

##########################################################################
## OPEN DATABASE
##########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : q{} ),
        $DbUsername,
        $DbPassword,
        {
            RaiseError        => 1,
            AutoCommit        => 1,
            mysql_enable_utf8 => 1
        }
    ) or die( "Could not connect to database: " . DBI::errstr() . "\n" );

    return ();
}

###########################################################################
## CLOSE DATABASE
###########################################################################

sub close_db {
    $dbh->disconnect();

    return ();
}

###########################################################################
## GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
###########################################################################

sub get_projects {

    my $result = q();
    my $sth = $dbh->prepare('SELECT project FROM cw_project ORDER BY project;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {

        foreach (@$arrayref) {
            $result = $_;
        }

        push( @Projects, $result );
    }

    return ();
}

###########################################################################
## DELETE "DONE" ARTICLES FROM DB
###########################################################################

sub delete_done_article_from_db {
    my ($project) = @_;

    my $sth =
      $dbh->prepare('DELETE FROM cw_error WHERE ok = 1 and project = ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    return ();
}
