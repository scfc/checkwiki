#! /usr/bin/perl -T

###########################################################################
#
# FILE:   checkwiki.cgi
# USAGE:
#
# DESCRIPTION:
#
# AUTHOR:  Stefan Kühn
# VERSION: 2013-07-28
# LICENSE: GPL
#
###########################################################################

use strict;
use warnings;
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use CGI::Carp qw(fatalsToBrowser set_message);    # CGI-Error
use Data::Dumper;
use DBI;

set_message(
    'There is a problem in the script. 
Send me a mail to (<a href="mailto:kuehn-s@gmx.net">kuehn-s@gmx.net</a>), 
giving this error message and the time and date of the error.',
);

our $VERSION = '2013-07-28';

our $script_name = 'checkwiki.cgi';

###########################################################################
## GET PARAMETERS FROM CGI
###########################################################################

our $param_view    = param('view');      # list, high, middle, low, only, detail
our $param_project = param('project');   # project
our $param_id      = param('id');        # id of improvment
our $param_title   = param('title');
our $param_offset  = param('offset');
our $param_limit   = param('limit');
our $param_orderby = param('orderby');
our $param_sort    = param('sort');
our $param_statistic = param('statistic');

$param_view      = q{} unless defined $param_view;
$param_project   = q{} unless defined $param_project;
$param_id        = q{} unless defined $param_id;
$param_title     = q{} unless defined $param_title;
$param_offset    = q{} unless defined $param_offset;
$param_limit     = q{} unless defined $param_limit;
$param_orderby   = q{} unless defined $param_orderby;
$param_sort      = q{} unless defined $param_sort;
$param_statistic = q{} unless defined $param_statistic;

#$param_view    = 'project';
#$param_project = 'enwiki';

if ( $param_offset =~ /^[0-9]+$/ ) { }
else {
    $param_offset = 0;
}

if ( $param_limit =~ /^[0-9]+$/ ) { }
else {
    $param_limit = 25;
}
$param_limit = 500 if ( $param_limit > 500 );
our $offset_lower  = $param_offset - $param_limit;
our $offset_higher = $param_offset + $param_limit;
$offset_lower = 0 if ( $offset_lower < 0 );
our $offset_end = $param_offset + $param_limit;

# Sorting
our $column_orderby = q{};
our $column_sort    = q{};
if ( $param_orderby ne '' ) {
    if (    $param_orderby ne 'article'
        and $param_orderby ne 'notice'
        and $param_orderby ne 'found'
        and $param_orderby ne 'more' )
    {
        $param_orderby = q{};
    }
}

if ( $param_sort ne '' ) {
    if (    $param_sort ne 'asc'
        and $param_sort ne 'desc' )
    {
        $column_sort = 'asc';
    }
    else {
        $column_sort = 'asc'  if ( $param_sort eq 'asc' );
        $column_sort = 'desc' if ( $param_sort eq 'desc' );
    }
}

###########################################################################
## OPEN DATABASE
###########################################################################

sub connect_database {

    my $dbh;
    my $dsn;
    my $user;
    my $password;

    $dsn =
"DBI:mysql:p50380g50450__checkwiki_p:tools-db;mysql_read_default_file=../replica.my.cnf";
    $dbh = DBI->connect( $dsn, $user, $password )
      or die( "Could not connect to database: " . DBI::errstr() . "\n" );

    return ($dbh);
}

##########################################################################
## BEGIN HTML FOR ALL PAGES
##########################################################################

our $lang = q{};
$lang = get_lang();

print "Content-type: text/html\n\n";
print
"<!DOCTYPE html>\n<head>\n<meta http-equiv=\"content-type\" content=\"text/html;charset=UTF-8\" />\n";
print '<title>Check Wikipedia</title>' . "\n";
print '<link rel="stylesheet" href="css/style.css" type="text/css" />' . "\n";
print get_style();
print '</head>' . "\n";
print '<body>' . "\n";
print '<h1>Check Wikipedia</h1>' . "\n" if ( $param_view ne 'bots' );

##########################################################################
## NO PARAMS ENTERED - SHOW STARTPAGE WITH OVERVIEW OF ALL PROJECTS
##########################################################################

if (    $param_project eq ''
    and $param_view      eq ''
    and $param_id        eq ''
    and $param_title     eq ''
    and $param_statistic eq '' )

{
    print redirect( -url => 'http://tools.wmflabs.org/checkwiki/index.htm' );
}

##########################################################################
## ONLY PROJECT PARAM ENTERED - SHOW PAGE FOR ONLY ONE PROJECT
##########################################################################

if (    $param_project ne ''
    and $param_view  eq 'project'
    and $param_id    eq ''
    and $param_title eq '' )
{
    print '<p>→ <a href="'
      . $script_name
      . '">Homepage</a> → '
      . $param_project . '</p>' . "\n";

    # local page, dump etc.
    print project_info($param_project);

    print
'<p><span style="font-size:10px;">This table will updated every 15 minutes.</span></p>'
      . "\n";
    print '<table class="table">';
    print
'<tr><th class="table">&nbsp;</th><th class="table">To-do</th><th class="table">Done</th></tr>'
      . "\n";
    print get_number_of_prio();
    print '</table>';

}

##########################################################################
## SHOW ALL ERRORS FOR ONE OR ALL PROJECTS
##########################################################################

if (
    $param_project ne ''
    and (  $param_view eq 'high'
        or $param_view eq 'middle'
        or $param_view eq 'low'
        or $param_view eq 'all' )
  )
{

    my $prio      = 0;
    my $headline  = q{};
    my $html_page = q{};
    if ( $param_view eq 'high' ) {
        $prio      = 1;
        $headline  = 'High priority';
        $html_page = 'priority_high.htm';
    }

    if ( $param_view eq 'middle' ) {
        $prio      = 2;
        $headline  = 'Middle priority';
        $html_page = 'priority_middle.htm';
    }

    if ( $param_view eq 'low' ) {
        $prio      = 3;
        $headline  = 'Low priority';
        $html_page = 'priority_low.htm';
    }

    if ( $param_view eq 'all' ) {
        $prio      = 0;
        $headline  = 'all priorities';
        $html_page = 'priority_all.htm';
    }

    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → '
      . $headline . '</p>' . "\n";
    print
'<p><span style="font-size:10px;">This table will updated every 15 minutes.</span></p>'
      . "\n";

    print get_number_error_and_desc_by_prio($prio);

}

