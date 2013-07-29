#! /usr/bin/perl -T

###########################################################################
#
# FILE:   checkwiki.cgi
# USAGE:
#
# DESCRIPTION:
#
# AUTHOR:  Stefan Kühn, Bryan White
# VERSION: 2013-07-28
# LICENSE: GPLv3
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

our $lang;    # try to remove this

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
if ( $param_orderby ne q{} ) {
    if (    $param_orderby ne 'article'
        and $param_orderby ne 'notice'
        and $param_orderby ne 'found'
        and $param_orderby ne 'more' )
    {
        $param_orderby = q{};
    }
}

if ( $param_sort ne q{} ) {
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

##########################################################################
## MAIN PROGRAM
##########################################################################

check_if_no_params();
begin_html();

##########################################################################
## ONLY PROJECT PARAM ENTERED - SHOW PAGE FOR ONLY ONE PROJECT
##########################################################################

if (    $param_project ne q{}
    and $param_view  eq 'project'
    and $param_id    eq q{}
    and $param_title eq q{} )
{
    print '<p>→ <a href="'
      . $script_name
      . '">Homepage</a> → '
      . $param_project . '</p>' . "\n";

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
    my $headline = q{};
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
    my $headline = q{};
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
    my $headline = get_headline($param_id);

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
        "SELECT title FROM cw_error WHERE Title='"
      . $param_title
      . "' AND project = '"
      . $param_project
      . "' limit 1;";

    my $sth = $dbh->prepare($sql_text)
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            my $result = $_;
            $result = q{} unless defined $result;
            if ( $result ne '' ) {
                print '<p>Article: <a target "_blank" href="'
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

##########################################################################
## NO PARAMS ENTERED - SHOW STARTPAGE WITH OVERVIEW OF ALL PROJECTS
##########################################################################

sub check_if_no_params {
    if (    $param_project eq ''
        and $param_view      eq ''
        and $param_id        eq ''
        and $param_title     eq ''
        and $param_statistic eq '' )
    {
        print redirect(
            -url => 'http://tools.wmflabs.org/checkwiki/index.htm' );
    }

}

##########################################################################
## BEGIN HTML FOR ALL PAGES
##########################################################################

sub begin_html {

    print "Content-type: text/html\n\n";
    print
"<!DOCTYPE html>\n<head>\n<meta http-equiv=\"content-type\" content=\"text/html;charset=UTF-8\" />\n";
    print '<title>Check Wikipedia</title>' . "\n";
    print '<link rel="stylesheet" href="css/style.css" type="text/css" />'
      . "\n";
    print get_style();
    print '</head>' . "\n";
    print '<body>' . "\n";
    print '<h1>Check Wikipedia</h1>' . "\n" if ( $param_view ne 'bots' );

}

##########################################################################
## GET NUMBER OF ALL ERRORS OVER ALL PROJECTS
##########################################################################

sub get_number_all_errors_over_all {
    my $dbh    = connect_database();
    my $result = 0;

    my $sth = $dbh->prepare('SELECT count(*) FROM cw_error WHERE ok=0;')
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            $result = $_;
            $result = q{} unless defined $result;
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
            $result = q{} unless defined $result;
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

    my $count_sql;
    $sth->bind_col( 1, \$count_sql );

    $sth->fetchrow_arrayref;

    if ( !defined($count_sql) ) {
        $count_sql = q{};
    }

    $result = $count_sql;

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

    my ( $errors_sql, $priority_sql, $done_sql );
    $sth->bind_col( 1, \$errors_sql );
    $sth->bind_col( 2, \$priority_sql );
    $sth->bind_col( 3, \$done_sql );

    while ( $sth->fetchrow_arrayref ) {

        $result .=
            '<tr><td class="table" style="text-align:right;"><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=';
        $result .= 'nothing" rel="nofollow">deactivated'
          if ( $priority_sql == 0 );
        $result .= 'high" rel="nofollow">high priority'
          if ( $priority_sql == 1 );
        $result .= 'middle" rel="nofollow">middle priority'
          if ( $priority_sql == 2 );
        $result .= 'low" rel="nofollow">low priority'
          if ( $priority_sql == 3 );

        $result .=
'</a></td><td class="table" style="text-align:right; vertical-align:middle;">'
          . $errors_sql
          . '</td><td class="table" style="text-align:right; vertical-align:middle;">'
          . $done_sql
          . '</td></tr>' . "\n";
        $sum_of_all    = $sum_of_all + $errors_sql;
        $sum_of_all_ok = $sum_of_all_ok + $done_sql;

        if ( $priority_sql == 3 ) {

            # sum -> all priorities
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

    $result .= '<table class="table">';
    $result .= '<tr>';
    $result .= '<th class="table">To-do</th>';
    $result .= '<th class="table">Done</th>';
    $result .= '<th class="table">Description</th>';
    $result .= '<th class="table">ID</th>';
    $result .= '</tr>' . "\n";

    # SHOW ONE PRIORITY FROM ONE PROJECT
    my $sql_text =
"SELECT IFNULL(errors, '') todo, IFNULL(done, '') ok, name, name_trans, id FROM cw_overview_errors WHERE prio = "
      . $prio
      . " and project = '"
      . $param_project
      . "' order by name_trans, name;";

    # SHOW ALL PRIORITIES FROM ONE PROJECT
    if ( $prio == 0 ) {
        $sql_text =
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

    my ( $errors_sql, $done_sql, $ok_sql, $name_sql, $trans_sql, $id_sql );
    $sth->bind_col( 1, \$errors_sql );
    $sth->bind_col( 2, \$ok_sql );
    $sth->bind_col( 3, \$name_sql );
    $sth->bind_col( 4, \$trans_sql );
    $sth->bind_col( 5, \$id_sql );

    while ( $sth->fetchrow_arrayref ) {

        if ( !defined($trans_sql) ) {
            $trans_sql = q{};
        }

        my $headline = $name_sql;
        if ( $trans_sql ne q{} ) {
            $headline = $trans_sql;
        }

        $result .= '<tr>';
        $result .= '<td class="table" align="right"  valign="middle">'
          . $errors_sql . '</td>';
        $result .= '<td class="table" align="right"  valign="middle">'
          . $ok_sql . '</td>';
        $result .=
            '<td class="table"><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=only&amp;id='
          . $id_sql
          . '" rel="nofollow">'
          . $headline
          . '</a></td>';
        $result .= '<td class="table" align="right"  valign="middle">'
          . $id_sql . '</td>';
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

    my ( $name_sql, $name_trans_sql );
    $sth->bind_col( 1, \$name_sql );
    $sth->bind_col( 2, \$name_trans_sql );

    $sth->fetchrow_arrayref;

    if ( !defined($name_sql) ) {
        $name_sql = q{};
    }
    if ( !defined($name_trans_sql) ) {
        $name_trans_sql = q{};
    }

    if ( $name_trans_sql ne q{} ) {
        $result = $name_trans_sql;    # Translated text
    }
    else {
        $result = $name_sql;          # English text
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

    my ( $text_sql, $text_trans_sql );
    $sth->bind_col( 1, \$text_sql );
    $sth->bind_col( 2, \$text_trans_sql );

    $sth->fetchrow_arrayref;

    if ( !defined($text_sql) ) {
        $text_sql = q{};
    }
    if ( !defined($text_trans_sql) ) {
        $text_trans_sql = q{};
    }

    if ( $text_trans_sql ne q{} ) {
        $result = $text_trans_sql;    # Translated text
    }
    else {
        $result = $text_sql;          # English text
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
    $result .= ' ' . $param_offset . ' to ' . $offset_end . ' ';
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

    #------------------- ARTICLE TITLE

    $result .= '<table class="table">';
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

        if ( !defined($found_sql) ) {
            $found_sql = q{};
        }

        my $title_sql_under = $title_sql;
        $title_sql_under =~ tr/ /_/;

        my $article_project = $param_project;
        if ( $param_project eq 'all' ) {
            $article_project = $project_sql;
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

    #------------------- ← 0 to 25 →

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
    $result .= ' ' . $param_offset . ' to ' . $offset_end . ' ';
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

    #------------------- ARTICLE TITLE

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

    #------------------- VERSION

    $result .= '<th class="table">Version</th>';

    #------------------- NOTICE

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

    #------------------- FOUND

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

    #------------------- DONE

    $result .= '<th class="table">Done</th>';
    $result .= '</tr>' . "\n";

    #--------- Main Table

    my $row_style = q{};
    my $row_style_main;
    my $sql_text;

    if ( $param_project ne 'all' ) {
        $sql_text = "SELECT a.title, a.notice, a.found, a.project FROM (
        SELECT title, notice, found, project from cw_error WHERE error="
          . $error . " AND ok=1 AND project = '" . $param_project . "') a
        JOIN cw_error b
        ON (a.title = b.title)
        AND b.project = '" . $param_project . "'
        GROUP BY a.title, a.notice
        ORDER BY " . $column_orderby . " " . $column_sort . " 
        LIMIT " . $param_offset . "," . $param_limit . ";";
    }
    else {
        $sql_text = "SELECT a.title, a.notice, a.found, a.project FROM (
        SELECT title, notice, found, project FROM cw_error WHERE error="
          . $error . " AND ok=1 ) a
        JOIN cw_error b
        ON (a.title = b.title)
        WHERE b.ok = 1
        GROUP BY a.title, a.notice
        ORDER BY " . $column_orderby . " " . $column_sort . " 
        LIMIT " . $param_offset . "," . $param_limit . ";";
    }

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my ( $title_sql, $notice_sql, $found_sql, $project_sql );
    $sth->bind_col( 1, \$title_sql );
    $sth->bind_col( 2, \$notice_sql );
    $sth->bind_col( 3, \$found_sql );
    $sth->bind_col( 4, \$project_sql );

    while ( $sth->fetchrow_arrayref ) {
        $found_sql = q{} unless defined $found_sql;

        my $title_sql_under = $title_sql;
        $title_sql_under =~ tr/ /_/;

        my $article_project = $param_project;
        if ( $param_project eq 'all' ) {
            $article_project = $project_sql;
        }

        my $homepage = get_homepage($article_project);

        if ( $row_style eq q{} ) {
            $row_style      = 'style="background-color:#D0F5A9"';
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
          . '&amp;action=history">history</a></td>';

        $result .=
          '<td class="table" ' . $row_style . '>' . $notice_sql . '</td>';
        $result .=
            '<td class="table" '
          . $row_style . '>'
          . time_string($found_sql) . '</td>';
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

    my $sql_text = "SELECT title FROM cw_error
    WHERE error = " . $error . " AND project = '" . $param_project . "'
    AND ok=0 LIMIT " . $param_offset . ", 500 ;";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    $result .= '<pre>' . "\n";

    my ($title_sql);
    $sth->bind_col( 1, \$title_sql );

    while ( $sth->fetchrow_arrayref ) {
        $result .= $title_sql . "\n";
    }

    $result .= '</pre>';

    return ($result);
}

###########################################################################
## OPEN DATABASE
###########################################################################

sub connect_database {

    my ( $dbh, $dsn, $user, $password );

    $dsn =
"DBI:mysql:p50380g50450__checkwiki_p:tools-db;mysql_read_default_file=../replica.my.cnf";
    $dbh = DBI->connect( $dsn, $user, $password { mysql_enable_utf8 => 1 } )
      or die( "Could not connect to database: " . DBI::errstr() . "\n" );

    return ($dbh);
}

###########################################################################

sub get_all_error_of_article {
    my ($id)   = @_;
    my $result = q{};
    my $dbh    = connect_database();

    $result .= '<table class="table">';
    $result .= '<tr>';
    $result .= '<th class="table">Error name</th>';
    $result .= '<th class="table">Notice</th>';
    $result .= '<th class="table">Done</th>';
    $result .= '</tr>' . "\n";

    my $sql_text =
      "SELECT a.error, b.name, a.notice, a.title, a.ok, b.name_trans
        FROM cw_error a JOIN cw_error_desc b 
        ON (a.error = b.id) 
        WHERE (a.title = '"
      . $id . "' AND a.project = '" . $param_project . "')
        AND b.project = '" . $param_project . "'
        ORDER BY b.name;";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my ( $error_sql, $name_sql, $notice_sql, $title_sql, $ok_sql, $trans_sql );
    $sth->bind_col( 1, \$error_sql );
    $sth->bind_col( 2, \$name_sql );
    $sth->bind_col( 3, \$notice_sql );
    $sth->bind_col( 4, \$title_sql );
    $sth->bind_col( 5, \$ok_sql );
    $sth->bind_col( 6, \$trans_sql );

    while ( $sth->fetchrow_arrayref ) {

        if ( !defined($name_sql) ) {
            $name_sql = q{};
        }
        if ( !defined($trans_sql) ) {
            $trans_sql = q{};
        }

        $result .= '<tr>';
        $result .=
            '<td class="table"><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=only&amp;id='
          . $error_sql . '">';
        if ( $trans_sql ne '' ) {
            $result .= $trans_sql;
        }
        else {
            $result .= $name_sql;
        }
        $result .= '</a></td>';
        $result .= '<td class="table">' . $notice_sql . '</td>';
        $result .= '<td class="table" align="center"  valign="middle">';
        if ( $ok_sql eq '0' ) {
            $result .=
                '<a href="'
              . $script_name
              . '?project='
              . $param_project
              . '&amp;view=detail&amp;id='
              . $error_sql
              . '&amp;title='
              . $title_sql
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