##########################################################################
## LIST OF ALL ARTICLES WITH ERRORS SORTED BY NAME OR NUMBER OF ERRORS
##########################################################################

if (    $param_project ne ''
    and $param_view eq 'list' )
{

    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → List of articles</p>' . "\n";

    print '<p>At the moment this list is deactivated.</p>' . "\n";

    #print get_list();

}

##########################################################################
## SET AN ARTICLE AS HAVING AN ERROR DONE
##########################################################################

if (    $param_project ne ''
    and $param_view  =~ /^(detail|only)$/
    and $param_title =~ /^(.)+$/
    and $param_id    =~ /^[0-9]+$/ )
{
    my $dbh = connect_database();
    my $sql_text =
        "UPDATE cw_error SET ok=1 WHERE Title='"
      . $param_title
      . "' AND error="
      . $param_id
      . " AND project = '"
      . $param_project . "';";
    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";
}

###########################################################################
## SHOW ONE ERROR FOR ALL ARTICLES
###########################################################################

if (    $param_project ne ''
    and $param_view =~ /^only(done)?$/
    and $param_id   =~ /^[0-9]+$/ )
{

    my $headline = q{};
    $headline = get_headline($param_id);

    my $prio = get_prio_of_error($param_id);

    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=high">high priority</a>'
      if ( $prio eq '1' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=middle">middle priority</a>'
      if ( $prio eq '2' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=low">low priority</a>'
      if ( $prio eq '3' );

    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → '
      . $prio . ' → '
      . $headline . '</p>' . "\n";

    print '<p>' . get_description($param_id) . '</p>' . "\n";
    print '<p>To do: <b>' . get_number_of_error($param_id) . '</b>, ';
    print 'Done: <b>'
      . get_number_of_ok_of_error($param_id)
      . '</b> article(s) - ';
    print 'ID: ' . $param_id . ' - ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=bots&amp;id='
      . $param_id
      . '&amp;offset='
      . $offset_lower
      . '&amp;limit='
      . $param_limit
      . '">List for bots</a> - ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=alldone&amp;id='
      . $param_id
      . '">Set all articles as done!</a>';
    print '</p>' . "\n";

###########################################################################
## SHOW ONLY ONE ERROR WITH ALL ARTICLES
###########################################################################

    if ( $param_view =~ /^only$/ ) {
        print '<p><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=onlydone&amp;id='
          . $param_id
          . '">Show all done articles</a></p>';
        print get_article_of_error($param_id);
    }

###########################################################################
## SHOW ONLY ONE ERROR WITH ALL ARTICLES SET AS DONE
###########################################################################

    if ( $param_view =~ /^onlydone$/ ) {
        print '<p><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=only&amp;id='
          . $param_id
          . '">Show to-do-list</a></p>';
        print get_done_article_of_error($param_id);
    }

}

###########################################################################
## SHOW ONE ERROR WITH ALL ARTICLES FOR BOTS
###########################################################################

if (    $param_project ne ''
    and $param_view =~ /^bots$/
    and $param_id   =~ /^[0-9]+$/ )
{

    print get_article_of_error_for_bots($param_id);
}

################################################################

if (    $param_project ne ''
    and $param_view =~ /^alldone$/
    and $param_id   =~ /^[0-9]+$/ )
{
    # All article of an error set ok = 1
    my $headline = '';
    $headline = get_headline($param_id);

    #print '<h2>'.$param_project.' - '.$headline.'</h2>'."\n";
    my $prio = get_prio_of_error($param_id);

    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=high">high priority</a>'
      if ( $prio eq '1' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=middle">middle priority</a>'
      if ( $prio eq '2' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=low">low priority</a>'
      if ( $prio eq '3' );

    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → '
      . $prio . ' → '
      . $headline . '</p>' . "\n";

    print
'<p>You work with a bot or a tool like "AWB" or "WikiCleaner".</p><p>And now you want set all <b>'
      . get_number_of_error($param_id)
      . '</b> article(s) of id <b>'
      . $param_id
      . '</b> as <b>done</b>.</p>';

    print '<ul>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I will back!</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I want only try this link!</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I am not sure. I will go back.</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=alldone2&amp;id='
      . $param_id
      . '">Yes, I will set all <b>'
      . get_number_of_error($param_id)
      . '</b> article(s) as done.</a></li>' . "\n";
    print '</ul>' . "\n";
    print '';
}

################################################################

if (    $param_project ne ''
    and $param_view =~ /^alldone2$/
    and $param_id   =~ /^[0-9]+$/ )
{
    # All article of an error set ok = 1
    my $headline = '';
    $headline = get_headline($param_id);

    #print '<h2>'.$param_project.' - '.$headline.'</h2>'."\n";
    my $prio = get_prio_of_error($param_id);

    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=high">high priority</a>'
      if ( $prio eq '1' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=middle">middle priority</a>'
      if ( $prio eq '2' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=low">low priority</a>'
      if ( $prio eq '3' );

    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → '
      . $prio . ' → '
      . $headline . '</p>' . "\n";

    print
'<p>You work with a bot or a tool like "AWB" or "WikiCleaner".</p><p>And now you want set all <b>'
      . get_number_of_error($param_id)
      . '</b> article(s) of id <b>'
      . $param_id
      . '</b>. as <b>done</b>.</p>';

    print
'<p>If you set all articles as done, then only in the database the article will set as done. With the next scan all this articles will be scanned again. If the script found this idea for improvment again, then this article is again in this list.</p>';

    print
'<p>If you want stop this listing, then this is not the way. Please contact the author at the <a href=""bilder/de.wikipedia.org/wiki/Benutzer:Stefan_Kühn/Check_Wikipedia">projectpage</a> and discuss the problem there.</p>';

    print '<ul>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I will back!</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I want only try this link!</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I am not sure. I will go back.</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=alldone3&amp;id='
      . $param_id
      . '">Yes, I will set all <b>'
      . get_number_of_error($param_id)
      . '</b> article(s) as done.</a></li>' . "\n";
    print '</ul>' . "\n";
    print '';
}

################################################################
if (    $param_project ne ''
    and $param_view =~ /^alldone3$/
    and $param_id   =~ /^[0-9]+$/ )
{
    # All article of an error set ok = 1
    my $headline = '';
    $headline = get_headline($param_id);

    #print '<h2>'.$param_project.' - '.$headline.'</h2>'."\n";
    my $prio = get_prio_of_error($param_id);

    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=high">high priority</a>'
      if ( $prio eq '1' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=middle">middle priority</a>'
      if ( $prio eq '2' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=low">low priority</a>'
      if ( $prio eq '3' );

    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → '
      . $prio . ' → '
      . $headline . '</p>' . "\n";

    print '<p>All <b>'
      . get_number_of_error($param_id)
      . '</b> article(s) of id <b>'
      . $param_id
      . '</b>. were set as <b>done</b></p>';

    my $dbh = connect_database();
    my $sql_text =
        "update cw_error set ok = 1 where error="
      . $param_id
      . " and project = '"
      . $param_project . "';";
    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    print 'Back to ' . $prio . "\n";
}

################################################################
#
if (    $param_project ne ''
    and $param_view eq 'detail'
    and $param_title =~ /^(.)+$/ )
{
    # Details zu einem Artikel anzeigen
    #print '<h2>'.$param_project.' - Details</h2>'."\n";
    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=list">List</a> → Details</p>' . "\n";

    my $dbh = connect_database();
    my $sql_text =
        "select title from cw_error where Title='"
      . $param_title
      . "' and project = '"
      . $param_project
      . "' limit 1;";

    my $sth = $dbh->prepare($sql_text)
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            my $result = $_;
            $result = '' unless defined $result;
            if ( $result ne '' ) {
                print '<p>Artikel: <a target "_blank" href="'
                  . get_homepage($param_project)
                  . '/wiki/'
                  . $result . '">'
                  . $result
                  . '</a> - 
                     <a href="'
                  . get_homepage($param_project)
                  . '/w/index.php?title='
                  . $result
                  . '&amp;action=edit">edit</a></p>';
            }
        }
    }

    print get_all_error_of_article($param_title);

}

##############################################################

if (    $param_project eq ''
    and $param_statistic eq 'run' )
{
    print '<p>→ <a href="' . $script_name . '">Homepage</a> → Statistic';
    get_statistic_starter();

    # to-do:?
}

##############################################################
if ( $param_view ne 'bots' ) {

    print
      #'<p><span style="font-size:10px;"><a href="de.wikipedia.org/wiki/Benutzer:Stefan_Kühn/Check_Wikipedia">projectpage</a> ·
      #<a href="de.wikipedia.org/w/index.php?title=Benutzer_Diskussion:Stefan_K%C3%BChn/Check_Wikipedia&amp;action=edit&amp;section=new">comments and bugs</a><br />
      #	Version '
      '<p><span style="font-size:10px;">Version '
      . $VERSION
      . ' · license: <a href="www.gnu.org/copyleft/gpl.html">GPL</a> · Powered by <a href="tools.wikimedia.de/">Wikimedia Toolserver</a> </span></p>'
      . "\n";
}

print '</body>';
print '</html>';

####################################################################################################################
####################################################################################################################
####################################################################################################################
####################################################################################################################
####################################################################################################################

sub get_number_all_errors_over_all {
    my $dbh    = connect_database();
    my $result = 0;

    my $sth = $dbh->prepare('SELECT count(*) FROM cw_error WHERE ok=0;')
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            $result = $_;
            $result = '' unless defined $result;
        }
    }
    return ($result);
}

###########################################################################

sub get_number_of_ok_over_all {
    my $dbh    = connect_database();
    my $result = 0;

    my $sth = $dbh->prepare('SELECT count(*) FROM cw_error WHERE ok=1;')
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            $result = $_;
            $result = '' unless defined $result;
        }
    }
    return ($result);
}

###########################################################################

sub get_projects {
    my $result = q{};
    my $dbh    = connect_database();

    my $sth = $dbh->prepare(
'SELECT ID, Project, Errors, Done, Lang, Last_Update, DATE(Last_Dump), Project_Page, Translation_Page FROM cw_overview ORDER BY Project;'
    ) || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    $result .= '<table class="table">';
    $result .= '<tr>' . "\n";
    $result .= '<th class="table">#</th>' . "\n";
    $result .= '<th class="table">Project</th>' . "\n";
    $result .= '<th class="table">To-do</th>' . "\n";
    $result .= '<th class="table">Done</th>' . "\n";
    $result .= '<th class="table">Change to<br />yesterday</th>' . "\n";
    $result .= '<th class="table">Change to<br />last week</th>' . "\n";
    $result .= '<th class="table">Last dump</th>' . "\n";
    $result .= '<th class="table">Last update</th>' . "\n";
    $result .= '<th class="table">Page at Wikipedia</th>' . "\n";
    $result .= '<th class="table">Translation</th>' . "\n";
    $result .= '</tr>' . "\n";
    while ( my $h = $sth->fetchrow_hashref() ) {

        #use Data::Dumper;
        print "<!--" . ( Dumper( keys(%$h) ) ) . "-->";
        $result .= '<tr>' . "\n";
        $result .= '<td class="table">' . $h->{'ID'} . '</td>' . "\n";
        $result .=
            '<td class="table"><a href="'
          . $script_name
          . '?project='
          . $h->{'Project'}
          . '&amp;view=project" rel="nofollow">'
          . $h->{'Project'} . '</td>' . "\n";
        $result .= '<td class="table" align="right"  valign="middle">'
          . $h->{'Errors'} . '</td>' . "\n";
        $result .= '<td class="table" align="right"  valign="middle">'
          . $h->{'Done'} . '</td>' . "\n";

        #change
        $result .= '<td class="table" align="right"  valign="middle">' . 'dunno'
          . '</td>' . "\n";
        $result .= '<td class="table" align="right"  valign="middle">' . 'dunno'
          . '</td>' . "\n";

        #last dump
        $result .= '<td class="table" align="right"  valign="middle">'
          . $h->{'DATE(Last_Dump)'} . '</td>' . "\n";
        $result .= '<td class="table">' . $h->{'Last_Update'} . '</td>';
        $result .=
            '<td class="table" align="center"  valign="middle"><a href="'
          . $h->{'lang'}
          . '.wikipedia.org/wiki/'
          . $h->{'Project_Page'}
          . '">here</a></td>' . "\n";
        $result .=
            '<td class="table" align="center"  valign="middle"><a href="'
          . $h->{'lang'}
          . '.wikipedia.org/wiki/'
          . $h->{'Translation_Page'}
          . '">here</a></td>' . "\n";
        $result .= '</tr>' . "\n";

    }
    $result .= '</table>';
    return ($result);
}

###########################################################################

sub get_number_all_article {
    my $result = 0;
    my $dbh    = connect_database();

    my $sql_text =
"SELECT count(a.error_id) FROM (select error_id FROM cw_error WHERE ok=0 AND project = '"
      . $param_project
      . "' GROUP BY error_id) a;";

    my $sth = $dbh->prepare($sql_text)
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            $result = $_;
            $result = '' unless defined $result;
        }
    }

    return ($result);
}

###########################################################################

sub get_number_of_ok {
    my $result = 0;
    my $dbh    = connect_database();

    my $sql_text =
      "SELECT IFNULL(sum(done),0) FROM cw_overview_errors WHERE project = '"
      . $param_project . "';";

    my $sth = $dbh->prepare($sql_text)
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            $result = $_;
            $result = '' unless defined $result;
        }
    }

    return ($result);
}

###########################################################################

sub get_number_all_errors {
    my $result = 0;
    my $dbh    = connect_database();

    my $sql_text =
      "SELECT IFNULL(sum(errors),0) FROM cw_overview_errors WHERE project = '"
      . $param_project . "';";

    my $sth = $dbh->prepare($sql_text)
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            $result = $_;
            $result = '' unless defined $result;
        }
    }

    return ($result);
}

###########################################################################

sub get_number_of_error {

    # Anzahl gefundenen Vorkommen eines Fehlers
    my ($error) = @_;
    my $result  = 0;
    my $dbh     = connect_database();

    my $sql_text =
        "SELECT count(*) FROM cw_error WHERE ok=0 AND error = "
      . $error
      . " AND project = '"
      . $param_project . "';";

    my $sth = $dbh->prepare($sql_text)
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            $result = $_;
            $result = '' unless defined $result;
        }
    }

    return ($result);
}

###########################################################################

sub get_number_of_ok_of_error {

    # Anzahl gefundenen Vorkommen eines Fehlers
    my ($error) = @_;
    my $result  = 0;
    my $dbh     = connect_database();

    my $sql_text =
        "SELECT count(*) FROM cw_error WHERE ok=1 AND error = "
      . $error
      . " AND project = '"
      . $param_project . "';";

    my $sth = $dbh->prepare($sql_text)
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            $result = $_;
            $result = '' unless defined $result;
        }
    }

    return ($result);
}

###########################################################################
### GET PROJECT INFORMATION FOR PROJECT'S STARTPAGE
############################################################################

sub project_info {
    my ($project) = @_;
    my $result    = q{};
    my $dbh       = connect_database();
    my @info;

    my $sql_text = "SELECT project, 
    if(length(ifnull(wikipage,''))!=0,wikipage, 'no data') wikipage,
    if(length(ifnull(translation_page,''))!=0,translation_page, 'no data') translation_page,
    date_format(last_dump,'%Y-%m-%d') last_dump, 
    ifnull(DATEDIFF(curdate(),last_dump),'')
    FROM cw_project 
    WHERE project='" . $project . "' limit 1;";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my (
        $project_sql,  $wikipage_sql, $translation_sql,
        $lastdump_sql, $dumpdate_sql
    );
    $sth->bind_col( 1, \$project_sql );
    $sth->bind_col( 2, \$wikipage_sql );
    $sth->bind_col( 3, \$translation_sql );
    $sth->bind_col( 4, \$lastdump_sql );
    $sth->bind_col( 5, \$dumpdate_sql );

    $sth->fetchrow_arrayref;

    my $homepage              = get_homepage($project_sql);
    my $wikipage_sql_under    = $wikipage_sql;
    my $translation_sql_under = $translation_sql;
    $wikipage_sql_under    =~ tr/ /_/;
    $translation_sql_under =~ tr/ /_/;

    $result .= '<ul>' . "\n";
    $result .=
        '<li>Local page: '
      . '<a href="https://'
      . $homepage
      . '/wiki/'
      . $wikipage_sql_under . '">'
      . $wikipage_sql
      . '</a></li>' . "\n";
    $result .=
        '<li>Translation page: '
      . '<a href="https://'
      . $homepage
      . '/wiki/'
      . $translation_sql_under
      . '">here</a></li>' . "\n";
    $result .=
        '<li>Last scanned dump '
      . $lastdump_sql . ' ('
      . $dumpdate_sql
      . ' days old)</li>' . "\n";

    $result .= '</ul>';

    return ($result);
}

#############################################################
# Show priority table (high, medium, low) + Number of errors
#############################################################

sub get_number_of_prio {
    my $result = q{};
    my $dbh    = connect_database();

    my $sql_text = "SELECT IFNULL(sum(errors),0), prio, IFNULL(sum(done),0) 
    FROM cw_overview_errors 
    WHERE project = '" . $param_project . "' 
    GROUP BY prio 
    HAVING prio > 0 ORDER BY prio;";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my $sum_of_all    = 0;
    my $sum_of_all_ok = 0;
    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        my $j = 0;
        foreach (@$arrayref) {

            #print $_."\n";
            $output[$i][$j] = $_;
            $output[$i][$j] = '' unless defined $output[$i][$j];
            $j              = $j + 1;
            if ( $j == 3 ) {
                $j = 0;
                $i++;
            }

            #print $_."\n";
        }
        my $number_of_error = $i;
        $result .=
            '<tr><td class="table" style="text-align:right;"><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=';
        $result .= 'nothing" rel="nofollow">deactivated'
          if ( $output[0][1] == 0 );
        $result .= 'high" rel="nofollow">high priority'
          if ( $output[0][1] == 1 );
        $result .= 'middle" rel="nofollow">middle priority'
          if ( $output[0][1] == 2 );
        $result .= 'low" rel="nofollow">low priority' if ( $output[0][1] == 3 );
        $result .=
'</a></td><td class="table" style="text-align:right; vertical-align:middle;">'
          . $output[0][0]
          . '</td><td class="table" style="text-align:right; vertical-align:middle;">'
          . $output[0][2]
          . '</td></tr>' . "\n";
        $sum_of_all    = $sum_of_all + $output[0][0];
        $sum_of_all_ok = $sum_of_all_ok + $output[0][2];

        if ( $output[0][1] == 3 ) {

            # summe -> all priorities
            my $result2 = q{};
            $result2 .=
                '<tr><td class="table" style="text-align:right;"><a href="'
              . $script_name
              . '?project='
              . $param_project
              . '&amp;view=';
            $result2 .= 'all">all priorities';
            $result2 .=
'</a></td><td class="table" style="text-align:right; vertical-align:middle;">'
              . $sum_of_all
              . '</td><td class="table" style="text-align:right; vertical-align:middle;">'
              . $sum_of_all_ok
              . '</td></tr>' . "\n";

            $result = $result2 . $result;
        }

    }

    return ($result);
}

####################################################################
# Show table with todo, description of errors (all,high,middle,low)
####################################################################

sub get_number_error_and_desc_by_prio {
    my ($prio) = @_;
    my $result = q{};
    my $dbh    = connect_database();

    # SHOW ONE PRIORITY FROM ONE PROJECT
    my $sql_text =
"SELECT IFNULL(errors, '') todo, IFNULL(done, '') ok, name, name_trans, id FROM cw_overview_errors WHERE prio = "
      . $prio
      . " and project = '"
      . $param_project
      . "' order by name_trans, name;";

    # SHOW ALL PRIORITIES FROM ONE PROJECT
    if ( $prio == 0 ) {
        i $sql_text =
"SELECT IFNULL(errors, '') todo, IFNULL(done, '') ok, name, name_trans, id FROM cw_overview_errors WHERE project = '"
          . $param_project
          . "' order by name_trans, name;";
    }

    # SHOW ALL PRIORITIES FROM ALL PROJECTS
    if ( $prio == 0 and $param_project eq 'all' ) {
        $sql_text =
"SELECT IFNULL(errors, '') todo, IFNULL(done, '') ok, name, name_trans, id FROM cw_overview_errors ORDER BY name_trans, name;";
    }

    my $sth = $dbh->prepare($sql_text)
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    $result .= '<table class="table">';
    $result .= '<tr>';
    $result .= '<th class="table">To-do</th>';
    $result .= '<th class="table">Done</th>';
    $result .= '<th class="table">Description</th>';
    $result .= '<th class="table">ID</th>';
    $result .= '</tr>' . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        my $j = 0;
        foreach (@$arrayref) {

            #print $_."\n";
            $output[$i][$j] = $_;
            $output[$i][$j] = '' unless defined $output[$i][$j];
            $j              = $j + 1;
            if ( $j == 5 ) {
                $j = 0;
                $i++;
            }

            #print $_."\n";
        }

        my $headline = $output[0][2];
        $headline = $output[0][3] if ( $output[0][3] ne '' );

        $result .= '<tr>';
        $result .= '<td class="table" align="right"  valign="middle">'
          . $output[0][0] . '</td>';
        $result .= '<td class="table" align="right"  valign="middle">'
          . $output[0][1] . '</td>';
        $result .=
            '<td class="table"><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=only&amp;id='
          . $output[0][4]
          . '" rel="nofollow">'
          . $headline
          . '</a></td>';
        $result .= '<td class="table" align="right"  valign="middle">'
          . $output[0][4] . '</td>';
        $result .= '</tr>' . "\n";

    }
    $result .= '</table>';

    return ($result);
}

###########################################################################

sub get_headline {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();
    my $sql_text =
        "SELECT name, name_trans FROM cw_error_desc WHERE id = "
      . $error
      . " AND project = '"
      . $param_project . "';";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        my $j = 0;
        foreach (@$arrayref) {

            #print '<p class="smalltext"/>xxx'.$_."</p>\n";
            $output[$i][$j] = $_;
            $output[$i][$j] = '' unless defined $output[$i][$j];
            $j              = $j + 1;
            if ( $j == 2 ) {
                $j = 0;
                $i++;
            }
        }
        if ( $output[0][1] ne '' ) {

            # translated text
            $result = $output[0][1];
        }
        else {
            # english text
            $result = $output[0][0];
        }
    }

    return ($result);
}

###########################################################################

sub get_description {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    my $sql_text =
        "SELECT text, text_trans FROM cw_error_desc WHERE id = "
      . $error
      . " AND project = '"
      . $param_project . "';";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        my $j = 0;
        foreach (@$arrayref) {

            #print $_."\n";
            $output[$i][$j] = $_;
            $output[$i][$j] = '' unless defined $output[$i][$j];
            $j              = $j + 1;

            #print $_."\n";
        }
        if ( $output[0][1] ne '' ) {

            # translated text
            $result = $output[0][1];
        }
        else {
            # english text
            $result = $output[0][0];
        }

    }

    return ($result);
}

###########################################################################

sub get_prio_of_error {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    my $sql_text =
        "SELECT prio FROM cw_error_desc WHERE id = "
      . $error
      . " AND project = '"
      . $param_project . "';";

    my $sth = $dbh->prepare($sql_text)
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            $result = $_;
            $result = '' unless defined $result;
        }
    }

    return ($result);
}

##########################################################################
## SHOW TABLE FOR ONLY ONE ERROR FOR ONE PROJECT
##########################################################################

sub get_article_of_error {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    $column_orderby = q{}                 if ( $column_orderby eq '' );
    $column_orderby = 'order by a.title'  if ( $param_orderby  eq 'article' );
    $column_orderby = 'order by a.notice' if ( $param_orderby  eq 'notice' );
    $column_orderby = 'order by more'     if ( $param_orderby  eq 'more' );
    $column_orderby = 'order by a.found'  if ( $param_orderby  eq 'found' );
    $column_sort    = 'asc'               if ( $column_sort    eq '' );
    $column_orderby = $column_orderby . ' ' . $column_sort
      if ( $column_orderby ne '' );

    $column_orderby = q{}               if ( $column_orderby eq '' );
    $column_orderby = 'order by title'  if ( $param_orderby  eq 'article' );
    $column_orderby = 'order by notice' if ( $param_orderby  eq 'notice' );
    $column_orderby = 'order by more'   if ( $param_orderby  eq 'more' );
    $column_orderby = 'order by found'  if ( $param_orderby  eq 'found' );
    $column_sort    = 'asc'             if ( $column_sort    eq '' );
    $column_orderby = $column_orderby . ' ' . $column_sort
      if ( $column_orderby ne '' );

    #------------------- ← 0 bis 25 →

    $result .= '<p>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $offset_lower
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby='
      . $param_orderby
      . '&amp;sort='
      . $param_sort
      . '">←</a>';
    $result .= ' ' . $param_offset . ' bis ' . $offset_end . ' ';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $offset_higher
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby='
      . $param_orderby
      . '&amp;sort='
      . $param_sort
      . '">→</a>';
    $result .= '</p>';

    $result .= '<table class="table">';

    #------------------- ARTICLE TITLE

    $result .= '<tr>';
    $result .= '<th class="table">Article';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=article&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=article&amp;sort=desc">↓</a>';
    $result .= '</th>';

    #------------------- EDIT

    $result .= '<th class="table">Edit</th>';

    #------------------- NOTICE

    $result .= '<th class="table">Notice';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=notice&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=notice&amp;sort=desc">↓</a>';
    $result .= '</th>';

    #------------------- MORE

    $result .= '<th class="table">More';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=more&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=more&amp;sort=desc">↓</a>';
    $result .= '</th>';

    #------------------- FOUND

    $result .= '<th class="table">Found';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=found&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=found&amp;sort=desc">↓</a>';
    $result .= '</th>';

    #------------------- DONE

    $result .= '<th class="table">Done</th>';
    $result .= '</tr>' . "\n";

    #--------- Main Table

    my $row_style = q{};
    my $row_style_main;

    my $sql_text = "SELECT title, notice, found, project FROM cw_error
    WHERE error = " . $error . " AND project = '" . $param_project . "'
    AND ok=0 " . ' ' . $column_orderby . ' ' . " 
    LIMIT " . $param_offset . "," . $param_limit . ";";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my ( $title_sql, $notice_sql, $found_sql, $project_sql );
    $sth->bind_col( 1, \$title_sql );
    $sth->bind_col( 2, \$notice_sql );
    $sth->bind_col( 3, \$found_sql );
    $sth->bind_col( 4, \$project_sql );

    while ( $sth->fetchrow_arrayref ) {
        $title_sql   = q{} unless defined $title_sql;
        $notice_sql  = q{} unless defined $notice_sql;
        $found_sql   = q{} unless defined $found_sql;
        $project_sql = q{} unless defined $project_sql;

        my $title_sql_under = $title_sql;
        $title_sql_under =~ tr/ /_/;

        my $article_project = $param_project;
        if ( $param_project eq 'all' ) {
            $article_project = $project_sql;
            $lang            = $article_project;
            $lang =~ s/wiki$//;
        }

        my $homepage = get_homepage($article_project);

        if ( $row_style eq q{} ) {
            $row_style      = 'style="background-color:#D0F5A9;"';
            $row_style_main = 'style="background-color:#D0F5A9; ';
        }
        else {
            $row_style      = q{};
            $row_style_main = 'style="';
        }

        $result .= '<tr>';
        $result .=
            '<td class="table" '
          . $row_style
          . '><a href="https://'
          . $homepage
          . '/wiki/'
          . $title_sql_under . '">'
          . $title_sql
          . '</a></td>';
        $result .=
            '<td class="table" '
          . $row_style
          . '><a href="https://'
          . $homepage
          . '/w/index.php?title='
          . $title_sql_under
          . '&amp;action=edit">edit</a></td>';

        $result .=
          '<td class="table" ' . $row_style . '>' . $notice_sql . '</td>';
        $result .=
            '<td class="table" '
          . $row_style_main
          . ' text-align:center; vertical-align:middle;">';

        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $article_project
          . '&amp;view=detail&amp;title='
          . $title_sql . '">'
          . 'more</a>';

        $result .= '</td>';
        $result .=
            '<td class="table" '
          . $row_style . '>'
          . time_string($found_sql) . '</td>';
        $result .=
            '<td class="table" '
          . $row_style_main
          . ' text-align:center; vertical-align:middle;">';
        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $article_project
          . '&amp;view=only&amp;id='
          . $error
          . '&amp;title='
          . $title_sql
          . '&amp;offset='
          . $param_offset
          . '&amp;limit='
          . $param_limit
          . '&amp;orderby='
          . $param_orderby
          . '&amp;sort='
          . $param_sort
          . '" rel="nofollow">Done</a>';
        $result .= '</td></tr>' . "\n";

    }
    $result .= '</table>';

    return ($result);
}

###########################################################################

sub get_done_article_of_error {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    # show all done articles of one error

    $column_orderby = 'a.title'  if ( $column_orderby eq '' );
    $column_orderby = 'a.title'  if ( $param_orderby  eq 'article' );
    $column_orderby = 'a.notice' if ( $param_orderby  eq 'notice' );
    $column_orderby = 'more'     if ( $param_orderby  eq 'more' );
    $column_orderby = 'a.found'  if ( $param_orderby  eq 'found' );
    $column_sort    = 'asc'      if ( $column_sort    eq '' );

    my $sql_text =
"SELECT a.title, a.notice, a.error_id, count(*) more, a.found, a.project FROM (
        SELECT title, notice, error_id, found, project from cw_error WHERE error="
      . $error . " AND ok=1 AND project = '" . $param_project . "') a
        JOIN cw_error b
        ON (a.title = b.title)
        AND b.project = '" . $param_project . "'
        GROUP BY a.title, a.notice, a.error_id
        ORDER BY " . $column_orderby . " " . $column_sort . " 
        LIMIT " . $param_offset . "," . $param_limit . ";";

    if ( $param_project eq 'all' ) {
        $sql_text =
"SELECT a.title, a.notice, a.error_id, count(*) more, a.found, a.project FROM (
            SELECT title, notice, error_id, found, project FROM cw_error WHERE error="
          . $error . " AND ok=1 ) a
            JOIN cw_error b
            ON (a.title = b.title)
            WHERE b.ok = 1
            GROUP BY a.title, a.notice, a.error_id
            ORDER BY " . $column_orderby . " " . $column_sort . " 
            LIMIT " . $param_offset . "," . $param_limit . ";";
    }

    #print $sql_text."\n";
    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    $result .= '<p>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $offset_lower
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby='
      . $param_orderby
      . '&amp;sort='
      . $param_sort
      . '">←</a>';
    $result .= ' ' . $param_offset . ' bis ' . $offset_end . ' ';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $offset_higher
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby='
      . $param_orderby
      . '&amp;sort='
      . $param_sort
      . '">→</a>';
    $result .= '</p>';

    $result .= '<table class="table">';
    $result .= '<tr>';
    $result .= '<th class="table">Article';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=article&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=article&amp;sort=desc">↓</a>';
    $result .= '</th>';
    $result .= '<th class="table">Version</th>';
    $result .= '<th class="table">Notice';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=notice&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=notice&amp;sort=desc">↓</a>';
    $result .= '</th>';
    $result .= '<th class="table">More';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=more&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=more&amp;sort=desc">↓</a>';
    $result .= '</th>';
    $result .= '<th class="table">Found';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=found&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=found&amp;sort=desc">↓</a>';
    $result .= '</th>';
    $result .= '<th class="table">Done</th>';
    $result .= '</tr>' . "\n";
    my $row_style = '';

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        my $j = 0;
        foreach (@$arrayref) {

            #print $_."\n";
            $output[$i][$j] = $_;
            $output[$i][$j] = '' unless defined $output[$i][$j];
            $j              = $j + 1;
            if ( $j == 6 ) {
                $j = 0;
                $i++;
            }

            #print $_."\n";
        }

        my $article_project = $param_project;
        if ( $param_project eq 'all' ) {
            $article_project = $output[0][5];
            $lang            = $article_project;
            $lang =~ s/wiki$//;
        }

        if ( $row_style eq '' ) {
            $row_style = 'style="background-color:#D0F5A9"';
        }
        else {
            $row_style = '';
        }

        $result .= '<tr>';
        $result .=
            '<td class="table" '
          . $row_style
          . '><a href="https://'
          . get_homepage($article_project)
          . '/wiki/'
          . $output[0][0] . '">'
          . $output[0][0]
          . '</a></td>';
        $result .=
            '<td class="table" '
          . $row_style
          . '><a href="https://'
          . get_homepage($article_project)
          . '/w/index.php?title='
          . $output[0][0]
          . '&amp;action=history">history</a></td>';

        $result .=
          '<td class="table" ' . $row_style . '>' . $output[0][1] . '</td>';
        $result .=
            '<td class="table" '
          . $row_style
          . ' align="center"  valign="middle">';
        if ( $output[0][3] == 1 ) {

            # only one error
        }
        else {
            # more other errors

            $result .=
                '<a href="'
              . $script_name
              . '?project='
              . $article_project
              . '&amp;view=detail&amp;title='
              . $output[0][2] . '">'
              . $output[0][3] . '</a>';
        }
        $result .= '</td>';
        $result .=
            '<td class="table" '
          . $row_style . '>'
          . time_string( $output[0][4] ) . '</td>';
        $result .=
            '<td class="table" '
          . $row_style
          . ' align="center"  valign="middle">';

        $result .= 'ok';
        $result .= '</td></tr>' . "\n";

    }
    $result .= '</table>';

    return ($result);
}

###########################################################################

sub get_article_of_error_for_bots {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    my $sql_text =
"SELECT a.title, a.notice, a.error_id, count(*) FROM (select title, notice, error_id FROM cw_error WHERE error="
      . $error
      . " AND ok=0 AND project = '"
      . $param_project . "') a
        JOIN cw_error b
        ON (a.title = b.title)
        WHERE b.ok = 0
        AND b.project = '" . $param_project . "'
        GROUP BY a.title, a.notice, a.error_id
        LIMIT " . $param_offset . "," . $param_limit . ";";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    $result .= '<pre>' . "\n";
    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        my $j = 0;
        foreach (@$arrayref) {

            #print $_."\n";
            $output[$i][$j] = $_;
            $output[$i][$j] = '' unless defined $output[$i][$j];
            $j              = $j + 1;
            if ( $j == 4 ) {
                $j = 0;
                $i++;
            }

            #print $_."\n";
        }

        $result .= $output[0][0] . "\n";
    }
    $result .= '</pre>';

    return ($result);
}

###########################################################################

sub get_list {
    my $result = q{};
    my $dbh    = connect_database();

    $column_orderby = 'more'  if ( $column_orderby eq '' );
    $column_orderby = 'title' if ( $param_orderby  eq 'article' );
    $column_orderby = 'more'  if ( $param_orderby  eq 'more' );
    $column_sort    = 'desc'  if ( $column_sort    eq '' );

    my $sql_text =
"SELECT title, count(*) more, error_id FROM cw_error WHERE ok=0 AND project = '"
      . $param_project . "' 
        GROUP BY title ORDER BY "
      . $column_orderby . " " . $column_sort . ", title 
        LIMIT " . $param_offset . "," . $param_limit . ";";

    #print $sql_text."\n";
    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    $result .= '<p>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=list&amp;offset='
      . $offset_lower
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby='
      . $param_orderby
      . '&amp;sort='
      . $param_sort
      . '">←</a>';
    $result .= ' ' . $param_offset . ' bis ' . $offset_end . ' ';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=list&amp;offset='
      . $offset_higher
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby='
      . $param_orderby
      . '&amp;sort='
      . $param_sort
      . '">→</a>';
    $result .= '</p>';

    $result .= '<table class="table">';
    $result .= '<tr>';
    $result .= '<th class="table">Number';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=list&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=more&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=list&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=more&amp;sort=desc">↓</a>';
    $result .= '</th>';
    $result .= '<th class="table">Article';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=list&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=article&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=list&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=article&amp;sort=desc">↓</a>';
    $result .= '</th>';
    $result .= '<th class="table">Details</th>';
    $result .= '</tr>' . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        my $j = 0;
        foreach (@$arrayref) {

            #print $_."\n";
            $output[$i][$j] = $_;
            $output[$i][$j] = '' unless defined $output[$i][$j];
            $j              = $j + 1;
            if ( $j == 3 ) {
                $j = 0;
                $i++;
            }

            #print $_."\n";
        }

        $result .= '<tr><td class="table" align="right"  valign="middle">'
          . $output[0][1] . '</td>';
        $result .=
            '<td class="table"><a href="https://'
          . get_homepage($param_project)
          . '/wiki/'
          . $output[0][0] . '">'
          . $output[0][0]
          . '</a></td>';
        $result .=
            '<td class="table" align="center"  valign="middle"><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=detail&amp;title='
          . $output[0][2]
          . '">Details</a></td>';
        $result .= '</tr>' . "\n";

    }
    $result .= '</table>';

    return ($result);
}

###########################################################################

sub get_all_error_of_article {
    my ($id)   = @_;
    my $result = q{};
    my $dbh    = connect_database();

    my $sql_text =
      "SELECT a.error, b.name, a.notice, a.error_id, a.ok, b.name_trans
        FROM cw_error a JOIN cw_error_desc b 
        ON (a.error = b.id) 
        WHERE (a.error_id = "
      . $id . " AND a.project = '" . $param_project . "')
        AND b.project = '" . $param_project . "'
        ORDER BY b.name;";

    #print $sql_text . "\n\n\n";
    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    $result .= '<table class="table">';
    $result .= '<tr>';
    $result .= '<th class="table">ideas for improvement</th>';
    $result .= '<th class="table">Notice</th>';
    $result .= '<th class="table">Done</th>';
    $result .= '</tr>' . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        my $j = 0;
        foreach (@$arrayref) {

            #print $_."\n";
            $output[$i][$j] = $_;
            $output[$i][$j] = '' unless defined $output[$i][$j];
            $j              = $j + 1;
            if ( $j == 6 ) {
                $j = 0;
                $i++;
            }

            #print $_."\n";
        }

        $result .= '<tr>';
        $result .=
            '<td class="table"><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=only&amp;id='
          . $output[0][0] . '">';
        if ( $output[0][5] ne '' ) {
            $result .= $output[0][5];
        }
        else {
            $result .= $output[0][1];
        }
        $result .= '</a></td>';
        $result .= '<td class="table">' . $output[0][2] . '</td>';
        $result .= '<td class="table" align="center"  valign="middle">';
        if ( $output[0][4] eq '0' ) {
            $result .=
                '<a href="'
              . $script_name
              . '?project='
              . $param_project
              . '&amp;view=detail&amp;id='
              . $output[0][0]
              . '&amp;title='
              . $output[0][3]
              . '" rel="nofollow">Done</a>';
        }
        else {
            $result .= 'ok';
        }
        $result .= '</td>';
        $result .= '</tr>' . "\n";

    }
    $result .= '</table>';

    return ($result);
}

###########################################################################

sub get_lang {
    my $result = q{};
    my $dbh    = connect_database();

    my $sql_text =
      "SELECT lang FROM cw_project WHERE project = '" . $param_project . "';";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            $result = $_;
            $result = '' unless defined $result;
        }
    }

    return ($result);
}

###########################################################################

sub time_string {
    my ($timestring) = @_;
    my $result = q{};

    if ( $timestring ne '' ) {
        $result = $timestring . '---';
        $result = $timestring;
        $result =~ s/ /&nbsp;/g;    # SYNTAX HIGHLIGHTING
    }

    return ($result);
}

###########################################################################

sub get_homepage {
    my ($result) = @_;

    if (
        !(
               $result =~ s/^nds_nlwiki$/nds-nl.wikipedia.org/
            || $result =~ s/^commonswiki$/commons.wikimedia.org/
            || $result =~ s/^([a-z]+)wiki$/$1.wikipedia.org/
            || $result =~ s/^([a-z]+)wikisource$/$1.wikisource.org/
            || $result =~ s/^([a-z]+)wikiversity$/$1.wikiversity.org/
            || $result =~ s/^([a-z]+)wiktionary$/$1.wiktionary.org/
        )
      )
    {
        die(    "Couldn't calculate server name for project"
              . $param_project
              . "\n" );
    }

    return ($result);
}

###########################################################################

sub get_style {
    my $result = '<style type="text/css">
    body { 
    
	font-family: Verdana, Tahoma, Arial, Helvetica, sans-serif;
	font-size:14px;
	font-style:normal;
	
	/* color:#9A91ff; */
	
	/* background-color:#00077A; */
	/* background-image:url(back.jpg); */
	/* background:url(back_new.jpg) no-repeat fixed top center; */
	/* background:url(../images/back_new.jpg) no-repeat fixed top center; */
	/* background:url(../images/back_schaf2.jpg) no-repeat fixed bottom left; */
	/* background:url(../images/back_schaf3.jpg) no-repeat fixed bottom left; */
	
	background-color:white;
	color:#555555;
	text-decoration:none; 
	line-height:normal; 
	font-weight:normal; 
	font-variant:normal; 
	text-transform:none; 
	margin-left:5%;
	margin-right:5%;
	}
	
h1	{
	/*color:red; */
	font-size:20px;
	}

h2	{
	/*color:red; */
	font-size:16px;
	}
	
a 	{  

	/*only blue */
	/* color:#80BFBF; */ 
	/* color:#4889c5; */ 
	/* color:#326a9e; */  
	
	color:#4889c5;
	font-weight:bold;
	/*nettes grün */
	/*color:#7CFC00;*/
	
	/* nice combinatione */
	/*color:#00077A; */
	/*background-color:#eee8fd;*/
	
	
	/* without underline */
	text-decoration:none; 
	
	/*Außenabstand*/
	/*padding:2px;*/
	}

a:hover {  
	background-color:#ffdeff;
	color:red;
	}
	
.nocolor{  
	background-color:white;
	color:white;
	} 
	
a:hover.nocolor{  
	background-color:white;
	color:white;
	}
	
.table{
	font-size:12px; 

	vertical-align:top;

	border-width:thin;
  	border-style:solid;
  	border-color:blue;
  	background-color:#EEEEEE;
  	
  	/*Innenabstand*/
	padding-top:2px;
	padding-bottom:2px;
	padding-left:5px;
	padding-right:5px;
  	
  	/* small border */
  	border-collapse:collapse; 
	
	/* no wrap
	white-space:nowrap;*/
  	
  	}
	
</style>';
    return ($result);
}

###############################
sub get_statistic_starter {

}

