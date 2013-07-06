#! /usr/bin/env perl

###########################################################################
##
## FILE:   checkwiki.pl
## USAGE:
##
## DESCRIPTION
##
## AUTHOR: Stefan Kühn
## Licence: GPL
##
###########################################################################

# notice
# delete_old_errors_in_db  --> Problem with deleting of errors in loadmodus
# delete_deleted_article_from_db --> Problem old articles

#################################################################

use strict;
use warnings;

our $VERSION = '2013-02-15';

use lib '/data/project/checkwiki/share/perl';
use DBI;
use File::Temp;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use LWP::UserAgent;
use MediaWiki::DumpFile::Compat;
use POSIX qw(strftime);
use URI::Escape;
use XML::LibXML;
use Data::Dumper;

binmode( STDOUT, ":encoding(UTF-8)" );  # PRINT OUTPUT IN UTF-8.  ARTICLE TITLES
                                        # ARE IN UTF-8

our $output_directory = '/mnt/user-store/sk/data/checkwiki/';
our $output_geo       = '/mnt/user-store/sk/data/geo/';

our $dump;
our $quit_program =
  'no';    # quit the program (yes,no), for quit the programm in an emergency
our $quit_reason = q{};    # quit the program reason

our $dump_or_live = q{};   # scan modus (dump, live)
our $silent_modus = 0;     # silent modus (very low output at screen) for batch

our $starter_modus   = 0;  # to update in the loadmodus the cw_starter table
our $load_modus_done = 1;  # done article from db
our $load_modus_new  = 1;  # new article from db
our $load_modus_dump = 1;  # new article from db
our $load_modus_last_change = 1;    # last_change article from db
our $load_modus_old         = 1;    # old article from db

our $details_for_page =
  'no';   # yes/no  durring the scan you can get more details for a article scan

our $time_start = time();    # start timer in secound
our $time_end   = time();    # end time in secound
our $date       = 0;         # date of dump "20060324"

our $line_number = 0;        # number of line in dump
our $project;                # name of the project 'dewiki'
our $language    = q{};      # language of dump 'de', 'en';
our $page_number = 0;        # number of pages in namesroom 0
our $base = q{};    # base of article, 'http://de.wikipedia.org/wiki/Hauptseite'
our $home = q{};    # base of article, 'http://de.wikipedia.org/wiki/'

our @namespace;     # namespace values
                    # 0 number
                    # 1 namespace in project language
                    # 2 namespace in english language

our @namespacealiases;    # namespacealiases values
                          # 0 number
                          # 1 namespacealias

our @namespace_cat;       #all namespaces for categorys
our @namespace_image;     #all namespaces for images
our @namespace_templates; #all namespaces for templates

our @magicword_defaultsort;

our @magicword_img_thumbnail;
our @magicword_img_manualthumb;
our @magicword_img_right;
our @magicword_img_left;
our @magicword_img_none;
our @magicword_img_center;
our @magicword_img_framed;
our @magicword_img_frameless;
our @magicword_img_page;
our @magicword_img_upright;
our @magicword_img_border;
our @magicword_img_sub;
our @magicword_img_super;
our @magicword_img_link;
our @magicword_img_alt;
our @magicword_img_width;
our @magicword_img_baseline;
our @magicword_img_top;
our @magicword_img_text_top;
our @magicword_img_middle;
our @magicword_img_bottom;
our @magicword_img_text_bottom;

# Database configuration.
our $DbName = 'u_sk_yarrow';
our $DbServer;
our $DbUsername;
our $DbPassword;

# MediaWiki::DumpFile variables
our $pmwd      = Parse::MediaWikiDump->new;
our $pages     = q{};
our $file_size = 0;
our $artcount  = 0;
our $start     = time;

# Wiki-special variables

our @live_article;    # to-do-list for live (all articles to scan)
our $current_live_article = -1;    # line_number_of_current_live_article
our $number_of_live_tests = -1;    # Number of articles for live test

our $current_live_error_scan = -1; # for scan every 100 article of an error
our @live_to_scan;    # article of one error number which should be scanned
our $number_article_live_to_scan = -1;    # all article from one error
our @article_was_scanned;    #if an article was scanned, this will insert here

our $xml_text_from_api =
  q{};                       # the text from more then one articles from the API

our $error_counter = -1;     # number of found errors in all article

our @error_description;   # Error Description
                          # 0 priority in script
                          # 1 title in English
                          # 2 description in English
                          # 3 number of found (only live scanned)
                          # 4 priority of foreign language
                          # 5 title in foreign language
                          # 6 description in foreign language
                          # 7 number of found in last scan (from statistic file)
                          # 8 all known errors (from statistic file + live)
                          # 9  XHTML translation title
                          # 10 XHTML translation description

our $number_of_error_description = -1;    # number of error_description

our $max_error_count = 50;                # maximum of shown article per error
our $maximum_current_error_scan =
  -1;    # how much shold be scanned for reach the max_error_count
our $rest_of_errors_not_scan_yet          = q{};
our $number_of_all_errors_in_all_articles = 0;     #all errors

our $for_statistic_new_article                   = 0;
our $for_statistic_last_change_article           = 0;
our $for_statistic_geo_article                   = 0;
our $for_statistic_number_of_articles_with_error = 0;

# files
our $error_list_filename     = 'error_list.txt';
our $translation_file        = 'translation.txt';
our $error_geo_list_filename = 'error_geo_list.txt';
my $TTFile;

our @inter_list = (
    'af',     'als', 'an',  'ar',     'bg', 'bs',
    'ca',     'cs',  'cy',  'da',     'de', 'el',
    'en',     'eo',  'es',  'et',     'eu', 'fa',
    'fi',     'fr',  'fy',  'gl',     'gv', 'he',
    'hi',     'hr',  'hu',  'id',     'is', 'it',
    'ja',     'jv',  'ka',  'ko',     'la', 'lb',
    'lt',     'ms',  'nds', 'nds_nl', 'nl', 'nn',
    'no',     'pl',  'pt',  'ro',     'ru', 'sh',
    'simple', 'sk',  'sl',  'sr',     'sv', 'sw',
    'ta',     'th',  'tr',  'uk',     'ur', 'vi',
    'vo',     'yi',  'zh'
);

our @foundation_projects = (
    'wikibooks',   'b',             'wiktionary', 'wikt',
    'wikinews',    'n',             'wikiquote',  'q',
    'wikisource',  's',             'wikipedia',  'w',
    'wikispecies', 'species',       'wikimedia',  'foundation',
    'wmf',         'wikiversity',   'v',          'commons',
    'meta',        'metawikipedia', 'm',          'incubator',
    'mw',          'quality',       'bugzilla',   'mediazilla',
    'nost',        'testwiki'
);

# current time
our (
    $akSekunden, $akMinuten,   $akStunden,   $akMonatstag, $akMonat,
    $akJahr,     $akWochentag, $akJahrestag, $akSommerzeit
) = localtime(time);
our $CTIME_String = localtime(time);
$akMonat     = $akMonat + 1;
$akJahr      = $akJahr + 1900;
$akMonat     = "0" . $akMonat if ( $akMonat < 10 );
$akMonatstag = "0" . $akMonatstag if ( $akMonatstag < 10 );
$akStunden   = "0" . $akStunden if ( $akStunden < 10 );
$akMinuten   = "0" . $akMinuten if ( $akMinuten < 10 );

our $top_priority_script    = 'Top priority';
our $middle_priority_script = 'Middle priority';
our $lowest_priority_script = 'Lowest priority';

our $dbh;    # DatenbaaseHandler

###############################
# variables for one article
###############################

$page_number = $page_number + 1;
our $title         = q{};    # title of the current article
our $page_id       = -1;     # page id of the current article
our $revision_id   = -1;     # revision id of the current article
our $revision_time = -1;     # revision time of the current article
our $text          = q{};    # text of the current article  (for work)
our $text_origin   = q{};    # text of the current article origin (for save)
our $text_without_comments =
  q{};    # text of the current article without_comments (for save)

our $page_namespace;    # namespace of page
our $page_is_redirect       = 'no';
our $page_is_disambiguation = 'no';

our $page_categories = q{};
our $page_interwikis = q{};

our $page_has_error    = 'no';    # yes/no  error in this page
our $page_error_number = -1;      # number of all article for this page

our @comments;                    # 0 pos_start
                                  # 1 pos_end
                                  # 2 comment
our $comment_counter = -1;        #number of comments in this page

our @category;                    # 0 pos_start
                                  # 1 pos_end
                                  # 2 category	Test
                                  # 3 linkname	Linkname
                                  # 4 original	[[Category:Test|Linkname]]

our $category_counter = -1;
our $category_all     = q{};      # all categries

our @interwiki;                   # 0 pos_start
                                  # 1 pos_end
                                  # 2 interwiki	Test
                                  # 3 linkname	Linkname
                                  # 4 original	[[de:Test|Linkname]]
                                  # 5 language

our $interwiki_counter = -1;

our @lines;                       # text seperated in lines
our @headlines;                   # headlines
our @section;                     # text between headlines
undef(@section);

our @lines_first_blank;           # all lines where the first character is ' '

our @templates_all;               # all templates
our @template;                    # templates with values
                                  # 0 number of template
                                  # 1 templatename
                                  # 2 template_row
                                  # 3 attribut
                                  # 4 value
our $number_of_template_parts = -1;    # number of all template parts

our @links_all;                        # all links
our @images_all;                       # all images
our @isbn;                             # all ibsn of books
our @ref;                              # all ref

our $page_has_geo_error    = 'no';     # yes/no   geo error in this page
our $page_geo_error_number = -1;       # number of all article for this page

our $end_of_dump =
  'no';    # when last article from dump scan then 'yes', else 'no'
our $end_of_live =
  'no';    # when last article from live scan then 'yes', else 'no'

our $statistic_online_page =
  -1;      # number of pages online from metadata-statistic

###########################################################################
###
############################################################################

sub get_time_string {
    return strftime( '%Y%m%d %H%M%S', localtime() );
}

###########################################################################
## OPEN DATABASE
###########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : '' ),
        $DbUsername,
        $DbPassword,
        {
            RaiseError => 1,
            AutoCommit => 1
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
## LOAD ARTICLE FOR LIVE SCAN
###########################################################################

sub load_article_for_live_scan {
    print_line();
    two_column_display( 'Load article for:', 'live scan' )
      if ( !$silent_modus );

    # Get 250 new articles last days.
    new_article(250) if ($load_modus_new);

    # Get 50 change articles last days.
    last_change_article(50) if ($load_modus_last_change);

    # Get 250 articles which are set as done in the database
    # which are not Scan_Live.
    get_done_article_from_database(250) if ($load_modus_done);

    # Get 250 articles which are the date of last_scan is very old.
    get_oldest_article_from_database(250) if ($load_modus_old);

    # Sort all articles.
    @live_article = sort (@live_article);

    # Delete all double/multi input article
    my ( $all_errors_of_this_article, @new_live_article, $old_title );
    foreach my $Line (@live_article) {
        $Line =~ /^([^\t]+)\t(\d+)\n?$/ || die("Couldn't parse '$Line'\n");

        my ( $current_title, $current_errors ) = ( $1, $2 );

        if ( defined($old_title) && $old_title ne $current_title ) {

            # Save old line.
            push( @new_live_article,
                $old_title . "\t" . $all_errors_of_this_article );
            $all_errors_of_this_article = $current_errors;
            $old_title                  = $current_title;
        }
        else {
            $all_errors_of_this_article .= ', ' . $current_errors;
        }
    }

    # Save last line.
    if ( defined($old_title) ) {
        push( @new_live_article,
            $old_title . "\t" . $all_errors_of_this_article );
    }

    @live_article = @new_live_article;
    two_column_display( 'all articles without double:', scalar(@live_article) );

    if ( !@live_article ) {

        # If no articles were found, end the scan.
        die("No articles in scan list for live\n");
    }

    return ();
}

###########################################################################
## NEW ARTICLE
###########################################################################

sub new_article {
    my ($limit) = @_;

# oldest not scanned article
# select distinct title from cw_new where scan_live = 0 and project = 'dewiki' and daytime >= (select daytime from cw_new where scan_live = 0 and project = 'dewiki' order by daytime limit 1) order by daytime limit 250;

    $for_statistic_new_article = 0;

    my $sth = $dbh->prepare(
'SELECT DISTINCT Title FROM cw_new WHERE Scan_Live = 0 AND Project = ? AND Daytime >= (SELECT Daytime FROM cw_new WHERE Scan_Live = 0 AND Project = ? ORDER BY Daytime LIMIT 1) ORDER BY Daytime LIMIT ?;'
    ) || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $project, $project, $limit )
      or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $r = $sth->fetchrow_arrayref() ) {
        push( @live_article, $r->[0] . "\t0" );
        $for_statistic_new_article++;
    }
    two_column_display( 'from db articles new:', $for_statistic_new_article );

    return ();
}

###########################################################################
##
###########################################################################

sub last_change_article {
    my ($limit) = @_;

# oldest not scanned article
# select distinct title from cw_new where scan_live = 0 and project = 'dewiki' and daytime >= (select daytime from cw_new where scan_live = 0 and project = 'dewiki' order by daytime limit 1) order by daytime limit 250;

    $for_statistic_last_change_article = 0;

    my $sth = $dbh->prepare(
'SELECT DISTINCT Title FROM cw_change WHERE Scan_Live = 0 AND Project = ? AND Daytime >= (SELECT Daytime FROM cw_change WHERE Scan_Live = 0 AND Project = ? ORDER BY Daytime LIMIT 1) ORDER BY Daytime LIMIT ?;'
    ) || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $project, $project, $limit )
      or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $r = $sth->fetchrow_arrayref() ) {
        push( @live_article, $r->[0] . "\t0" );
        $for_statistic_last_change_article++;
    }
    two_column_display( 'from db articles changed:',
        $for_statistic_last_change_article );

    return ();
}

###########################################################################
##
###########################################################################

sub geo_error_article {

    # get all last_change article last days
    # Load last change articles
    my $file_geo       = $project . '_' . $error_geo_list_filename;
    my $file_input_geo = $output_geo . $project . '/' . $file_geo;

    #print $file_input_new."\n";
    my $geo_counter = 0;
    if ( -e $file_input_geo ) {

        #if existing
        #print 'file exist'."\n";
        open( my $input_geo, "<", $file_input_geo );
        do {
            my $line = <$input_geo>;
            if ($line) {
                $line =~ s/\n$//g;
                my @split_line = split( /\t/, $line );
                my $number_of_parts = @split_line;
                if ( $number_of_parts > 0 ) {
                    push( @live_article, $split_line[0] . "\t" . '0' );
                    $geo_counter++;
                }
            }
        } until ( eof($input_geo) == 1 );
        close($input_geo);
    }
    two_column_display( 'from file articles geo:', $geo_counter );
    print ' (no file: ' . $file_geo . ' )' if not( -e $file_input_geo );
    print "\n";
    $for_statistic_geo_article = $geo_counter;

    return ();
}

###########################################################################
##
###########################################################################

sub article_with_error_from_dump_scan {
    my $database_dump_scan_counter = 0;
    my $limit                      = 250;

# oldest not scanned article
# select distinct title from cw_new where scan_live = 0 and project = 'dewiki' and daytime >= (select daytime from cw_new where scan_live = 0 and project = 'dewiki' order by daytime limit 1) order by daytime limit 250;

    my $sth = $dbh->prepare(
'SELECT DISTINCT Title FROM cw_dumpscan WHERE Scan_Live = 0 AND Project = ? LIMIT ?;'
    ) || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $project, $limit )
      or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $r = $sth->fetchrow_arrayref() ) {
        push( @live_article, $r->[0] . "\t0" );
        $database_dump_scan_counter++;
    }

    two_column_display( 'from db articles (not scan live):',
        $database_dump_scan_counter );

#print "\t".$database_dump_scan_counter."\t".'articles from dump (not scan live) from db'."\n";

    return ();
}

###########################################################################
##
###########################################################################

sub get_done_article_from_database {
    my ($limit) = @_;
    my $database_ok_counter = 0;

    my $sth = $dbh->prepare(
        'SELECT Title FROM cw_error WHERE Ok = 1 AND Project = ? LIMIT ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $project, $limit )
      or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $r = $sth->fetchrow_arrayref() ) {
        push( @live_article, $r->[0] . "\t0" );
        $database_ok_counter++;
    }
    two_column_display( 'from db done articles:', $database_ok_counter );

    return ();
}

###########################################################################
##
###########################################################################

sub get_oldest_article_from_database {
    my ($limit) = @_;
    my $database_ok_counter = 0;

    my $sth = $dbh->prepare(
'SELECT Title FROM cw_error WHERE Project = ? AND DATEDIFF(NOW(), Found) > 31 ORDER BY DATEDIFF(NOW(), Found) DESC LIMIT ?;'
    ) || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $project, $limit )
      or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $r = $sth->fetchrow_arrayref() ) {
        push( @live_article, $r->[0] . "\t0" );
        $database_ok_counter++;
    }
    two_column_display( 'from db old articles:', $database_ok_counter );

    return ();
}

###########################################################################
##
###########################################################################

sub scan_pages {

    # get the text of the next page
    print_line();
    print 'Start scanning' . "\n" if ( !$silent_modus );

    $end_of_dump = 'no';
    $end_of_live = 'no';

    my $page = q{};

    if ( $dump_or_live eq 'dump' ) {
        while ( defined( $page = $pages->next ) || $end_of_dump eq 'no' ) {
            next unless $page->namespace eq '';
            update_ui() if ++$artcount % 500 == 0;
            set_variables_for_article();
            $page_namespace = 0;

            $title = case_fixer( $page->title );
            $text  = ${ $page->text };
            check_article();
            $end_of_dump = 'yes' if ( $artcount > 10000 );
        }
    }
    elsif ( $dump_or_live eq 'live' ) {
        do {
            set_variables_for_article();
            get_next_page_from_live();
            check_article();
          } until (
            $end_of_live eq 'yes'

              #or $page_number > 2000
              #or ($error_counter > 10000 and $project ne 'dewiki')
              #or $page_id  > 7950
              #or ($error_counter > 40000)
          );
    }

    print 'articles scan finish' . "\n\n" if ( !$silent_modus );

    return ();
}

###########################################################################
##
###########################################################################

sub update_ui {
    my $seconds = time - $start;
    my $bytes   = $pages->current_byte;

    print "  ", pretty_number($artcount), " articles; ";
    print pretty_bytes($bytes), " processed; ";

    if ( defined($file_size) ) {
        my $percent = int( $bytes / $file_size * 100 );

        print "$percent% completed\n";
    }
    else {
        my $bytes_per_second = int( $bytes / $seconds );
        print pretty_bytes($bytes_per_second), " per second\n";
    }

    return ();
}

###########################################################################
###
###########################################################################

sub pretty_number {
    my $number = reverse(shift);
    $number =~ s/(...)/$1,/g;
    $number = reverse($number);
    $number =~ s/^,//;

    return $number;

}

###########################################################################
###
##########################################################################

sub pretty_bytes {
    my ($bytes) = @_;
    my $pretty = int($bytes) . ' bytes';

    if ( ( $bytes = $bytes / 1024 ) > 1 ) {
        $pretty = int($bytes) . ' kilobytes';
    }

    if ( ( $bytes = $bytes / 1024 ) > 1 ) {
        $pretty = sprintf( "%0.2f", $bytes ) . ' megabytes';
    }

    if ( ( $bytes = $bytes / 1024 ) > 1 ) {
        $pretty = sprintf( "%0.4f", $bytes ) . ' gigabytes';
    }

    return ($pretty);
}

###########################################################################
###
###########################################################################

sub case_fixer {
    my ($my_title) = @_;

    #check for namespace
    if ( $my_title =~ /^(.+?):(.+)/ ) {
        $my_title = $1 . ':' . ucfirst($2);
    }
    else {
        $my_title = ucfirst($title);
    }

    return ($my_title);
}

###########################################################################
##
###########################################################################

sub set_variables_for_article {
    $page_number   = $page_number + 1;
    $title         = q{};              # title of the current article
    $page_id       = -1;               # page id of the current article
    $revision_id   = -1;               # revision id of the current article
    $revision_time = -1;               # revision time of the current article
    $text          = q{};              # text of the current article  (for work)
    $text_origin = q{};    # text of the current article origin (for save)
    $text_without_comments =
      q{};    # text of the current article without_comments (for save)

    $page_is_redirect       = 'no';
    $page_is_disambiguation = 'no';

    $page_categories = q{};
    $page_interwikis = q{};

    $page_has_error    = 'no';    # yes/no  error in this page
    $page_error_number = -1;      # number of all article for this page

    undef(@comments);             # 0 pos_start
                                  # 1 pos_end
                                  # 2 comment
    $comment_counter = -1;        #number of comments in this page

    undef(@category);             # 0 pos_start
                                  # 1 pos_end
                                  # 2 category	Test
                                  # 3 linkname	Linkname
                                  # 4 original	[[Category:Test|Linkname]]

    $category_counter = -1;
    $category_all     = q{};      # all categries

    undef(@interwiki);            # 0 pos_start
                                  # 1 pos_end
                                  # 2 interwiki	Test
                                  # 3 linkname	Linkname
                                  # 4 original	[[de:Test|Linkname]]
                                  # 5 language

    $interwiki_counter = -1;

    undef(@lines);                # text seperated in lines
    undef(@headlines);            # headlines
    undef(@section);              # text between headlines

    undef(@lines_first_blank);    # all lines where the first character is ' '

    undef(@templates_all);        # all templates
    undef(@template);             # templates with values
                                  # 0 number of template
                                  # 1 templatename
                                  # 2 template_row
                                  # 3 attribut
                                  # 4 value
    $number_of_template_parts = -1;    # number of all template parts

    undef(@links_all);                 # all links
    undef(@images_all);                # all images
    undef(@isbn);                      # all ibsn of books
    undef(@ref);                       # all ref

    $page_has_geo_error    = 'no';     # yes/no  geo error in this page
    $page_geo_error_number = -1;       # number of all article for this page

    return ();
}

###########################################################################
##
###########################################################################

sub update_table_cw_error_from_dump {

    if ( $dump_or_live eq 'dump' ) {
        print 'move all article from cw_dumpscan into cw_error' . "\n";
        my $sth = $dbh->prepare('DELETE FROM cw_error WHERE Project = ?;')
          || die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

        $sth = $dbh->prepare(
"INSERT INTO cw_error (SELECT * FROM cw_dumpscan WHERE Project = ?);"
        ) || die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

        print 'delete all article from this project in cw_dumpscan' . "\n";
        $sth = $dbh->prepare("DELETE FROM cw_dumpscan WHERE Project = ?;")
          || die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";
    }

    return ();
}

###########################################################################
##
###########################################################################

sub delete_deleted_article_from_db {

    # Delete all deleted articles from database.

    # FIXME: This doesn't look right.  This deletes all rows where
    # Found is not in the same 10-day group as the current date.
    # --tl, 2013-06-01
    my $sth = $dbh->prepare(
"DELETE FROM cw_error WHERE Ok = 1 AND Project = ? AND Found NOT LIKE CONCAT('%', ?, '%');"
    ) || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $project, substr( get_time_string(), 0, 7 ) )
      or die "Cannot execute: " . $sth->errstr . "\n";

    return ();
}

###########################################################################
##
###########################################################################

sub delete_article_from_table_cw_new {

    # Delete all scanned or older than 7 days from this project.
    my $sth = $dbh->prepare(
'DELETE FROM cw_new WHERE Project = ? AND (Scan_Live = 1 OR DATEDIFF(NOW(), Daytime) > 7);'
    ) || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    # Delete all articles from don't scan projects.
    $sth =
      $dbh->prepare('DELETE FROM cw_new WHERE DATEDIFF(NOW(), Daytime) > 8;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    return ();
}

###########################################################################
##
###########################################################################

sub delete_article_from_table_cw_change {

    # Delete all scanned or older than three days from this project.
    my $sth = $dbh->prepare(
'DELETE FROM cw_change WHERE Project = ? AND (Scan_Live = 1 OR DATEDIFF(NOW(), Daytime) > 3);'
    ) || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    # Delete all articles from don't scan projects.
    $sth =
      $dbh->prepare('DELETE FROM cw_change WHERE DATEDIFF(NOW(), Daytime) > 8;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute() or die "Cannot execute: " . $sth->errstr . "\n";

    return ();
}

###########################################################################
##
###########################################################################

sub update_table_cw_starter {
    if ($starter_modus) {
        print "update_table_cw_starter\n" if ( !$silent_modus );
        if ( $error_counter > 0 ) {
            my $sth =
              $dbh->prepare( 'UPDATE cw_starter SET '
                  . 'Errors_Done = Errors_Done + ?, '
                  . 'Errors_New = Errors_New + ?, '
                  . 'Errors_Dump = Errors_Dump + ?, '
                  . 'Errors_Change = Errors_Change + ?, '
                  . 'Errors_Old = Errors_Old + ?, '
                  . 'Current_Run = ?, '
                  . 'Last_Run_Change = IF(?, TRUE, Last_Run_Change) '
                  . 'WHERE Project = ?);' )
              or die( $dbh->errstr() . "\n" );
            $sth->execute(
                $load_modus_done        ? $error_counter : 0,
                $load_modus_new         ? $error_counter : 0,
                $load_modus_dump        ? $error_counter : 0,
                $load_modus_last_change ? $error_counter : 0,
                $load_modus_old         ? $error_counter : 0,
                $error_counter,
                !$load_modus_new && $load_modus_last_change,
                $project
            );
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

# Read metadata from API.
sub ReadMetadata {

    # Calculate server name.
    my $ServerName = $project;
    if (
        !(
               $ServerName =~ s/^nds_nlwiki$/nds-nl.wikipedia.org/
            || $ServerName =~ s/^commonswiki$/commons.wikimedia.org/
            || $ServerName =~ s/^([a-z]+)wiki$/$1.wikipedia.org/
            || $ServerName =~ s/^([a-z]+)wikisource$/$1.wikisource.org/
            || $ServerName =~ s/^([a-z]+)wikiversity$/$1.wikiversity.org/
            || $ServerName =~ s/^([a-z]+)wiktionary$/$1.wiktionary.org/
        )
      )
    {
        die( "Couldn't calculate server name for project" . $project . "\n" );
    }

    my $url = 'http://' . $ServerName . '/w/api.php';
    print_line();
    two_column_display( 'load metadata from:', $url );
    $url .=
'?action=query&meta=siteinfo&siprop=general|namespaces|namespacealiases|statistics|magicwords&format=xml';

    my $UA       = LWP::UserAgent->new();
    my $Response = $UA->get($url);

    if ( !$Response->is_success() ) {
        die("Could not retrieve metadata\n");
    }

    my $Content = $Response->decoded_content( raise_error => 1 );
    if ( !defined($Content) ) {
        die("Could not decode content\n");
    }
    my $metatext = $Content;

    # Parse siteinfo to DOM.
    my $XMLParser = XML::LibXML->new or die( $! . "\n" );
    my $SiteInfo = $XMLParser->parse_string($Content) or die( $! . "\n" );

    # Extract sitename.
    my $sitename =
      ( $SiteInfo->findnodes(q!//api/query/general/@sitename!) )[0]->getData();
    two_column_display( 'Sitename:', $sitename ) if ( !$silent_modus );

    # Extract base.
    my $my_base =
      ( $SiteInfo->findnodes(q!//api/query/general/@base!) )[0]->getData();
    two_column_display( 'Base:', $my_base ) if ( !$silent_modus );
    $home = $my_base;
    $home =~ s/[^\/]+$//;

    # Get namespaces numbers and names (e. g., "6, Tabulator image").
    foreach my $Node ( $SiteInfo->findnodes(q!//api/query/namespaces/ns!) ) {
        my $id        = $Node->getAttribute('id');
        my $canonical = $Node->getAttribute('canonical');
        my $name      = $Node->textContent();

        $canonical = q{} if ( !defined($canonical) );

        # Store namespace.
        push( @namespace, [ $id, $name, $canonical ] );

        # Store special namespaces in convenient variables.
        if ( $id == 6 ) {
            @namespace_image = ( $name, $canonical );
        }
        elsif ( $id == 10 ) {
            @namespace_templates = ($name);
            push( @namespace_templates, $canonical ) if ( $name ne $canonical );
        }
        elsif ( $id == 14 ) {
            @namespace_cat = ($name);
            push( @namespace_cat, $canonical ) if ( $name ne $canonical );
        }
    }

    # Namespace aliases.
    foreach
      my $Node ( $SiteInfo->findnodes(q!//api/query/namespacealiases/ns!) )
    {
        my $id   = $Node->getAttribute('id');
        my $name = $Node->textContent();

        if ( $id == 6 ) {    # Alias for image?
            push( @namespace_image, $name );
        }
        elsif ( $id == 10 ) {    # Alias for template?
            push( @namespace_templates, $name );
        }
        elsif ( $id == 14 ) {    # Alias for category?
            push( @namespace_cat, $name );
        }

        # Store all aliases.
        push( @namespacealiases, [ $id, $name ] );
    }

    # Magicwords.
    @magicword_defaultsort     = get_magicword( $SiteInfo, 'defaultsort' );
    @magicword_img_thumbnail   = get_magicword( $SiteInfo, 'img_thumbnail' );
    @magicword_img_manualthumb = get_magicword( $SiteInfo, 'img_manualthumb' );
    @magicword_img_right       = get_magicword( $SiteInfo, 'img_right' );
    @magicword_img_left        = get_magicword( $SiteInfo, 'img_left' );
    @magicword_img_none        = get_magicword( $SiteInfo, 'img_none' );
    @magicword_img_center      = get_magicword( $SiteInfo, 'img_center' );
    @magicword_img_framed      = get_magicword( $SiteInfo, 'img_framed' );
    @magicword_img_frameless   = get_magicword( $SiteInfo, 'img_frameless' );
    @magicword_img_page        = get_magicword( $SiteInfo, 'img_page' );
    @magicword_img_upright     = get_magicword( $SiteInfo, 'img_upright' );
    @magicword_img_border      = get_magicword( $SiteInfo, 'img_border' );
    @magicword_img_sub         = get_magicword( $SiteInfo, 'img_sub' );
    @magicword_img_super       = get_magicword( $SiteInfo, 'img_super' );
    @magicword_img_link        = get_magicword( $SiteInfo, 'img_link' );
    @magicword_img_alt         = get_magicword( $SiteInfo, 'img_alt' );
    @magicword_img_width       = get_magicword( $SiteInfo, 'img_width' );
    @magicword_img_baseline    = get_magicword( $SiteInfo, 'img_baseline' );
    @magicword_img_top         = get_magicword( $SiteInfo, 'img_top' );
    @magicword_img_text_top    = get_magicword( $SiteInfo, 'img_text_top' );
    @magicword_img_middle      = get_magicword( $SiteInfo, 'img_middle' );
    @magicword_img_bottom      = get_magicword( $SiteInfo, 'img_bottom' );
    @magicword_img_text_bottom = get_magicword( $SiteInfo, 'img_text_bottom' );

    # Read statistics.
    $statistic_online_page =
      ( $SiteInfo->findnodes(q!//api/query/statistics/@pages!) )[0]->getData();
    two_column_display( 'pages online:', $statistic_online_page );

    return ();
}

###########################################################################
##
###########################################################################

sub get_magicword {
    my ( $SiteInfo, $key ) = @_;
    my @result;

    foreach my $Node (
        $SiteInfo->findnodes(
                q!//api/query/magicwords/magicword[@name = '!
              . $key
              . q!']/aliases/alias!
        )
      )
    {
        push( @result, $Node->textContent() );
    }

    return @result;
}

###########################################################################
##
###########################################################################

sub get_next_page_from_live {
    $current_live_article++;    #next article

    if ( $current_live_error_scan != 0 ) {

        # Error not 0 (new aricles, and last changes...)

        if (    $current_live_error_scan != 0
            and $current_live_article == $maximum_current_error_scan )
        {
# set number higher if not all 50 errors  found
#print 'Nr.'.$current_live_error_scan."\n";
#print 'Found at moment :'.$error_description[$current_live_error_scan][3]."\n";
#print 'Max allowed:'.$max_error_count."\n";
#print 'Max possible:'.$number_article_live_to_scan."\n";

            if ( $error_description[$current_live_error_scan][3] <
                $max_error_count )
            {
                # set higer maximum
                $maximum_current_error_scan =
                  $maximum_current_error_scan +
                  ( $max_error_count -
                      $error_description[$current_live_error_scan][3] );

                #print 'Set higher maximum: '.$maximum_current_error_scan."\n";
            }
            else {
                # stop scan
                save_errors_for_next_scan($current_live_article);

                #$rest_of_errors_not_scan_yet
                $current_live_article = -1;
            }
        }

        # find next error with articles
        if (   ( $current_live_error_scan > 0 and $current_live_article == -1 )
            or $current_live_article == $number_article_live_to_scan
            or $current_live_error_scan == -1 )
        {
            #print 'switch from error to error'."\n";

            $current_live_error_scan = 0
              if ( $current_live_error_scan == -1 );    #start with error 1

            do {
                $current_live_error_scan++;

                #print $current_live_error_scan."\n";
                @live_to_scan = ();
                if ( $error_description[$current_live_error_scan][3] <
                    $max_error_count )
                {
                    # only if not all found with new/change/last
                    get_all_error_with_number($current_live_error_scan);
                }
                else {
                    # if with new /change etc. we found for this error much
                    get_all_error_with_number($current_live_error_scan);
                    save_errors_for_next_scan(0);
                    @live_to_scan = ();
                }

                $number_article_live_to_scan = @live_to_scan;
              } until (
                $current_live_error_scan >= $number_of_error_description
                  or $number_article_live_to_scan > 0
              );

            $maximum_current_error_scan = $max_error_count;
            if ( $error_description[$current_live_error_scan][3] > 0 ) {

 #print 'More errors for error'.$current_live_error_scan."\n";
 #print 'At moment only :'.$error_description[$current_live_error_scan][3]."\n";
                $maximum_current_error_scan =
                  $max_error_count -
                  $error_description[$current_live_error_scan][3];

                #print 'Search now for more :'.$maximum_current_error_scan."\n";
            }
            $current_live_article = 0;
            $xml_text_from_api    = q{};

#print '#############################################################'."\n";
#print 'Error '.$current_live_error_scan.' :'."\t".$number_article_live_to_scan."\n" if ($number_article_live_to_scan > 0);
#print 'Max='.$maximum_current_error_scan."\n";
#print 'Available = '.$number_article_live_to_scan."\n";

        }
    }

    if (    $current_live_error_scan == 0
        and $current_live_article >= $number_article_live_to_scan )
    {
        # end of live, no more article to scan
        $end_of_live = 'yes';
    }

    if ( $current_live_error_scan >= $number_of_error_description ) {

# after check live all errors, then start with check of error 0 (new articles, last changes, ...)
        $current_live_article    = 0;
        $xml_text_from_api       = q{};
        $current_live_error_scan = 0;
        get_all_error_with_number($current_live_error_scan);
        $number_article_live_to_scan = @live_to_scan;

        #print 'Error 0 :'."\t".$number_article_live_to_scan."\n";
        $maximum_current_error_scan = $max_error_count;
    }

    #$number_article_live_to_scan = @live_to_scan;
    if (    $current_live_article < $number_article_live_to_scan
        and $number_article_live_to_scan > 0
        and $end_of_live ne 'yes' )
    {
        # there is an error with articles
        # now we get the next article

        if ( $xml_text_from_api eq '' ) {

            # if list of xml_text_from_api is empty, then load next ariticles
            #print 'Load next texts from API'."\n";
            my $many_titles    = q{};
            my $i              = $current_live_article;
            my $end_many_title = 'false';
            do {

                my $line       = $live_to_scan[$i];
                my @line_split = split( /\t/, $line );
                my $next_title = $line_split[0];
                printf( "\$next_title = %s\n", $next_title );
                $next_title  = replace_special_letters($next_title);
                $many_titles = $many_titles . '|' . uri_escape($next_title);
                $many_titles =~ s/^\|//;
                $i++;
                $end_many_title = 'true'
                  if ( $i == $number_article_live_to_scan );
                $end_many_title = 'true'
                  if ( $i == $current_live_article + 25 )
                  ;    # not more then 25 articles
                $end_many_title = 'true'
                  if ( length($many_titles) > 2000 )
                  ; # url length not too long (Problem ruwiki and other no latin letters    )
            } until ( $end_many_title eq 'true' );

            #print 'Many titles ='.$many_titles."\n";
            $xml_text_from_api = raw_text_more_articles($many_titles);
            $xml_text_from_api =~ s/^<\?xml version="1\.0"\?>//;
            $xml_text_from_api =~ s/^<api>//;
            $xml_text_from_api =~ s/^<query>//;
            $xml_text_from_api =~ s/^<pages>//;
            $xml_text_from_api =~ s/<\/api>$//;
            $xml_text_from_api =~ s/<\/query>$//;
            $xml_text_from_api =~ s/<\/pages>$//;

            #print $xml_text_from_api."\n";

        }

        # get next title and  text from xml_text_from_api
        if ( $xml_text_from_api ne '' ) {

            my $pos_end = index( $xml_text_from_api, '</page>' );
            if ( $pos_end > -1 ) {

                # normal page
                $text =
                  substr( $xml_text_from_api, 0, $pos_end + length('</page>') );
                $xml_text_from_api =
                  substr( $xml_text_from_api, $pos_end + length('</page>') );
            }
            else {
                # missing page
                # <page ns="0" title="ZBlu-ray Disc" missing="" />
                #print 'Missing Page'."\n";
                $pos_end = index( $xml_text_from_api, 'missing="" />' );
                $text =
                  substr( $xml_text_from_api, 0,
                    $pos_end + length('missing="" />') );
                $xml_text_from_api =
                  substr( $xml_text_from_api,
                    $pos_end + length('missing="" />') );
                if ( $pos_end == -1 ) {

                    #BIG PROBLEM
                    print 'WARNING: Big problem with API' . "\n";
                    $text              = q{};
                    $xml_text_from_api = q{};
                }
            }

            my $line = $live_to_scan[$current_live_article];
            my @line_split = split( /\t/, $line );
            $title = $line_split[0];

            #print $title ."\n";
            #print substr (  $text, 0, 150)."\n";

            if ( index( $text, 'title=' . '"' . $title . '"' ) == -1 ) {

                # the result from the api is in a other sort
                # know get the current title
                # for example <page pageid="2065519" ns="0" title=".380 ACP">
                #print "Old title:".$title ."\n";
                my $pos_title = index( $text, 'title="' );
                my $title_text = $text;
                $title_text =
                  substr( $title_text, $pos_title + length('title="') );
                $pos_title = index( $title_text, '"' );
                $title = substr( $title_text, 0, $pos_title );

                #print "New title:".$title;
                #print "\n\n";
                #print substr (  $text, 0, 150)."\n";
                #print "\n\n";

            }

            #print $title."\n";
            push( @article_was_scanned, $title );

            # get id
            my $test_id_pos = index( $text, 'pageid="' );
            if ( $test_id_pos > -1 ) {
                $page_id = substr( $text, $test_id_pos + length('pageid="') );
                $test_id_pos = index( $page_id, '"' );
                $page_id = substr( $page_id, 0, $test_id_pos );

                #print $page_id.' - '.$title."\n";
            }

            # get  text
            my $test = index( $text, '<rev timestamp="' );
            if ( $test > -1 ) {
                my $pos = index( $text, '">', $test );
                $text = substr( $text, $pos + 2 );

                #$text =~ s/<text xml:space="preserve">//g;
                $test = index( $text, '</rev>' );
                $text = substr( $text, 0, $test );
            }

            #revision_id
            #revision_time
            #print $text."\n";
            #print substr($text, 0, 60)."\n";
            $text = replace_special_letters($text);
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub save_errors_for_next_scan {
    my ($from_number) = @_;
    $number_article_live_to_scan = @live_to_scan;

    for ( my $i = $from_number ; $i < $number_article_live_to_scan ; $i++ ) {

        #print $live_to_scan[$i]."\n";

        my $line = $live_to_scan[$i];

        #print '1:'.$line."\n";
        my @line_split = split( /\t/, $line );
        my $rest_title = $line_split[0];
        $rest_of_errors_not_scan_yet =
            $rest_of_errors_not_scan_yet . "\n"
          . $rest_title . "\t"
          . $current_live_error_scan;
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_all_error_with_number {

# get from array "live_article" with all errors, only this errors with error number X
    my ($error_live) = @_;

    #print 'Error number: '.$error_live."\n";

    my $number_of_article = @live_article;

    #print $number_of_article."\n";
    #print $live_article[0]."\n";

    if ( $number_of_article > 0 ) {
        for ( my $i = 0 ; $i < $number_of_article ; $i++ ) {
            my $current_live_line = $live_article[$i];

            #print $current_live_line."\n";
            my @line_split = split( /\t/, $current_live_line );

            #print 'alle:'.$line_split[1]."\n" if ($error_live == 0);
            my @split_error = split( ', ', $line_split[1] );
            my $found = 'no';
            foreach (@split_error) {
                if ( $error_live eq $_ ) {

                    #found error with number X
                    $found = 'yes';

                    #print $current_live_line."\n" if ($error_live == 0);
                }
            }
            if ( $found eq 'yes' ) {

                # article has error X
                #print 'found '.$current_live_line."\n"  if ($error_live == 7);

                # was this article scanned today ?
                $found = 'no';
                my $number_of_scanned_articles = @article_was_scanned;

                #print 'Scanned: '."\t".$number_of_scanned_articles."\n";
                foreach (@article_was_scanned) {

                    #print $_."\n";
                    if ( index( $current_live_line, $_ . "\t" ) == 0 ) {

                        #article was in this run scanned
                        $found = 'yes';

                        #print 'Was scanned :'."\t".$current_live_line."\n";
                    }
                }
                if ( $found eq 'no' ) {
                    push( @live_to_scan, $current_live_line );    #."\t".$i
                }
            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub replace_special_letters {
    my ($content) = @_;

# only in dump must replace not in live
# http://de.wikipedia.org/w/index.php?title=Benutzer_Diskussion:Stefan_K%C3%BChn&oldid=48573921#Dump
    $content =~ s/&lt;/</g;
    $content =~ s/&gt;/>/g;
    $content =~ s/&quot;/"/g;
    $content =~ s/&#039;/'/g;
    $content =~ s/&amp;/&/g;

    # &lt; -> <
    # &gt; -> >
    # &quot;  -> "
    # &#039; -> '
    # &amp; -> &
    return ($content);
}

###########################################################################
##
###########################################################################

sub raw_text {
    my ($my_title) = @_;

    $my_title =~ s/&amp;/%26/g;    # Problem with & in title
    $my_title =~ s/&#039;/'/g;     # Problem with apostroph in title
    $my_title =~ s/&lt;/</g;
    $my_title =~ s/&gt;/>/g;
    $my_title =~ s/&quot;/"/g;

# http://localhost/~daniel/WikiSense/WikiProxy.php?wiki=$lang.wikipedia.org&title=$article
    my $url2 = q{};

#$url2 = 'http://localhost/~daniel/WikiSense/WikiProxy.php?wiki=de.wikipedia.org&title='.$title;
    $url2 = $home;
    $url2 =~ s/\/wiki\//\/w\//;

    # old  	$url2 = $url2.'index.php?title='.$title.'&action=raw';
    $url2 =
        $url2
      . 'api.php?action=query&prop=revisions&titles='
      . $my_title
      . '&rvprop=timestamp|content&format=xml';

    #print $url2."\n";

    my $response2;

    #do {
    uri_escape($url2);

    #print $url2."\n";
    #uri_escape( join ' ' => @ARGV );
    my $ua2 = LWP::UserAgent->new;
    $response2 = $ua2->get($url2);

    #}
    #until ($response2->is_success);
    my $content2 = $response2->content;
    my $result2  = q{};
    $result2 = $content2 if ($content2);

    return ($result2);
}

###########################################################################
##
###########################################################################

sub raw_text_more_articles {
    my ($my_title) = @_;

    #$my_title =~ s/&amp;/%26/g;		# Problem with & in title
    #$my_title =~ s/&#039;/'/g;			# Problem with apostroph in title
    #$my_title =~ s/&lt;/</g;
    #$my_title =~ s/&gt;/>/g;
    #$my_title =~ s/&quot;/"/g;
    #$my_title =~ s/&#039;/'/g;

    my $url2 = q{};
    $url2 = $home;
    $url2 =~ s/\/wiki\//\/w\//;
    $url2 =
        $url2
      . 'api.php?action=query&prop=revisions&titles='
      . $my_title
      . '&rvprop=timestamp|content&format=xml';

    printf( "\$url2 = %s\n", $url2 );
    my $response2;
    my $ua2 = LWP::UserAgent->new;
    $response2 = $ua2->get($url2);
    my $content2 = $response2->content;
    my $result2  = q{};
    $result2 = $content2 if ($content2);
    return ($result2);
}

###########################################################################
##
###########################################################################

sub output_little_statistic {
    print 'errors found:' . "\t\t" . $error_counter . " (+1)\n";

    return ();
}

###########################################################################
##
###########################################################################

sub output_duration {
    $time_end = time();
    my $duration         = $time_end - $time_start;
    my $duration_minutes = int( $duration / 60 );
    my $duration_secounds =
      int( ( ( int( 100 * ( $duration / 60 ) ) / 100 ) - $duration_minutes ) *
          60 );

    print 'Duration:' . "\t\t"
      . $duration_minutes
      . ' minutes '
      . $duration_secounds
      . ' secounds' . "\n";
    print $project. ' ' . $dump_or_live . "\n" if ( !$silent_modus );

    return ();
}

###########################################################################
##
###########################################################################

sub check_article {
    my $steps = 1;
    $steps = 5000 if ( $silent_modus eq 'silent' );

    if (   $title eq 'At-Tabarī'
        or $title eq 'Rumänien'
        or $title eq 'Liste der Ortsteile im Saarland' )
    {
        # $details_for_page = 'yes';
    }

    my $text_for_tests = "Hallo
Barnaby, Wendy. The Plague Makers: The Secret World of Biological Warfare, Frog Ltd, 1999. 
in en [[Japanese war crimes]]
<noinclude>
</noinclude>
{{DEFAULTSORT:Role-playing game}}
=== Test ===
<onlyinclude></onlyinclude>
<includeonly></includeonly>
ISBN 1-883319-85-4 ISBN 0-7567-5698-7 ISBN 0-8264-1258-0 ISBN 0-8264-1415-X
* Tulku - ISBN 978 90 04 12766 0 (wrong ISBN)
:-sdfsdf[[http://www.wikipedia.org Wikipedia]] chack tererh
:#sadf
ISBN 3-8304-1007-7  ok
ISBN 3-00-016815-X  ok 
ISBN 978-0-8330-3930-9  ok
ISBN3-00-016815-X
[[Category:abc]] and [[Category:Abc]]&auml
[[1911 př. n. l.|1911]]–[[1897 př. n. l.|1897]] př. n. l.
Rodné jméno = <hiero><--M17-Y5:N35-G17-F4:X1--></hiero> <br />
Trůnní jméno = <hiero>M23-L2-<--N5:S12-D28*D28:D28--></hiero><br />
<references group='Bild' />&Ouml  124345
===This is a headline with reference <ref>A reference with '''bold''' text</ref>===
Nubkaure 
<hiero>-V28-V31:N35-G17-C10-</hiero>
Jméno obou paní = &uuml<hiero>-G16-V28-V31:N35-G17-C10-</hiero><br />
[[Image:logo|thumb| < small> sdfsdf</small>]]
<ref>Abu XY</ref>

im text ISBN 3-8304-1007-7 im text  <-- ok
im text ISBN 3-00-016815-X im text   ok
im text ISBN 978-0-8330-3930-9 im text   ok
[[Image:logo|thumb| Part < small> Part2</small> Part2]]
[[Image:logo|thumb| Part < small> Part</small>]]
ISBN-10 3-8304-1007-7	   bad
ISBN-10: 3-8304-1007-7	   bad
ISBN-13 978-0-8330-3930-9	   bad
ISBN-13: 978-0-8330-3930-9	-->bad
<ref>Abu XY</ref>

ISBN 123451678XXXX 	bad
ISBN 123456789x 	ok
ISBN 3-00-0168X5-X  bad

*ISBN 3-8304-1007-7 121 Test ok
*ISBN 3-8304-1007-7121 Test bad
*ISBN 3 8304 1007 7 121 Test ok
*ISBN 978-0-8330-39 309 Test ok
*ISBN 9 7 8 0 8 3 3 0 3 9 3 0 9 Test bad 10 ok 13

[http://www.dehoniane.it/edb/cat_dettaglio.php?ISBN=24109]	bad
{{test|ISBN=3 8304 1007 7 121 |test=[[text]]}}	bad
[https://www5.cbonline.nl/pls/apexcop/f?p=130:1010:401581703141772 ISBN-bureau] bad

	
ISBN 3-8304-1007-7

<\br>
</br>
[[:hu:A Gibb fivérek által írt dalok listája]] Big Problem
[[en:Supermann]]
testx
=== Liste ===
test
=== 1Acte au sens d'''instrumentum'' ===
<math>tesxter</math>
=== 2Acte au sens d'''instrumentum''' ===

 
	
== 3Acte au sens d''instrumentum'' ==

ISBN 978-88-10-24109-7

* ISBN 0-691-11532-X ok
* ISBN 123451678XXXX bad
* ISBN-10 1234567890 bad
* ISBN-10: 1234567890 bad
* ISBN-13 1234567890123 bad
* ISBN-13: 1234567890123 bad
* ISBN 123456789x Test ok
* ISBN 123456789x x12 Test
* ISBN 123456789012x Test
* ISBN 1234567890 12x Test
* ISBN 123456789X 123 Test
* ISBN 1 2 3 4 5 6 7 8 9 0 Test

[http://www.dehoniane.it/edb/cat_dettaglio.php?ISBN=24109]
[https://www5.cbonline.nl/pls/apexcop/f?p=130:1010:401581703141772 ISBN-bureau]

* Tramlijn_Ede_-_Wageningen - ISBN-nummer
* Tulku - ISBN 978 90 04 12766 0 (wrong ISBN)
* Michel_Schooyans - [http://www.dehoniane.it/edb/cat_dettaglio.php?ISBN=24109]
*VARA_gezinsencyclopedie - [https://www5.cbonline.nl/pls/apexcop/f?p=130:1010:401581703141772 ISBN-bureau]


Testtext hat einen [[|Link]], der nirgendwo hinführt.<ref>Kees Heitink en Gert Jan Koster, De tram rijdt weer!: Bennekomse tramgeschiedenis 1882 - 1937 - 1968 - 2008, 28 bladzijden, geen ISBN-nummer, uitverkocht.</ref>.
=== 4Acte au sens d''instrumentum'' ===
[[abszolútérték-függvény||]] ''f''(''x'') – ''f''(''y'') [[abszolútérték-függvény||]] aus huwiki
 * [[Antwerpen (stad)|Antwerpen]] heeft na de succesvolle <BR>organisatie van de Eurogames XI in [[2007]] voorstellen gedaan om editie IX van de Gay Games in [[2014]] of eventueel de 3e editie van de World OutGames in [[2013]] naar Antwerpen te halen. Het zogeheten '[[bidbook]]' is ingediend en het is afwachten op mogelijke toewijzing door de internationale organisaties. <br>
*a[[B:abc]]<br>
*bas addf< br>
*casfdasdf< br >
*das fdasdf< br / >
[[Che&#322;mno]] and 
sdfsf ISBN 3434462236   
95-98. ISBN 0 7876 5784 0. .
=== UNO MANDAT ===
0-13-110370-9
* [http://www.research.att.com/~bs/3rd.html The C++ Programming Language]: [[Bjarne Stroustrup]], special ed., Addison-Weslye, ISBN 0-201-70073-5, 2000
* The C++ Standard, Incorporating Technical Corrigendum 1, BS ISO/IEC 14882:2003 (2nd ed.), John Wiley & Sons, ISBN 0-470-84674-7
* [[Brian Kernighan|Brian W. Kernighan]], [[Dennis Ritchie|Dennis M. Ritchie]]: ''[[The C Programming Language]]'', Second Edition, Prentice-Hall, ISBN 0-13-110370-9 1988
* [http://kmdec.fjfi.cvut.cz/~virius/publ-list.html#CPP Programování v C++]: Miroslav Virius, [http://www.cvut.cz/cs/uz/ctn Vydavatelství ČVUT], druhé vydání, ISBN 80-01-02978-6 2004
* Naučte se C++ za 21 dní: Jesse Liberty, [http://www.cpress.cz/ Computer Press], ISBN 80-7226-774-4, 2002
* Programovací jazyk C++ pro zelenáče: Petr Šaloun, [http://www.neo.cz Neokortex] s.r.o., ISBN 80-86330-18-4, 2005
* Rozumíme C++: Andrew Koenig, Barbara E. Moo, [http://www.cpress.cz/ Computer Press], ISBN 80-7226-656-X, 2003
* [http://gama.fsv.cvut.cz/~cepek/uvodc++/uvodc++-2004-09-11.pdf Úvod do C++]: Prof. Ing. Aleš Čepek, CSc., Vydavatelství ČVUT, 2004
*eaa[[abc]]< br /  > 
<ref>sdfsdf</ref> .
Verlag LANGEWIESCHE, ISBN-10: 3784551912 und ISBN-13: 9783784551913 
=== Meine Überschrift ABN === ISBN 1234-X-1234
*fdd asaddf&hellip;</br 7> 
{{Zitat|Der Globus ist schön. <ref name='asda'>Buch 27</ref>}}
{{Zitat|Madera=1000 <ref name='asda'>Buch 27</ref>|Kolumbus{{Höhe|name=123}}|kirche=4 }}
==== Саларианцы ====
[[Breslau]] ([[Wroc&#322;aw]])
*gffasfdasdf<\br7>
{{Testvorlage|name=heeft na de succesvolle <BR>organisatie van de [[Eurogames XIa|Eurogames XI]] inheeft na de succesvolle <BR>organisatie van de Eurogames XI inheeft na de succesvolle <BR>organisatie van de Eurogames XI in123<br>|ott]o=kao}}
*hgasfda sdf<br />
<ref>sdfsdf2</ref>!
<br><br> 
===== PPM, PGM, PBM, PNM =====
===== PPM, PGM, PBM, PNM =====

" . 'test<br1/><br/1>&ndash;uberlappung<references />3456Ende des Text';

    #	$text = $text_for_tests;

    delete_old_errors_in_db();

    get_comments_nowiki_pre();

    get_math();
    get_source();
    get_code();
    get_syntaxhighlight();
    get_isbn();
    get_templates();
    get_links();
    get_images();
    get_tables();
    get_gallery();

    #get_hiero();    #problem with <-- and --> (error 056)
    get_ref();

    check_for_redirect();
    get_categories();
    get_interwikis();

    create_line_array();

    #get_line_first_blank();
    get_headlines();

    set_article_as_scan_live_in_db( $title, $page_id )
      if ( $dump_or_live eq 'live' );

    return ();
}

###########################################################################
## DELETE ARTICLE IN DATABASE
###########################################################################

sub delete_old_errors_in_db {
    if ( $dump_or_live eq 'live' && $page_id && $title ne '' ) {
        my $sth = $dbh->prepare(
            'DELETE FROM cw_error WHERE Error_ID = ? AND Project = ?;')
          || die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute( $page_id, $project )
          or die "Cannot execute: " . $sth->errstr . "\n";
    }

    return ();
}

###########################################################################
## SET THE NAMESPACE ID OF AN ARTICLE
###########################################################################

sub get_namespace {
    if ( $title =~ '^([^:]+):' ) {
        foreach my $Namespace (@namespace) {
            if ( $1 eq $Namespace->[1] || $1 eq $Namespace->[2] ) {
                $page_namespace = $Namespace->[0];

                return;
            }
        }

        foreach my $NamespaceAlias (@namespacealiases) {
            if ( $1 eq $NamespaceAlias->[1] ) {
                $page_namespace = $NamespaceAlias->[0];

                return;
            }
        }
    }

    # If no namespace prefix or not found.
    $page_namespace = 0;

    return ();
}

###########################################################################
##
###########################################################################

sub get_comments_nowiki_pre {
    my $last_pos    = -1;
    my $pos_comment = -1;
    my $pos_nowiki  = -1;
    my $pos_pre     = -1;
    my $pos_first   = -1;
    my $loop_again  = 0;
    do {

        # next tag
        $pos_comment = index( $text, '<!--',     $last_pos );
        $pos_nowiki  = index( $text, '<nowiki>', $last_pos );
        $pos_pre     = index( $text, '<pre>',    $last_pos );
        $pos_pre = index( $text, '<pre ', $last_pos ) if ( $pos_pre == -1 );

        #print $pos_comment.' '.$pos_nowiki.' '.$pos_pre."\n";

        #first tag
        my $tag_first = q{};
        $tag_first = 'comment' if ( $pos_comment > -1 );
        $tag_first = 'nowiki'
          if (
            ( $pos_nowiki > -1 and $tag_first eq '' )
            or (    $pos_nowiki > -1
                and $tag_first eq 'comment'
                and $pos_nowiki < $pos_comment )
          );
        $tag_first = 'pre'
          if (
            ( $pos_pre > -1 and $tag_first eq '' )
            or (    $pos_pre > -1
                and $tag_first eq 'comment'
                and $pos_pre < $pos_comment )
            or (    $pos_pre > -1
                and $tag_first eq 'nowiki'
                and $pos_pre < $pos_nowiki )
          );

        #print $tag_first."\n";

        #check end tag
        my $pos_comment_end =
          index( $text, '-->', $pos_comment + length('<!--') );
        my $pos_nowiki_end =
          index( $text, '</nowiki>', $pos_nowiki + length('<nowiki>') );
        my $pos_pre_end = index( $text, '</pre>', $pos_pre + length('<pre') );

        #comment
        if ( $tag_first eq 'comment' and $pos_comment_end > -1 ) {

            #found <!-- and -->
            $last_pos   = get_next_comment( $pos_comment + $last_pos );
            $loop_again = 1;

            #print 'comment'.' '.$pos_comment.' '.$last_pos."\n";
        }
        if ( $tag_first eq 'comment' and $pos_comment_end == -1 ) {

            #found <!-- and no -->
            $last_pos   = $pos_comment + 1;
            $loop_again = 1;

            #print 'comment no end'."\n";
            my $text_output = substr( $text, $pos_comment );
            $text_output = text_reduce( $text_output, 80 );
            error_005_Comment_no_correct_end( 'check', $text_output );

            #print $text_output."\n";
        }

        #nowiki
        if ( $tag_first eq 'nowiki' and $pos_nowiki_end > -1 ) {

            # found <nowiki> and </nowiki>
            $last_pos   = get_next_nowiki( $pos_nowiki + $last_pos );
            $loop_again = 1;

            #print 'nowiki'.' '.$pos_nowiki.' '.$last_pos."\n";
        }
        if ( $tag_first eq 'nowiki' and $pos_nowiki_end == -1 ) {

            # found <nowiki> and no </nowiki>
            $last_pos   = $pos_nowiki + 1;
            $loop_again = 1;

            #print 'nowiki no end'."\n";
            my $text_output = substr( $text, $pos_nowiki );
            $text_output = text_reduce( $text_output, 80 );
            error_023_nowiki_no_correct_end( 'check', $text_output );
        }

        #pre
        if ( $tag_first eq 'pre' and $pos_pre_end > -1 ) {

            # found <pre> and </pre>
            $last_pos   = get_next_pre( $pos_pre + $last_pos );
            $loop_again = 1;

            #print 'pre'.' '.$pos_pre.' '.$last_pos."\n";
        }
        if ( $tag_first eq 'pre' and $pos_pre_end == -1 ) {

            # found <pre> and no </pre>
            #print $last_pos.' '.$pos_pre."\n";
            $last_pos   = $pos_pre + 1;
            $loop_again = 1;

            #print 'pre no end'."\n";
            my $text_output = substr( $text, $pos_pre );
            $text_output = text_reduce( $text_output, 80 );
            error_024_pre_no_correct_end( 'check', $text_output );
        }

        #end
        if (    $pos_comment == -1
            and $pos_nowiki == -1
            and $pos_pre == -1 )
        {
            # found no <!-- and no <nowiki> and no <pre>
            $loop_again = 0;

        }
    } until ( $loop_again == 0 );
    $text_without_comments = $text;

    return ();
}

###########################################################################
##
###########################################################################

sub get_next_pre {

    #get position of next comment
    my $pos_start = index( $text, '<pre' );
    my $pos_end = index( $text, '</pre>', $pos_start );
    my $result = $pos_start + length('<pre');

    if ( $pos_start > -1 and $pos_end > -1 ) {

        #found a comment in current page
        $pos_end = $pos_end + length('</pre>');

#$comment_counter = $comment_counter +1;
#$comments[$comment_counter][0] = $pos_start;
#$comments[$comment_counter][1] = $pos_end;
#$comments[$comment_counter][2] = substr($text, $pos_start, $pos_end - $pos_start  );

#print 'Begin='.$comments[$comment_counter][0].' End='.$comments[$comment_counter][1]."\n";
#print 'Comment='.$comments[$comment_counter][2]."\n";

        #replace comment with space
        my $text_before = substr( $text, 0, $pos_start );
        my $text_after  = substr( $text, $pos_end );
        my $filler      = q{};
        for ( my $i = 0 ; $i < ( $pos_end - $pos_start ) ; $i++ ) {
            $filler = $filler . ' ';
        }
        $text   = $text_before . $filler . $text_after;
        $result = $pos_end;
    }

    return ($result);
}

###########################################################################
##
###########################################################################

sub get_next_nowiki {

    #get position of next comment
    my $pos_start = index( $text, '<nowiki>' );
    my $pos_end = index( $text, '</nowiki>', $pos_start );
    my $result = $pos_start + length('<nowiki>');

    if ( $pos_start > -1 and $pos_end > -1 ) {

        #found a comment in current page
        $pos_end = $pos_end + length('</nowiki>');

        #replace comment with space
        my $text_before = substr( $text, 0, $pos_start );
        my $text_after  = substr( $text, $pos_end );
        my $filler      = q{};
        for ( my $i = 0 ; $i < ( $pos_end - $pos_start ) ; $i++ ) {
            $filler = $filler . ' ';
        }
        $text   = $text_before . $filler . $text_after;
        $result = $pos_end;
    }

    return ($result);
}

###########################################################################
##
###########################################################################

sub get_next_comment {
    my $pos_start = index( $text, '<!--' );
    my $pos_end = index( $text, '-->', $pos_start + length('<!--') );
    my $result = $pos_start + length('<!--');
    if ( $pos_start > -1 and $pos_end > -1 ) {

        #found a comment in current page
        $pos_end                       = $pos_end + length('-->');
        $comment_counter               = $comment_counter + 1;
        $comments[$comment_counter][0] = $pos_start;
        $comments[$comment_counter][1] = $pos_end;
        $comments[$comment_counter][2] =
          substr( $text, $pos_start, $pos_end - $pos_start );

        #print $comments[$comment_counter][2]."\n";

        #replace comment with space
        my $text_before = substr( $text, 0, $pos_start );
        my $text_after  = substr( $text, $pos_end );
        my $filler      = q{};
        for ( my $i = 0 ; $i < ( $pos_end - $pos_start ) ; $i++ ) {
            $filler = $filler . ' ';
        }
        $text   = $text_before . $filler . $text_after;
        $result = $pos_end;
    }

    return ($result);
}

###########################################################################
##
###########################################################################

sub get_math {
    my $pos_start_old = 0;
    my $pos_end_old   = 0;
    my $end_search    = 'yes';
    do {
        my $pos_start = 0;
        my $pos_end   = 0;
        $end_search = 'yes';

        #get position of next <math>
        $pos_start = index( lc($text), '<math>', $pos_start_old );
        my $pos_start2 = index( lc($text), '<math style=', $pos_start_old );
        my $pos_start3 = index( lc($text), '<math title=', $pos_start_old );
        my $pos_start4 = index( lc($text), '<math alt=',   $pos_start_old );

        #print $pos_start.' '. $pos_end .' '.$pos_start2."\n";
        if (
            $pos_start == -1
            or (    $pos_start > -1
                and $pos_start2 > -1
                and $pos_start > $pos_start2 )
          )
        {
            $pos_start = $pos_start2;
        }
        if (
            $pos_start == -1
            or (    $pos_start > -1
                and $pos_start3 > -1
                and $pos_start > $pos_start3 )
          )
        {
            $pos_start = $pos_start3;
        }
        if (
            $pos_start == -1
            or (    $pos_start > -1
                and $pos_start4 > -1
                and $pos_start > $pos_start4 )
          )
        {
            $pos_start = $pos_start4;
        }
        $pos_end = index( lc($text), '</math>', $pos_start + length('<math') );

        #print $pos_start.' '. $pos_end ."\n";
        if ( $pos_start > -1 and $pos_end > -1 ) {

            #found a math in current page
            $pos_end = $pos_end + length('</math>');

            #print substr($text, $pos_start, $pos_end - $pos_start  )."\n";

            $end_search    = 'no';
            $pos_start_old = $pos_end;

            #replace comment with space
            my $text_before = substr( $text, 0, $pos_start );
            my $text_after  = substr( $text, $pos_end );
            my $filler      = q{};
            for ( my $i = 0 ; $i < ( $pos_end - $pos_start ) ; $i++ ) {
                $filler = $filler . ' ';
            }
            $text = $text_before . $filler . $text_after;
        }
        if ( $pos_start > -1 and $pos_end == -1 ) {
            error_013_Math_no_correct_end( 'check',
                substr( $text, $pos_start, 50 ) );

            #print 'Math:'.substr( $text, $pos_start, 50)."\n";
            $end_search = 'yes';
        }

    } until ( $end_search eq 'yes' );

    return ();
}

###########################################################################
##
###########################################################################

sub get_source {
    my $pos_start_old = 0;
    my $pos_end_old   = 0;
    my $end_search    = 'yes';

    do {
        my $pos_start = 0;
        my $pos_end   = 0;
        $end_search = 'yes';

        #get position of next <math>
        $pos_start = index( $text, '<source', $pos_start_old );
        $pos_end = index( $text, '</source>', $pos_start + length('<source') );
        if ( $title eq 'ALTER' ) {
            print $pos_start. "\n";
            print $pos_end. "\n";
        }

        if ( $pos_start > -1 and $pos_end > -1 ) {

            #found a math in current page
            $pos_end = $pos_end + length('</source>');

            #print substr($text, $pos_start, $pos_end - $pos_start  )."\n";

            $end_search    = 'no';
            $pos_start_old = $pos_end;

            #replace comment with space
            my $text_before = substr( $text, 0, $pos_start );
            my $text_after  = substr( $text, $pos_end );
            my $filler      = q{};
            for ( my $i = 0 ; $i < ( $pos_end - $pos_start ) ; $i++ ) {
                $filler = $filler . ' ';
            }
            $text = $text_before . $filler . $text_after;
        }
        if ( $pos_start > -1 and $pos_end == -1 ) {
            error_014_Source_no_correct_end( 'check',
                substr( $text, $pos_start, 50 ) );

            #print 'Source:'.substr( $text, $pos_start, 50)."\n";
            $end_search = 'yes';
        }

    } until ( $end_search eq 'yes' );

    return ();
}

###########################################################################
##
###########################################################################

sub get_syntaxhighlight {
    my $pos_start_old = 0;
    my $pos_end_old   = 0;
    my $end_search    = 'yes';

    do {
        my $pos_start = 0;
        my $pos_end   = 0;
        $end_search = 'yes';

        #get position of next <math>
        $pos_start = index( $text, '<syntaxhighlight', $pos_start_old );
        $pos_end =
          index( $text, '</syntaxhighlight>',
            $pos_start + length('<syntaxhighlight') );
        if ( $title eq 'ALTER' ) {
            print $pos_start. "\n";
            print $pos_end. "\n";
        }

        if ( $pos_start > -1 and $pos_end > -1 ) {

            #found a math in current page
            $pos_end = $pos_end + length('</syntaxhighlight>');

            #print substr($text, $pos_start, $pos_end - $pos_start  )."\n";

            $end_search    = 'no';
            $pos_start_old = $pos_end;

            #replace comment with space
            my $text_before = substr( $text, 0, $pos_start );
            my $text_after  = substr( $text, $pos_end );
            my $filler      = q{};
            for ( my $i = 0 ; $i < ( $pos_end - $pos_start ) ; $i++ ) {
                $filler = $filler . ' ';
            }
            $text = $text_before . $filler . $text_after;
        }
        if ( $pos_start > -1 and $pos_end == -1 ) {

    #error_014_Source_no_correct_end ('check', substr( $text, $pos_start, 50) );
    #print 'Source:'.substr( $text, $pos_start, 50)."\n";
            $end_search = 'yes';
        }

    } until ( $end_search eq 'yes' );

    return ();
}

###########################################################################
##
###########################################################################

sub get_code {
    my $pos_start_old = 0;
    my $pos_end_old   = 0;
    my $end_search    = 'yes';
    do {
        my $pos_start = 0;
        my $pos_end   = 0;
        $end_search = 'yes';

        #get position of next <math>
        $pos_start = index( $text, '<code>',  $pos_start_old );
        $pos_end   = index( $text, '</code>', $pos_start );

        if ( $pos_start > -1 and $pos_end > -1 ) {

            #found a math in current page
            $pos_end = $pos_end + length('</code>');

            #print substr($text, $pos_start, $pos_end - $pos_start  )."\n";

            $end_search    = 'no';
            $pos_start_old = $pos_end;

            #replace comment with space
            my $text_before = substr( $text, 0, $pos_start );
            my $text_after  = substr( $text, $pos_end );
            my $filler      = q{};
            for ( my $i = 0 ; $i < ( $pos_end - $pos_start ) ; $i++ ) {
                $filler = $filler . ' ';
            }
            $text = $text_before . $filler . $text_after;
        }
        if ( $pos_start > -1 and $pos_end == -1 ) {
            error_015_Code_no_correct_end( 'check',
                substr( $text, $pos_start, 50 ) );

            #print 'Code:'.substr( $text, $pos_start, 50)."\n";
            $end_search = 'yes';
        }

    } until ( $end_search eq 'yes' );

    return ();
}

###########################################################################
##
###########################################################################

sub get_isbn {

    # get all isbn

    if (
            index( $text, 'ISBN' ) > 0
        and $title ne 'International Standard Book Number'
        and $title ne 'ISBN'
        and $title ne 'ISBN-10'
        and $title ne 'ISBN-13'
        and $title ne 'Internationaal Standaard Boeknummer'
        and $title ne 'International Standard Book Number'
        and $title ne 'European Article Number'
        and $title ne 'Internationale Standardbuchnummer'
        and $title ne 'Buchland'
        and $title ne 'Codice ISBN'
        and index( $title, 'ISBN' ) == -1

        # better with show too interwiki !!!

      )
    {
        my $text_test = $text;

       #print "\n\n".'###################################################'."\n";
        while ( $text_test =~ /ISBN([ ]|[-]|[=])/g ) {
            my $pos_start = pos($text_test) - 5;

            #print "\n\n";
            #print $pos_start."\n";
            my $current_isbn = substr( $text_test, $pos_start );

            my $output_isbn = substr( $current_isbn, 0, 50 );
            $output_isbn =~ s/\n/ /g;

            #print $output_isbn."\n";

            my $result_isbn = q{};
            my $i           = -1;
            my $finish      = 'no';

            #print 'isbn: '."\t".$current_isbn."\n";

            # \tab
            $current_isbn =~ s/\t/ /;

            if ( $current_isbn =~ /^([ ]+)?ISBN=([ ]+)?/ ) {

                #print 'ISBN in Link'."\n";
                # ISBN = 01234566 in templates
                $current_isbn =~ s/^([ ]+)?ISBN([ ]+)?=([ ]+)?/ /;

                #if ( length($current_isbn ) == 10

                my $pos_open  = index( $current_isbn, '[' );
                my $pos_close = index( $current_isbn, ']' );

                #print $pos_open."\n";
                #print $pos_close."\n";
                if (
                    ( $pos_open == -1 and $pos_close > -1 )
                    or (    $pos_open > -1
                        and $pos_close > -1
                        and $pos_open > $pos_close )
                  )
                {
# [[nl:Michel_Schooyans]] - [http://www.dehoniane.it/edb/cat_dettaglio.php?ISBN=24109]
#print "\t".'Get ISBN: ISBN in Link: '."\t"."\n";
                    $current_isbn = 'ISBN';
                }
            }

            if ( $current_isbn =~ /^([ ]+)?ISBN-[^1]/ ) {

                # text "ISBN-number"
                # text "ISBN-bureau"
                #print "\t".'Get ISBN: ISBN with Minus'."\t"."\n";
                $current_isbn = 'ISBN';
            }

            #print "\t".'Get ISBN 2: '."\t".substr($current_isbn, 0, 45)."\n";
            my $pos_next_ISBN = index( $current_isbn, 'ISBN', 4 );
            if ( $pos_next_ISBN > -1 ) {

#many ISBN behind the first ISBN
# "ISBN 1-883319-85-4 ISBN 0-7567-5698-7 ISBN 0-8264-1258-0 ISBN 0-8264-1415-X")
                $current_isbn = substr( $current_isbn, 0, $pos_next_ISBN );
            }
            $current_isbn =~ s/ISBN//g;

            #print "\t".'Get ISBN 2b: '."\t".substr($current_isbn, 0, 45)."\n";

            do {
                $i++;
                if ( $i <= length($current_isbn) ) {
                    my $character = substr( $current_isbn, $i, 1 );
                    if ( $character =~ /[ 0-9Xx\-]/ ) {
                        $result_isbn = $result_isbn . $character;
                    }
                    else {
                        $finish = 'yes';
                    }
                }
                else {
                    $finish = 'yes';
                }

            } until ( $finish eq 'yes' );

            if (    $result_isbn =~ /[^ ]/
                and $result_isbn =~ /[0-9]/ )
            {
                $result_isbn =~ s/^([ ]+)?//g;
                $result_isbn =~ s/([ ]+)?$//g;

                #print "\t".'Get ISBN 2: '."\t".$result_isbn."\n";
                push( @isbn, $result_isbn );
                check_isbn($result_isbn);
            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub check_isbn {
    my ($current_isbn) = @_;

    #print 'check: '."\t".$current_isbn."\n";
    # length
    my $test_isbn = $current_isbn;

    $test_isbn =~ s/^([ ]+)?//g;
    $test_isbn =~ s/([ ]+)?$//g;
    $test_isbn =~ s/[ ]//g;

    #print "\t".'Check ISBN 1: '."\t_".$test_isbn."_\n";
    my $result = 'yes';

    # length of isbn
    if ( $result eq 'yes' ) {
        if (   index( $test_isbn, '-10' ) == 0
            or index( $test_isbn, '-13' ) == 0 )
        {
            $result = 'no';
            error_069_isbn_wrong_syntax( 'check', $current_isbn );
        }
    }

    $test_isbn =~ s/-//g;

    #print "\t".'Check ISBN 2: '."\t_".$test_isbn."_\n";

    # wrong position of X
    if ( $result eq 'yes' ) {
        $test_isbn =~ s/x/X/g;
        if ( index( $test_isbn, 'X' ) > -1 ) {

            # ISBN with X
            #print "\t".'Check ISBN X: '."\t_".$test_isbn."_\n";
            if ( index( $test_isbn, 'X' ) != 9 ) {

                # ISBN 123456X890
                $result = 'no';
                error_071_isbn_wrong_pos_X( 'check', $current_isbn );
            }
            if ( index( $test_isbn, 'X' ) == 9
                and ( length($test_isbn) != 10 ) )
            {
                # ISBN 123451678XXXX b
                $test_isbn = substr( $test_isbn, 0, 10 );

                #print "\t".'Check ISBN X reduce length: '.$test_isbn."\n";
            }
        }
    }

    my $check_10      = 'no ok';
    my $check_13      = 'no ok';
    my $found_text_10 = q{};
    my $found_text_13 = q{};

    # Check Checksum 13
    if ( $result eq 'yes' ) {
        if ( length($test_isbn) >= 13
            and $test_isbn =~ /^[0-9]{13}/ )
        {
            my $checksum = 0;
            $checksum = $checksum + 1 * substr( $test_isbn, 0,  1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 1,  1 );
            $checksum = $checksum + 1 * substr( $test_isbn, 2,  1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 3,  1 );
            $checksum = $checksum + 1 * substr( $test_isbn, 4,  1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 5,  1 );
            $checksum = $checksum + 1 * substr( $test_isbn, 6,  1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 7,  1 );
            $checksum = $checksum + 1 * substr( $test_isbn, 8,  1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 9,  1 );
            $checksum = $checksum + 1 * substr( $test_isbn, 10, 1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 11, 1 );

            #print 'Checksum: '."\t".$checksum."\n";
            my $checker = 10 - substr( $checksum, length($checksum) - 1, 1 );
            $checker = 0 if ( $checker == 10 );

            #print $checker."\n";
            if ( $checker eq substr( $test_isbn, 12, 1 ) ) {
                $check_13 = 'ok';
            }
            else {
                $found_text_13 =
                    $current_isbn
                  . '</nowiki> || <nowiki>'
                  . substr( $test_isbn, 12, 1 ) . ' vs. '
                  . $checker;
            }
        }
    }

    # Check Checksum 10
    if ( $result eq 'yes' ) {
        if (    length($test_isbn) >= 10
            and $test_isbn =~ /^[0-9X]{10}/
            and $check_13 eq 'no ok' )
        {
            my $checksum = 0;
            $checksum = $checksum + 1 * substr( $test_isbn, 0, 1 );
            $checksum = $checksum + 2 * substr( $test_isbn, 1, 1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 2, 1 );
            $checksum = $checksum + 4 * substr( $test_isbn, 3, 1 );
            $checksum = $checksum + 5 * substr( $test_isbn, 4, 1 );
            $checksum = $checksum + 6 * substr( $test_isbn, 5, 1 );
            $checksum = $checksum + 7 * substr( $test_isbn, 6, 1 );
            $checksum = $checksum + 8 * substr( $test_isbn, 7, 1 );
            $checksum = $checksum + 9 * substr( $test_isbn, 8, 1 );

            #print 'Checksum: '."\t".$checksum."\n";
            my $checker = $checksum % 11;

            #print $checker."\n";
            if (   ( $checker < 10 and $checker ne substr( $test_isbn, 9, 1 ) )
                or ( $checker == 10 and 'X' ne substr( $test_isbn, 9, 1 ) ) )
            {
                # check wrong and 10 or more characters
                $found_text_10 =
                    $current_isbn
                  . '</nowiki> || <nowiki>'
                  . substr( $test_isbn, 9, 1 ) . ' vs. '
                  . $checker . ' ('
                  . $checksum
                  . ' mod 11)';
            }
            else {
                $check_10 = 'ok';
            }
        }
    }

    # length of isbn
    if ( $result eq 'yes'
        and not( $check_10 eq 'ok' or $check_13 eq 'ok' ) )
    {

        if (    $check_10 eq 'no ok'
            and $check_13 eq 'no ok'
            and length($test_isbn) == 10 )
        {
            $result = 'no';
            error_072_isbn_10_wrong_checksum( 'check', $found_text_10 );
        }

        if (    $check_10 eq 'no ok'
            and $check_13 eq 'no ok'
            and length($test_isbn) == 13 )
        {
            $result = 'no';
            error_073_isbn_13_wrong_checksum( 'check', $found_text_13 );
        }

        if (    $check_10 eq 'no ok'
            and $check_13 eq 'no ok'
            and $result   eq 'yes'
            and length($test_isbn) != 0 )
        {
            $result = 'no';
            error_070_isbn_wrong_length( 'check',
                $current_isbn . '</nowiki> || <nowiki>' . length($test_isbn) );
        }
    }

    #if ($result eq 'yes') {
    #	print "\t".'Check ISBN: all ok!'."\n";
    #} else {
    #	print "\t".'Check ISBN: wrong ISBN!'."\n";
    #}

    return ();
}

###########################################################################
##
###########################################################################

sub get_templates {

    # filter all templates
    my $pos_start = 0;
    my $pos_end   = 0;

    my $text_test = $text;

#$text_test = 'abc{{Huhu|name=1|otto=|die=23|wert=as|wertA=[[Dresden|Pesterwitz]] Mein|wertB=1234}}
#{{ISD|123}}  {{ESD {{Test|dfgvb}}|123}} {{tzu}} {{poil|ert{{eret|er}}|qwezh}} {{xtesxt} und außerdem
#{{Frerd|qwer=0|asd={{mytedfg|poil={{1234|12334}}}}|fgh=123}} und {{mnb|jkl=12|fgh=78|cvb=4567} Ende.';

    #print $text_test ."\n\n\n";

    $text_test =~ s/\n//g;    # delete all breaks  --> only one line
    $text_test =~ s/\t//g;    # delete all tabulator  --> better for output
    @templates_all = ();

    while ( $text_test =~ /\{\{/g ) {

        #Begin of template
        $pos_start = pos($text_test) - 2;
        my $temp_text             = substr( $text_test, $pos_start );
        my $temp_text_2           = q{};
        my $beginn_curly_brackets = 1;
        my $end_curly_brackets    = 0;
        while ( $temp_text =~ /\}\}/g ) {

            # Find currect end - number of {{ == }}
            $pos_end     = pos($temp_text);
            $temp_text_2 = substr( $temp_text, 0, $pos_end );
            $temp_text_2 = ' ' . $temp_text_2 . ' ';

            #print $temp_text_2."\n";

            # test the number of {{ and  }}
            my $temp_text_2_a = $temp_text_2;
            $beginn_curly_brackets = ( $temp_text_2_a =~ s/\{\{//g );
            my $temp_text_2_b = $temp_text_2;
            $end_curly_brackets = ( $temp_text_2_b =~ s/\}\}//g );

            #print $beginn_curly_brackets .' vs. '.$end_curly_brackets."\n";
            last if ( $beginn_curly_brackets eq $end_curly_brackets );
        }

        if ( $beginn_curly_brackets == $end_curly_brackets ) {

            # template is correct
            $temp_text_2 = substr( $temp_text_2, 1, length($temp_text_2) - 2 );

           #print 'Template:'.$temp_text_2."\n" if ($details_for_page eq 'yes');
            push( @templates_all, $temp_text_2 );
        }
        else {
            # template has no correct end
            $temp_text = text_reduce( $temp_text, 80 );
            error_043_template_no_correct_end( 'check', $temp_text );

            #print 'Error: '.$title.' '.$temp_text."\n";
        }
    }

    # extract for each template all attributes and values
    my $number_of_templates   = -1;
    my $template_part_counter = -1;
    my $output                = q{};
    foreach (@templates_all) {
        my $current_template = $_;

        #print 'Current templat:_'.$current_template."_\n";
        $current_template =~ s/^\{\{//;
        $current_template =~ s/\}\}$//;
        $current_template =~ s/^ //g;

        foreach (@namespace_templates) {
            $current_template =~ s/^$_://i;
        }

        $number_of_templates = $number_of_templates + 1;
        my $template_name = q{};

        my @template_split = split( /\|/, $current_template );
        my $number_of_splits = @template_split;

        if ( index( $current_template, '|' ) == -1 ) {

            # if no pipe; for example {{test}}
            $template_name = $current_template;
            next;
        }

        if ( index( $current_template, '|' ) > -1 ) {

            # templates with pipe {{test|attribute=value}}

            # get template name
            $template_split[0] =~ s/^ //g;
            $template_name = $template_split[0];

            #print 'Template name: '.$template_name."\n";
            if ( index( $template_name, '_' ) > -1 ) {

                #print $title."\n";
                #print 'Template name: '.$template_name."\n";
                $template_name =~ s/_/ /g;

                #print 'Template name: '.$template_name."\n";
            }
            if ( index( $template_name, '  ' ) > -1 ) {

                #print $title."\n";
                #print 'Template name: '.$template_name."\n";
                $template_name =~ s/  / /g;

                #print 'Template name: '.$template_name."\n";
            }

            shift(@template_split);

            # get next part of template
            my $template_part = q{};
            my @template_part_array;
            undef(@template_part_array);

            foreach (@template_split) {
                $template_part = $template_part . $_;

                #print "\t" . 'Test this templatepart: ' . $template_part . "\n"
                #  if ( $details_for_page eq 'yes' );

                # check for []
                my $template_part1 = $template_part;
                my $beginn_brackets = ( $template_part1 =~ s/\[\[//g );

                #print "\t\t1 ".$beginn_brackets."\n";

                my $template_part2 = $template_part;
                my $end_brackets = ( $template_part2 =~ s/\]\]//g );

                #print "\t\t2 ".$end_brackets."\n";

                #check for {}
                my $template_part3 = $template_part;
                my $beginn_curly_brackets = ( $template_part3 =~ s/\{\{//g );

                #print "\t\t3 ".$beginn_curly_brackets."\n";

                my $template_part4 = $template_part;
                my $end_curly_brackets = ( $template_part4 =~ s/\}\}//g );

                #print "\t\t4 ".$end_curly_brackets."\n";

                # templet part complete ?
                if (    $beginn_brackets eq $end_brackets
                    and $beginn_curly_brackets eq $end_curly_brackets )
                {

                    push( @template_part_array, $template_part );
                    $template_part = q{};
                }
                else {
                    $template_part = $template_part . '|';
                }

            }

            # OUTPUT If only templates {{{xy|value}}
            my $template_part_number           = -1;
            my $template_part_without_attribut = -1;

            foreach (@template_part_array) {
                $template_part = $_;

                #print "\t\t".'Template part: '.$_."\n";

                $template_part_number  = $template_part_number + 1;
                $template_part_counter = $template_part_counter + 1;

                $template_name =~ s/^[ ]+//g;
                $template_name =~ s/[ ]+$//g;
                $template[$template_part_counter][0] = $number_of_templates;
                $template[$template_part_counter][1] = $template_name;
                $template[$template_part_counter][2] = $template_part_number;

                my $attribut = q{};
                my $value    = q{};
                if ( index( $template_part, '=' ) > -1 ) {

                    #template part with "="   {{test|attribut=value}}

                    my $pos_equal     = index( $template_part, '=' );
                    my $pos_lower     = index( $template_part, '<' );
                    my $pos_next_temp = index( $template_part, '{{' );
                    my $pos_table     = index( $template_part, '{|' );
                    my $pos_bracket   = index( $template_part, '[' );

                    my $equal_ok = 'true';
                    $equal_ok = 'false'
                      if ( $pos_lower > -1 and $pos_lower < $pos_equal );
                    $equal_ok = 'false'
                      if (  $pos_next_temp > -1
                        and $pos_next_temp < $pos_equal );
                    $equal_ok = 'false'
                      if ( $pos_table > -1 and $pos_table < $pos_equal );
                    $equal_ok = 'false'
                      if ( $pos_bracket > -1 and $pos_bracket < $pos_equal );

                    if ( $equal_ok eq 'true' ) {

                        #template part with "="   {{test|attribut=value}}
                        $attribut =
                          substr( $template_part, 0,
                            index( $template_part, '=' ) );
                        $value =
                          substr( $template_part,
                            index( $template_part, '=' ) + 1 );
                    }
                    else {
                     # problem:  {{test|value<ref name="sdfsdf"> sdfhsdf</ref>}}
                     # problem   {{test|value{{test2|name=teste}}|sdfsdf}}
                        $template_part_without_attribut =
                          $template_part_without_attribut + 1;
                        $attribut = $template_part_without_attribut;
                        $value    = $template_part;
                    }
                }
                else {
                    #template part with no "="   {{test|value}}
                    $template_part_without_attribut =
                      $template_part_without_attribut + 1;
                    $attribut = $template_part_without_attribut;
                    $value    = $template_part;
                }

                $attribut =~ s/^[ ]+//g;
                $attribut =~ s/[ ]+$//g;
                $value    =~ s/^[ ]+//g;
                $value    =~ s/[ ]+$//g;

           #print 'x'.$attribut."x\tx".$value."x\n" ;#if ($title eq 'Methanol');
                $template[$template_part_counter][3] = $attribut;
                $template[$template_part_counter][4] = $value;

                $number_of_template_parts = $number_of_template_parts + 1;

                #print $number_of_template_parts."\n";

                $output .= $title . "\t";
                $output .= $page_id . "\t";
                $output .= $template[$template_part_counter][0] . "\t";
                $output .= $template[$template_part_counter][1] . "\t";
                $output .= $template[$template_part_counter][2] . "\t";
                $output .= $template[$template_part_counter][3] . "\t";
                $output .= $template[$template_part_counter][4] . "\n";

                #print $output."\n"  if ($title eq 'Methanol');
            }

        }

        #print "\n";
        # OUTPUT If all templates {{xy}} and {{xy|value}}

    }

    #print $output."\n"  if ($title eq 'Methanol');
    #print $page_namespace."\n"  if ($title eq 'Methanol');

    # Output for TemplateTiger
    if (
        $dump_or_live eq 'dump'
        and (  $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
      )
    {

        print $output if ( $details_for_page eq 'yes' );
        $TTFile->print($output);

# new in tt-table of database
# for (my $i = 0; $i <=$number_of_template_parts; $i++) {
#	insert_into_db_table_tt ($title, $page_id, $template[$i][0], $template[$i][1], $template[$i][2], $template[$i][3], $template[$i][4], $template[$i][5]);
#}

    }

    #die  if ($title eq 'Methanol');

    return ();
}

###########################################################################
##
###########################################################################

sub get_links {

    # filter all templates
    my $pos_start = 0;
    my $pos_end   = 0;

    my $text_test = $text;

#$text_test = 'abc[[Kartographie]], Bild:abd|[[Globus]]]] ohne [[Gradnetz]] weiterer Text
#aber hier [[Link234|sdsdlfk]]  [[Test]]';

    #print $text_test ."\n\n\n";

    $text_test =~ s/\n//g;
    undef(@links_all);

    while ( $text_test =~ /\[\[/g ) {

        #Begin of link
        $pos_start = pos($text_test) - 2;
        my $link_text              = substr( $text_test, $pos_start );
        my $link_text_2            = q{};
        my $beginn_square_brackets = 1;
        my $end_square_brackets    = 0;
        while ( $link_text =~ /\]\]/g ) {

            # Find currect end - number of [[==]]
            $pos_end     = pos($link_text);
            $link_text_2 = substr( $link_text, 0, $pos_end );
            $link_text_2 = ' ' . $link_text_2 . ' ';

            #print $link_text_2."\n";

            # test the number of [[and  ]]
            my $link_text_2_a = $link_text_2;
            $beginn_square_brackets = ( $link_text_2_a =~ s/\[\[//g );
            my $link_text_2_b = $link_text_2;
            $end_square_brackets = ( $link_text_2_b =~ s/\]\]//g );

            #print $beginn_square_brackets .' vs. '.$end_square_brackets."\n";
            last if ( $beginn_square_brackets eq $end_square_brackets );
        }

        if ( $beginn_square_brackets == $end_square_brackets ) {

            # link is correct
            $link_text_2 = substr( $link_text_2, 1, length($link_text_2) - 2 );

            #print 'Link:'.$link_text_2."\n";
            push( @links_all, $link_text_2 );
        }
        else {
            # template has no correct end
            $link_text = text_reduce( $link_text, 80 );
            error_010_count_square_breaks( 'check', $link_text );

            #print 'Error: '.$title.' '.$link_text."\n";
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_images {

    # get all images from all links
    undef(@images_all);

    my $found_error_text = q{};
    foreach (@links_all) {
        my $current_link = $_;

        #print $current_link. "\n";

        my $link_is_image = 'no';
        foreach (@namespace_image) {
            my $namespace_image_word = $_;
            $link_is_image = 'yes'
              if ( $current_link =~ /^\[\[([ ]?)+?$namespace_image_word:/i );
        }
        if ( $link_is_image eq 'yes' ) {

            # link is a image
            my $current_image = $current_link;
            push( @images_all, $current_image );

            #print "\t".'Image:'."\t".$current_image."\n";

            my $test_image = $current_image;

            #print '1:'."\t".$test_image."\n";
            foreach (@magicword_img_thumbnail) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '2:'."\t".$test_image."\n";
            foreach (@magicword_img_right) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '3:'."\t".$test_image."\n";
            foreach (@magicword_img_left) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '4:'."\t".$test_image."\n";
            foreach (@magicword_img_none) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '5:'."\t".$test_image."\n";
            foreach (@magicword_img_center) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '6:'."\t".$test_image."\n";
            foreach (@magicword_img_framed) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '7:'."\t".$test_image."\n";
            foreach (@magicword_img_frameless) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '8:'."\t".$test_image."\n";
            foreach (@magicword_img_border) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '9:'."\t".$test_image."\n";
            foreach (@magicword_img_sub) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '10:'."\t".$test_image."\n";
            foreach (@magicword_img_super) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '11:'."\t".$test_image."\n";
            foreach (@magicword_img_baseline) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '12:'."\t".$test_image."\n";
            foreach (@magicword_img_top) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '13:'."\t".$test_image."\n";
            foreach (@magicword_img_text_top) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '14:'."\t".$test_image."\n";
            foreach (@magicword_img_middle) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #print '15:'."\t".$test_image."\n";
            foreach (@magicword_img_bottom) {
                my $current_magicword = $_;

                #print $current_magicword."\n";
                $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
            }

            #######
            # special

            # 100px
            # 100x100px
            #print '16:'."\t".$test_image."\n";
            #foreach(@magicword_img_width) {
            #	my $current_magicword = $_;
            #	$current_magicword =~ s/$1/[0-9]+/;
            ##	print $current_magicword."\n";
            $test_image =~ s/\|([ ]?)+[0-9]+(x[0-9]+)?px([ ]?)+(\||\])/$4/i;

            #}

            #print '17:'."\t".$test_image."\n";

            if ( $found_error_text eq '' ) {
                if ( index( $test_image, '|' ) == -1 ) {

                    # [[Image:Afriga3.svg]]
                    $found_error_text = $current_image;
                }
                else {
                    my $pos_1 = index( $test_image, '|' );
                    my $pos_2 = index( $test_image, '|', $pos_1 + 1 );

                    #print '1:'."\t".$pos_1."\n";
                    #print '2:'."\t".$pos_2."\n";
                    if ( $pos_2 == -1
                        and index( $test_image, '|]' ) > -1 )
                    {
                        # [[Image:Afriga3.svg|]]
                        $found_error_text = $current_image;

                        #print 'Error'."\n";
                    }
                }
            }
        }
    }

    if ( $found_error_text ne '' ) {
        error_030_image_without_description( 'check', $found_error_text );
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_tables {

    # search for comments in this page
    # save comments in Array
    # replace comments with space
    #print 'get comment'."\n";
    my $pos_start_old = 0;
    my $pos_end_old   = 0;
    my $end_search    = 'yes';
    do {
        my $pos_start = 0;
        my $pos_end   = 0;
        $end_search = 'yes';

        #get position of next comment
        $pos_start = index( $text, '{|', $pos_start_old );
        $pos_end   = index( $text, '|}', $pos_start );

        #print 'get table: x'.substr ($text, $pos_end, 3 )."x\n";

        if (    $pos_start > -1
            and $pos_end > -1
            and substr( $text, $pos_end, 3 ) ne '|}}' )
        {
            #found a comment in current page
            $pos_end = $pos_end + length('|}');

#$comment_counter = $comment_counter +1;
#$comments[$comment_counter][0] = $pos_start;
#$comments[$comment_counter][1] = $pos_end;
#$comments[$comment_counter][2] = substr($text, $pos_start, $pos_end - $pos_start  );

#print 'Begin='.$comments[$comment_counter][0].' End='.$comments[$comment_counter][1]."\n";
#print 'Comment='.$comments[$comment_counter][2]."\n";

            $end_search    = 'no';
            $pos_start_old = $pos_end;

            #replace comment with space
            my $text_before = substr( $text, 0, $pos_start );
            my $text_after  = substr( $text, $pos_end );
            my $filler      = q{};
            for ( my $i = 0 ; $i < ( $pos_end - $pos_start ) ; $i++ ) {
                $filler = $filler . ' ';
            }
            $text = $text_before . $filler . $text_after;
        }
        if ( $pos_start > -1 and $pos_end == -1 ) {
            error_028_table_no_correct_end( 'check',
                substr( $text, $pos_start, 50 ) );
            $end_search = 'yes';
        }

    } until ( $end_search eq 'yes' );

    return ();
}

###########################################################################
##
###########################################################################

sub get_gallery {
    my $pos_start_old = 0;
    my $pos_end_old   = 0;
    my $end_search    = 'yes';
    do {
        my $pos_start = 0;
        my $pos_end   = 0;
        $end_search = 'yes';
        $pos_start  = index( $text, '<gallery', $pos_start_old );
        $pos_end    = index( $text, '</gallery>', $pos_start );
        if ( $pos_start > -1 and $pos_end > -1 ) {
            $pos_end       = $pos_end + length('</gallery>');
            $end_search    = 'no';
            $pos_start_old = $pos_end;

            #replace comment with space
            my $text_before = substr( $text, 0, $pos_start );
            my $text_after = substr( $text, $pos_end );
            my $text_gallery =
              substr( $text, $pos_start, $pos_end - $pos_start );
            error_035_gallery_without_description( 'check', $text_gallery );

            my $filler = q{};
            for ( my $i = 0 ; $i < ( $pos_end - $pos_start ) ; $i++ ) {
                $filler = $filler . ' ';
            }
            $text = $text_before . $filler . $text_after;

        }
        if ( $pos_start > -1 and $pos_end == -1 ) {
            error_029_gallery_no_correct_end( 'check',
                substr( $text, $pos_start, 50 ) );
            $end_search = 'yes';
        }
    } until ( $end_search eq 'yes' );

    return ();
}

###########################################################################
##
###########################################################################

sub get_hiero {

    #print 'Get hiero tag'."\n";
    my $pos_start_old = 0;
    my $pos_end_old   = 0;
    my $end_search    = 'yes';
    do {
        my $pos_start = 0;
        my $pos_end   = 0;
        $end_search = 'yes';

        #get position of next <math>
        $pos_start = index( $text, '<hiero>',  $pos_start_old );
        $pos_end   = index( $text, '</hiero>', $pos_start );

        if ( $pos_start > -1 and $pos_end > -1 ) {

            #found a math in current page
            $pos_end = $pos_end + length('</hiero>');

            #print substr($text, $pos_start, $pos_end - $pos_start  )."\n";

            $end_search    = 'no';
            $pos_start_old = $pos_end;

            #replace comment with space
            my $text_before = substr( $text, 0, $pos_start );
            my $text_after  = substr( $text, $pos_end );
            my $filler      = q{};
            for ( my $i = 0 ; $i < ( $pos_end - $pos_start ) ; $i++ ) {
                $filler = $filler . ' ';
            }
            $text = $text_before . $filler . $text_after;
        }
        if ( $pos_start > -1 and $pos_end == -1 ) {

     #error_015_Code_no_correct_end ( 'check', substr( $text, $pos_start, 50) );
     #print 'Code:'.substr( $text, $pos_start, 50)."\n";
            $end_search = 'yes';
        }

    } until ( $end_search eq 'yes' );

    return ();
}

###########################################################################
##
###########################################################################

sub get_ref {

    #print 'Get hiero tag'."\n";
    undef(@ref);
    my $pos_start_old = 0;
    my $pos_end_old   = 0;
    my $end_search    = 'yes';
    do {
        my $pos_start = 0;
        my $pos_end   = 0;
        $end_search = 'yes';

        #get position of next <math>
        $pos_start = index( $text, '<ref>',  $pos_start_old );
        $pos_end   = index( $text, '</ref>', $pos_start );

        if ( $pos_start > -1 and $pos_end > -1 ) {

            #found a math in current page
            $pos_end = $pos_end + length('</ref>');

            #print substr($text, $pos_start, $pos_end - $pos_start  )."\n";

            $end_search    = 'no';
            $pos_start_old = $pos_end;

            #print $pos_start." ".$pos_end."\n";
            my $new_ref = substr( $text, $pos_start, $pos_end - $pos_start );

            #print $new_ref."\n";
            push( @ref, $new_ref );
        }

    } until ( $end_search eq 'yes' );

    return ();
}

###########################################################################
##
###########################################################################

sub check_for_redirect {

    # is this page a redirect?
    if ( index( lc($text), '#redirect' ) > -1 ) {
        $page_is_redirect = 'yes';
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_categories {

    # search for categories in this page
    # save comments in Array
    # replace comments with space
    #print 'get categories'."\n";

#$text = 'absc[[ Kategorie:123|Museum]],Kategorie:78]][[     Category:ABC-Waffe| Kreuz ]][[Category:XY-Waffe|Hand ]] [[  category:Schwert| Fuss]] [[Kategorie:Karto]][[kategorie:Karto]]';
#print $text."\n";
#foreach (@namespace_cat) {
#	print $_."\n";
#}
    foreach (@namespace_cat) {

        my $namespace_cat_word = $_;

        #print "namespace_cat_word:".$namespace_cat_word."x\n";

        my $pos_start = 0;
        my $pos_end   = 0;

        my $text_test = $text;

        my $search_word = $namespace_cat_word;
        while ( $text_test =~ /\[\[([ ]+)?($search_word:)/ig ) {
            $pos_start = pos($text_test) - length($search_word) - 1;

#print "search word <b>$search_word</b> gefunden bei Position $pos_start<br>\n";

            $pos_end = index( $text_test, ']]', $pos_start );

            my $counter_begin = 0;
            do {
                $pos_start     = $pos_start - 1;
                $counter_begin = $counter_begin + 1
                  if ( substr( $text_test, $pos_start, 1 ) eq '[' );
            } until ( $counter_begin == 2 );

            #print $namespace_cat."\n";
            #print $pos_start."\n";
            #print $pos_end."\n";

            if ( $pos_start > -1 and $pos_end > -1 ) {

                #found a comment in current page
                $pos_end                        = $pos_end + length(']]');
                $category_counter               = $category_counter + 1;
                $category[$category_counter][0] = $pos_start;
                $category[$category_counter][1] = $pos_end;
                $category[$category_counter][2] = q{};
                $category[$category_counter][3] = q{};
                $category[$category_counter][4] =
                  substr( $text_test, $pos_start, $pos_end - $pos_start );

     #print $category[$category_counter][4]."\n";# if ($title eq 'Alain Delon');

                #replace comment with space
                #my $text_before = substr( $text, 0, $pos_start );
                #my $text_after  = substr( $text, $pos_end );
                #my $filler = q{};
                #for (my $i = 0; $i < ($pos_end-$pos_start); $i++) {
                # 		$filler = $filler.' ';
                #}
                #$text = $text_before.$filler.$text_after;

                #filter catname
                $category[$category_counter][2] =
                  $category[$category_counter][4];
                $category[$category_counter][2] =~ s/\[\[//g;    #delete space
                $category[$category_counter][2] =~
                  s/^([ ]+)?//g;    #delete blank before text
                $category[$category_counter][2] =~ s/\]\]//g;    #delete ]]
                $category[$category_counter][2] =~
                  s/^$namespace_cat_word//i;                     #delete ]]
                $category[$category_counter][2] =~ s/^://;       #delete ]]
                $category[$category_counter][2] =~ s/\|(.)*//g;  #delete |xy
                  #$category[$category_counter][2] =~ s/^(.)*://i;	#delete [[category:
                $category[$category_counter][2] =~
                  s/^ //g;    #delete blank before text
                $category[$category_counter][2] =~
                  s/ $//g;    #delete blank after text

                #filter linkname
                $category[$category_counter][3] =
                  $category[$category_counter][4];
                $category[$category_counter][3] = q{}
                  if ( index( $category[$category_counter][3], '|' ) == -1 );
                $category[$category_counter][3] =~
                  s/^(.)*\|//gi;    #delete [[category:xy|
                $category[$category_counter][3] =~ s/\]\]//g;    #delete ]]
                $category[$category_counter][3] =~
                  s/^ //g;    #delete blank before text
                $category[$category_counter][3] =~
                  s/ $//g;    #delete blank after text

#if ($title eq 'Alain Delon') {
#print "\t".'Begin='.$category[$category_counter][0].' End='.$category[$category_counter][1]."\n";
#print "\t".'catname=' .$category[$category_counter][2]."\n";
#print "\t".'linkname='.$category[$category_counter][3]."\n";
#print "\t".'full cat='.$category[$category_counter][4]."\n";

                #}
            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_interwikis {
    foreach (@inter_list) {

        my $current_lang = $_;

        #print "namespace_cat_word:".$namespace_cat_word."x\n";

        my $pos_start = 0;
        my $pos_end   = 0;

        my $text_test = $text;

        my $search_word = $current_lang;
        while ( $text_test =~ /\[\[([ ]+)?($search_word:)/ig ) {
            $pos_start = pos($text_test) - length($search_word) - 1;

#print "search word <b>$search_word</b> gefunden bei Position $pos_start<br>\n";

            $pos_end = index( $text_test, ']]', $pos_start );

            my $counter_begin = 0;
            do {
                $pos_start     = $pos_start - 1;
                $counter_begin = $counter_begin + 1
                  if ( substr( $text_test, $pos_start, 1 ) eq '[' );
            } until ( $counter_begin == 2 );

            #print $namespace_cat."\n";
            #print $pos_start."\n";
            #print $pos_end."\n";

            if ( $pos_start > -1 and $pos_end > -1 ) {

                #found a comment in current page
                $pos_end                          = $pos_end + length(']]');
                $interwiki_counter                = $interwiki_counter + 1;
                $interwiki[$interwiki_counter][0] = $pos_start;
                $interwiki[$interwiki_counter][1] = $pos_end;
                $interwiki[$interwiki_counter][2] = q{};
                $interwiki[$interwiki_counter][3] = q{};
                $interwiki[$interwiki_counter][4] =
                  substr( $text_test, $pos_start, $pos_end - $pos_start );

                $interwiki[$interwiki_counter][2] =
                  $interwiki[$interwiki_counter][4];
                $interwiki[$interwiki_counter][2] =~ s/\]\]//g;      #delete ]]
                $interwiki[$interwiki_counter][2] =~ s/\|(.)*//g;    #delete |xy
                $interwiki[$interwiki_counter][2] =~
                  s/^(.)*://gi;    #delete [[category:
                $interwiki[$interwiki_counter][2] =~
                  s/^ //g;         #delete blank before text
                $interwiki[$interwiki_counter][2] =~
                  s/ $//g;         #delete blank after text

                #filter linkname
                $interwiki[$interwiki_counter][3] =
                  $interwiki[$interwiki_counter][4];
                $interwiki[$interwiki_counter][3] = q{}
                  if ( index( $interwiki[$interwiki_counter][3], '|' ) == -1 );
                $interwiki[$interwiki_counter][3] =~
                  s/^(.)*\|//gi;    #delete [[category:xy|
                $interwiki[$interwiki_counter][3] =~ s/\]\]//g;    #delete ]]
                $interwiki[$interwiki_counter][3] =~
                  s/^ //g;    #delete blank before text
                $interwiki[$interwiki_counter][3] =~
                  s/ $//g;    #delete blank after text

                #language
                $interwiki[$interwiki_counter][5] = $current_lang;

         #$interwiki[$interwiki_counter][5] = $interwiki[$interwiki_counter][4];
         #$interwiki[$interwiki_counter][5] =~ s/:(.)*//gi;
         #$interwiki[$interwiki_counter][5] =~ s/\[\[//g;		#delete [[

#if ($title eq 'JPEG') {
#print "\t".'Begin='.$interwiki[$interwiki_counter][0].' End='.$interwiki[$interwiki_counter][1]."\n";
#print "\t".'full interwiki='.$interwiki[$interwiki_counter][4]."\n";
#print "\t".'language='.$interwiki[$interwiki_counter][5]."\n";
#print "\t".'interwikiname='.$interwiki[$interwiki_counter][2]."\n";
#print "\t".'linkname='.$interwiki[$interwiki_counter][3]."\n";
#}

            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub create_line_array {
    @lines = split( /\n/, $text );

    return ();
}

###########################################################################
##
###########################################################################

sub get_line_first_blank {
    undef(@lines_first_blank);

    #my $yes_blank = 'no';

    foreach (@lines) {
        my $current_line = $_;
        if (
                $current_line =~ /^ [^ ]/
            and $current_line =~ /^ [^\|]/    # no table
            and $current_line =~ /^ [^\!]/    #no table
          )
        {
            push( @lines_first_blank, $current_line );

            #$yes_blank = 'yes';

        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_headlines {
    undef(@headlines);

    my $section_text = q{};

    #get headlines
    foreach (@lines) {
        my $current_line = $_;

        if ( substr( $current_line, 0, 1 ) eq '=' ) {

            # save section
            push( @section, $section_text );
            $section_text = q{};

            # save headline
            push( @headlines, $current_line );
        }
        $section_text = $section_text . $_ . "\n";
    }
    push( @section, $section_text );

    #foreach(@headlines) {
    #	print $_."\n";
    #}

    return ();
}

###########################################################################
##
###########################################################################

sub error_list {
    my ($attribut) = @_;    # check / get_description

    error_001_no_bold_title($attribut);    # don´t work - deactivated
    error_002_have_br($attribut);
    error_003_have_ref($attribut);
    error_004_have_html_and_no_topic($attribut);
    error_005_Comment_no_correct_end( $attribut, '' );
    error_006_defaultsort_with_special_letters($attribut);
    error_007_headline_only_three($attribut);
    error_008_headline_start_end($attribut);
    error_009_more_then_one_category_in_a_line($attribut);
    error_010_count_square_breaks( $attribut, '' );
    error_011_html_names_entities($attribut);
    error_012_html_list_elements($attribut);
    error_013_Math_no_correct_end( $attribut, '' );
    error_014_Source_no_correct_end( $attribut, '' );
    error_015_Code_no_correct_end( $attribut, '' );
    error_016_unicode_control_characters($attribut);
    error_017_category_double($attribut);
    error_018_category_first_letter_small($attribut);
    error_019_headline_only_one($attribut);
    error_020_symbol_for_dead($attribut);
    error_021_category_is_english($attribut);
    error_022_category_with_space($attribut);
    error_023_nowiki_no_correct_end( $attribut, '' );
    error_024_pre_no_correct_end( $attribut, '' );
    error_025_headline_hierarchy($attribut);
    error_026_html_text_style_elements($attribut);
    error_027_unicode_syntax($attribut);
    error_028_table_no_correct_end( $attribut, '' );
    error_029_gallery_no_correct_end( $attribut, '' );
    error_030_image_without_description( $attribut, '' );

    error_031_html_table_elements($attribut);
    error_032_double_pipe_in_link($attribut);
    error_033_html_text_style_elements_underline($attribut);
    error_034_template_programming_elements($attribut);
    error_035_gallery_without_description( $attribut, '' );
    error_036_redirect_not_correct($attribut);
    error_037_title_with_special_letters_and_no_defaultsort($attribut);

    error_038_html_text_style_elements_italic($attribut);
    error_039_html_text_style_elements_paragraph($attribut);
    error_040_html_text_style_elements_font($attribut);
    error_041_html_text_style_elements_big($attribut);
    error_042_html_text_style_elements_small($attribut);
    error_043_template_no_correct_end( $attribut, '' );
    error_044_headline_with_bold($attribut);
    error_045_interwiki_double($attribut);
    error_046_count_square_breaks_begin($attribut);
    error_047_template_no_correct_begin($attribut);
    error_048_title_in_text($attribut);
    error_049_headline_with_html($attribut);
    error_050_dash($attribut);
    error_051_interwiki_before_last_headline($attribut);
    error_052_category_before_last_headline($attribut);
    error_053_interwiki_before_category($attribut);
    error_054_break_in_list($attribut);
    error_055_html_text_style_elements_small_double($attribut);
    error_056_arrow_as_ASCII_art($attribut);
    error_057_headline_end_with_colon($attribut);
    error_058_headline_with_capitalization($attribut);
    error_059_template_value_end_with_br($attribut);
    error_060_template_parameter_with_problem($attribut);
    error_061_reference_with_punctuation($attribut);
    error_062_headline_alone($attribut);
    error_063_html_text_style_elements_small_ref_sub_sup($attribut);
    error_064_link_equal_linktext($attribut);
    error_065_image_description_with_break($attribut);
    error_066_image_description_with_full_small($attribut);
    error_067_reference_after_punctuation($attribut);
    error_068_link_to_other_language($attribut);
    error_069_isbn_wrong_syntax( $attribut, '' );
    error_070_isbn_wrong_length( $attribut, '' );
    error_071_isbn_wrong_pos_X( $attribut, '' );
    error_072_isbn_10_wrong_checksum( $attribut, '' );
    error_073_isbn_13_wrong_checksum( $attribut, '' );
    error_074_link_with_no_target($attribut);
    error_075_indented_list($attribut);
    error_076_link_with_no_space($attribut);
    error_077_image_description_with_partial_small($attribut);
    error_078_reference_double($attribut);
    error_079_external_link_without_description($attribut);
    error_080_external_link_with_line_break($attribut);
    error_081_ref_double($attribut);
    error_082_link_to_other_wikiproject($attribut);
    error_083_headline_only_three_and_later_level_two($attribut);
    error_084_section_without_text($attribut);
    error_085_tag_without_content($attribut);
    error_086_link_with_two_brackets_to_external_source($attribut);
    error_087_html_names_entities_without_semicolon($attribut);
    error_088_defaultsort_with_first_blank($attribut);
    error_089_defaultsort_with_capitalization_in_the_middle_of_the_word(
        $attribut);
    error_090_defaultsort_with_lowercase_letters($attribut);
    error_091_title_with_lowercase_letters_and_no_defaultsort($attribut);
    error_092_headline_double($attribut);

    return ();
}

###########################################################################
##  ERROR 01
###########################################################################

sub error_001_no_bold_title {
    my ($attribut) = @_;
    my $error_code = 1;

    if ( $attribut eq 'check' ) {
        if (    $page_namespace == 0
            and index( $text, "'''" ) == -1
            and $page_is_redirect eq 'no' )
        {
            error_register( $error_code, '' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 02
###########################################################################

sub error_002_have_br {
    my $attribut   = @_;
    my $error_code = 2;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};

        if (   $page_namespace == 0
            or $page_namespace == 104 )
        {
            my $test_text = lc($text);
            if (   index( $test_text, '<br' ) > -1
                or index( $test_text, 'br>' ) > -1 )
            {
                my $pos = -1;
                foreach (@lines) {
                    my $current_line    = $_;
                    my $current_line_lc = lc($current_line);

                    #print $current_line_lc."\n";

                    if ( $current_line_lc =~ /<br\/[^ ]>/g ) {

                        # <br/1>
                        $pos = pos($current_line_lc) if ( $pos == -1 );
                    }

                    if ( $current_line_lc =~ /<br[^ ]\/>/g ) {

                        # <br1/>
                        $pos = pos($current_line_lc) if ( $pos == -1 );
                    }

                    if ( $current_line_lc =~ /<br[^ \/]>/g ) {

                        # <br7>
                        $pos = pos($current_line_lc) if ( $pos == -1 );
                    }

                    if ( $current_line_lc =~ /<[^ \/]br>/g ) {

                        # <\br>
                        $pos = pos($current_line_lc) if ( $pos == -1 );
                    }

                    if (    $pos > -1
                        and $test ne 'found' )
                    {
                        #print $pos."\n";
                        $test = 'found';
                        if ( $test_line eq '' ) {
                            $test_line = substr( $current_line, 0, $pos );
                            $test_line = text_reduce_to_end( $test_line, 50 );

                            #print $test_line."\n";
                        }
                    }
                }
            }
        }
        if ( $test eq 'found' ) {
            $test_line = text_reduce( $test_line, 80 );
            error_register( $error_code,
                '<nowiki>' . $test_line . ' </nowiki>' );

            #print "\t". $error_code."\t".$title."\t".$test_line."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 02
###########################################################################

sub error_003_have_ref {
    my $attribut   = @_;
    my $error_code = 3;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (   $page_namespace == 0
            or $page_namespace == 104 )
        {

            if (   index( $text, '<ref>' ) > -1
                or index( $text, '<ref name' ) > -1 )
            {

                my $test      = "false";
                my $test_text = lc($text);
                $test = "true"
                  if (  $test_text =~ /<[ ]?+references>/
                    and $test_text =~ /<[ ]?+\/references>/ );
                $test = "true" if ( $test_text =~ /<[ ]?+references[ ]?+\/>/ );
                $test = "true" if ( $test_text =~ /<[ ]?+references group/ );
                $test = "true" if ( $test_text =~ /\{\{[ ]?+refbegin/ );
                $test = "true" if ( $test_text =~ /\{\{[ ]?+refend/ );
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+reflist/ );    # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+reflink/ );    # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+reference list/ );    # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+references-small/ );  # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+references/ );        # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+listaref / );         # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+reference/ );         # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+przypisy/ );          # in plwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+amaga/ );             # in cawiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+referències/ );      # in cawiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+viitteet/ );          # in fiwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+verwysings/ );        # in afwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+references/ );        # in itwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+références/ );      # in frwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+notes/ );             # in frwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+listaref/ );          # in nlwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+referenties/ );       # in cawiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+ref-section/ );       # in ptwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+referências/ );      # in ptwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+refs/ );    # in nlwiki + enwiki
                $test = "true" if ( $test_text =~ /\{\{[ ]?+noot/ ); # in nlwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+unreferenced/ );      # in nlwiki
                $test = "true" if ( $test_text =~ /\{\{[ ]?+fnb/ );  # in nlwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+примечания/ )
                  ;                                                  # in ruwiki
                $test = "true"
                  if ( $test_text =~
                    /\{\{[ ]?+список примечаний/ );  # in ruwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+Примечания/ )
                  ;    # in ruwiki (Problem with big letters)
                $test = "true"
                  if (
                    $test_text =~ /\{\{[ ]?+Список примечаний/ )
                  ;    # in ruwiki (Problem with big letters)
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+kaynakça/ );    # in trwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+ثبت المراجع/ )
                  ;                                             # in arwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+appendix/ );     # in nlwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+примітки/ );  # in ukwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+Примітки/ );  # in ukwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+hide ref/ );          # in zhwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+forrás/ );           # in huwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+註腳/ );            # in zhwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+註腳h/ );           # in zhwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+註腳f/ );           # in zhwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+kayan kaynakça/ );   # in trwiki
                $test = "true" if ( $test_text =~ /\{\{[ ]?+r/ );    # in itwiki
                $test = "true" if ( $test_text =~ /\{\{[ ]?+r/ );    # in itwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+הערות שוליים/ )
                  ;                                                  # in hewiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+הערה/ );          # in hewiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+注脚/ );            # in zhwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+referências/ );      # in ptwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+רעפליסטע/ );  # in yiwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+apèndix/ );          # in cawiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+παραπομπές/ )
                  ;                                                  # in elwiki

                if ( $test eq "false" ) {
                    error_register( $error_code, '' );

                    #print "\t". $error_code."\t".$title."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 04
###########################################################################

sub error_004_have_html_and_no_topic {
    my ($attribut) = @_;
    my $error_code = 4;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and index( $text, 'http://' ) > -1
            and index( $text, '==' ) == -1
            and index( $text, '{{' ) == -1
            and $project eq 'dewiki'
            and index( $text, '<references' ) == -1
            and index( $text, '<ref>' ) == -1 )
        {
            error_register( $error_code, '' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 05
###########################################################################

sub error_005_Comment_no_correct_end {
    my ( $attribut, $comment ) = @_;
    my $error_code = 5;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, '<nowiki>' . $comment . '</nowiki>' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 06
###########################################################################

sub error_006_defaultsort_with_special_letters {
    my ($attribut) = @_;
    my $error_code = 6;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );

    #* in de: ä → a, ö → o, ü → u, ß → ss
    #* in fi: ü → y, é → e, ß → ss, etc.
    #* in sv and fi is allowed ÅÄÖåäö
    #* in cs is allowed čďěňřšťžČĎŇŘŠŤŽ
    #* in da, no, nn is allowed ÆØÅæøå
    #* in ro is allowed ăîâşţ
    #* in ru: Ё → Е, ё → е
    if ( $attribut eq 'check' ) {

        # {{DEFAULTSORT:Mueller, Kai}}
        # {{ORDENA:Alfons I}}
        if (
                ( $page_namespace == 0 or $page_namespace == 104 )
            and $project ne 'arwiki'
            and $project ne 'hewiki'
            and $project ne 'plwiki'
            and $project ne 'jawiki'
            and $project ne 'yiwiki'
            and $project ne 'zhwiki'

          )
        {

            my $pos1 = -1;
            foreach (@magicword_defaultsort) {
                $pos1 = index( $text, $_ ) if ( $pos1 == -1 );
            }

            if ( $pos1 > -1 ) {
                my $pos2 = index( substr( $text, $pos1 ), '}}' );
                my $testtext = substr( $text, $pos1, $pos2 );

                my $testtext_2 = $testtext;

                #my $testtext =~ s/{{DEFAULTSORT\s*:(.*)}}/$1/;
                #print $testtext."\n";
                $testtext =~ s/[-—–:,\.0-9 A-Za-z!\?']//g;
                $testtext =~ s/[&]//g;
                $testtext =~ s/#//g;
                $testtext =~ s/\///g;
                $testtext =~ s/\(//g;
                $testtext =~ s/\)//g;
                $testtext =~ s/\*//g;
                $testtext =~ s/[ÅÄÖåäö]//g
                  if ( $project eq 'svwiki' )
                  ;    # For Swedish, ÅÄÖ should also be allowed
                $testtext =~ s/[ÅÄÖåäö]//g
                  if ( $project eq 'fiwiki' )
                  ;    # For Finnish, ÅÄÖ should also be allowed
                $testtext =~ s/[čďěňřšťžČĎŇŘŠŤŽ]//g
                  if ( $project eq 'cswiki' );
                $testtext =~ s/[ÆØÅæøå]//g if ( $project eq 'dawiki' );
                $testtext =~ s/[ÆØÅæøå]//g if ( $project eq 'nowiki' );
                $testtext =~ s/[ÆØÅæøå]//g if ( $project eq 'nnwiki' );
                $testtext =~ s/[ăîâşţ]//g   if ( $project eq 'rowiki' );
                $testtext =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюя]//g
                  if ( $project eq 'ruwiki' );
                $testtext =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюяіїґ]//g
                  if ( $project eq 'ukwiki' );
                $testtext =~ s/[~]//g
                  if ( $project eq 'huwiki' );    # ~ for special letters

                #if ($testtext ne '') error_register(…);

                #print $testtext."\n";
                if (
                    ( $testtext ne '' )    # normal article
                      #or ($testtext ne '' and $page_namespace != 0 and index($text, '{{DEFAULTSORT') > -1 )		# if not an article then wiht {{ }}
                  )
                {
                    $testtext   = text_reduce( $testtext,   80 );
                    $testtext_2 = text_reduce( $testtext_2, 80 );

                    error_register( $error_code,
                            '<nowiki>'
                          . $testtext
                          . '</nowiki> || <nowiki>'
                          . $testtext_2
                          . '</nowiki>' );

                    #print "\t". $error_code."\t".$title."\t".$testtext."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 07
###########################################################################

sub error_007_headline_only_three {
    my ($attribut) = @_;
    my $error_code = 7;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        if ( $headlines[0]
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            if ( $headlines[0] =~ /===/ ) {

                my $found_level_two = 'no';
                foreach (@headlines) {
                    if ( $_ =~ /^==[^=]/ ) {
                        $found_level_two = 'yes';    #found level two (error 83)
                    }
                }
                if ( $found_level_two eq 'no' ) {
                    error_register( $error_code,
                        '<nowiki>' . $headlines[0] . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$headlines[0].'</nowiki>'."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 08
###########################################################################

sub error_008_headline_start_end {
    my ($attribut) = @_;
    my $error_code = 8;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        foreach (@headlines) {
            my $current_line  = $_;
            my $current_line1 = $current_line;
            my $current_line2 = $current_line;

            $current_line2 =~ s/\t//gi;
            $current_line2 =~ s/[ ]+/ /gi;
            $current_line2 =~ s/ $//gi;

            if (    $current_line1 =~ /^==/
                and not( $current_line2 =~ /==$/ )
                and index( $current_line, '<ref' ) == -1
                and ( $page_namespace == 0 or $page_namespace == 104 ) )
            {
                $current_line = text_reduce( $current_line, 80 );
                error_register( $error_code,
                    '<nowiki>' . $current_line . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$current_line.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 09
###########################################################################

sub error_009_more_then_one_category_in_a_line {
    my ($attribut) = @_;
    my $error_code = 9;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $error_line = q{};

        foreach (@lines) {
            my $current_line = $_;
            my $found        = 0;

            foreach (@namespace_cat) {
                my $namespace_cat_word = $_;
                $found = $found + 1
                  if ( $current_line =~ /\[\[([ ]+)?($namespace_cat_word:)/ig );
            }

            if ( $found > 1
                and ( $page_namespace == 0 or $page_namespace == 104 ) )
            {
                $error_line = $current_line;
            }
        }

        if ( $error_line ne '' ) {
            error_register( $error_code,
                '<nowiki>' . $error_line . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$error_line.'</nowiki>'."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 10
###########################################################################

sub error_010_count_square_breaks {
    my ( $attribut, $comment ) = @_;
    my $error_code = 10;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            $comment = text_reduce( $comment, 80 );
            error_register( $error_code, '<nowiki>' . $comment . '</nowiki>' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 11
###########################################################################

sub error_011_html_names_entities {
    my ($attribut) = @_;
    my $error_code = 11;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $pos       = -1;
            my $test_text = lc($text);

            # see http://turner.faculty.swau.edu/webstuff/htmlsymbols.html
            $pos = index( $test_text, '&auml;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&ouml;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&uuml;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&szlig;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&aring;' )  if ( $pos == -1 );    # åÅ
            $pos = index( $test_text, '&hellip;' ) if ( $pos == -1 );    # …
                #$pos = index( $test_text, '&lt;') if ($pos == -1);						# for example, &lt;em> produces <em> for use in examples
                #$pos = index( $test_text, '&gt;') if ($pos == -1);
                #$pos = index( $test_text, '&amp;') if ($pos == -1);					# For example, in en:Beta (letter), the code: &amp;beta; is used to add "&beta" to the page's display, rather than the unicode character β.
            $pos = index( $test_text, '&quot;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&minus;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&oline;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&cent;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&pound;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&euro;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&sect;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&dagger;' ) if ( $pos == -1 );

            $pos = index( $test_text, '&lsquo;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&rsquo;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&middot;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&bull;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&copy;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&reg;' )    if ( $pos == -1 );
            $pos = index( $test_text, '&trade;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&iquest;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&iexcl;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&aelig;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&ccedil;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&ntilde;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&acirc;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&aacute;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&agrave;' ) if ( $pos == -1 );

            #arrows
            $pos = index( $test_text, '&darr;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&uarr;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&crarr;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&rarr;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&larr;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&harr;' )  if ( $pos == -1 );

            if ( $pos > -1 ) {
                my $found_text = substr( $text, $pos );
                $found_text = text_reduce( $found_text, 80 );
                $found_text =~ s/&/&amp;/g;
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 12
###########################################################################

sub error_012_html_list_elements {
    my ($attribut) = @_;
    my $error_code = 12;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};
        my $test_text = lc($text);
        if (   index( $test_text, '<ol' ) > -1
            or index( $test_text, '<ul' ) > -1
            or index( $test_text, '<li>' ) > -1 )
        {
            foreach (@lines) {
                my $current_line    = $_;
                my $current_line_lc = lc($current_line);

                #get position of categorie

                if (
                        ( $page_namespace == 0 or $page_namespace == 104 )
                    and index( $text, '<ol start' ) == -1
                    and index( $text, '<ol type' ) == -1
                    and
                    index( $text, '<ol style="list-style-type:lower-roman">' )
                    == -1
                    and
                    index( $text, '<ol style="list-style-type:lower-alpha">' )
                    == -1
                    and (  index( $current_line_lc, '<ol>' ) > -1
                        or index( $current_line_lc, '<ul>' ) > -1
                        or index( $current_line_lc, '<li>' ) > -1 )
                  )
                {
                    $test = 'found';
                    $test_line = $current_line if ( $test_line eq '' );
                }
            }
        }
        if ( $test eq 'found' ) {
            $test_line = text_reduce( $test_line, 80 );
            error_register( $error_code,
                '<nowiki>' . $test_line . ' </nowiki>' );

            #print "\t". $error_code."\t".$title."\t".$test_line."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 13
###########################################################################

sub error_013_Math_no_correct_end {
    my ( $attribut, $comment ) = @_;
    my $error_code = 13;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $comment ne '' ) {
            error_register( $error_code, '<nowiki>' . $comment . '</nowiki>' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 14
###########################################################################

sub error_014_Source_no_correct_end {
    my ( $attribut, $comment ) = @_;
    my $error_code = 14;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $comment ne '' ) {
            error_register( $error_code, '<nowiki>' . $comment . '</nowiki>' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 16
###########################################################################

sub error_015_Code_no_correct_end {
    my ( $attribut, $comment ) = @_;
    my $error_code = 15;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $comment ne '' ) {
            error_register( $error_code, '<nowiki>' . $comment . '</nowiki>' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 17
###########################################################################

sub error_016_unicode_control_characters {
    my ($attribut) = @_;
    my $error_code = 16;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            foreach (@templates_all) {
                my $template_text = $_;
                my $pos           = -1;

              #$pos = index( $text, '&#xFEFF;') 	if ($pos == -1);	# l in Wrozlaw
              #$pos = index( $text, '&#x200E;') 	if ($pos == -1);	# l in Wrozlaw
              #$pos = index( $text, '&#x200B;') 	if ($pos == -1);	# –
                $pos = index( $template_text, '‎' )
                  if ( $pos == -1 );    # &#x200E;
                $pos = index( $template_text, '﻿' )
                  if ( $pos == -1 );    # &#xFEFF;
                  #$pos = index( $template_text, '​') if ($pos == -1);	# &#x200B;  # problem with IPA characters like "͡" in cs:Czechowice-Dziedzice.

                if ( $pos > -1 ) {
                    my $found_text = substr( $template_text, $pos );
                    $found_text = text_reduce( $found_text, 80 );
                    error_register( $error_code,
                        '<nowiki>' . $found_text . '</nowiki>' );

                    #print "\t". $error_code."\t".$title."\t".$found_text."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 17
###########################################################################

sub error_017_category_double {
    my ( $attribut, $comment ) = @_;
    my $error_code = 17;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        #print $title."\n" if ($page_number > 25000);;
        for ( my $i = 0 ; $i <= $category_counter - 1 ; $i++ ) {

#if ($title eq 'File:TobolskCoin.jpg') {
#	print "\t".'Begin='.$category[$i][0].' End='.$category[$category_counter][1]."\n";
#	print "\t".'catname=' .$category[$i][2]."\n";
#	print "\t".'linkname='.$category[$i][3]."\n";
#	print "\t".'full cat='.$category[$i][4]."\n";
#}

            my $test1 = $category[$i][2];

            if ( $test1 ne '' ) {
                $test1 =
                  uc( substr( $test1, 0, 1 ) )
                  . substr( $test1, 1 );    #first letter big

                for ( my $j = $i + 1 ; $j <= $category_counter ; $j++ ) {

                    my $test2 = $category[$j][2];
                    if ( $test2 ne '' ) {

                        $test2 =
                          uc( substr( $test2, 0, 1 ) )
                          . substr( $test2, 1 );    #first letter big

                 #print $title."\t".$category[$i][2]."\t".$category[$j][2]."\n";
                        if ( $test1 eq $test2
                            and
                            ( $page_namespace == 0 or $page_namespace == 104 ) )
                        {
                            error_register( $error_code,
                                '<nowiki>' . $category[$i][2] . '</nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$category[$i][2]."\n";
                        }
                    }
                }
            }

        }

    }

    return ();
}

###########################################################################
## ERROR 18
###########################################################################

sub error_018_category_first_letter_small {
    my ($attribut) = @_;
    my $error_code = 18;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $project ne 'commonswiki' ) {
            for ( my $i = 0 ; $i <= $category_counter ; $i++ ) {
                my $test_letter = substr( $category[$i][2], 0, 1 );
                if ( $test_letter =~ /([a-z]|ä|ö|ü)/ ) {
                    error_register( $error_code,
                        '<nowiki>' . $category[$i][2] . '</nowiki>' );

                    #print "\t".$test_letter.' - '.$category[$i][2]."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 19
###########################################################################

sub error_019_headline_only_one {
    my ($attribut) = @_;
    my $error_code = 19;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $headlines[0]
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            if ( $headlines[0] =~ /^=[^=]/ ) {
                error_register( $error_code,
                    '<nowiki>' . $headlines[0] . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$headlines[0].'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 20
###########################################################################

sub error_020_symbol_for_dead {
    my ($attribut) = @_;
    my $error_code = 20;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $pos = index( $text, '&dagger;' );
        if ( $pos > -1
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            my $test_text = substr( $text, $pos, 100 );
            $test_text = text_reduce( $test_text, 50 );
            error_register( $error_code,
                '<nowiki>…' . $test_text . '…</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>…'.$test_text.'…</nowiki>'."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 21
###########################################################################

sub error_021_category_is_english {
    my ($attribut) = @_;
    my $error_code = 21;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (    $project ne 'enwiki'
            and $project ne 'commonswiki'
            and ( $page_namespace == 0 or $page_namespace == 104 )
            and $namespace_cat[0] ne 'Category' )
        {
            for ( my $i = 0 ; $i <= $category_counter ; $i++ ) {
                my $current_cat = lc( $category[$i][4] );

                if ( index( $current_cat, lc( $namespace_cat[1] ) ) > -1 ) {
                    error_register( $error_code,
                        '<nowiki>' . $current_cat . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$category[$i][4].'</nowiki>'."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 22
###########################################################################

sub error_022_category_with_space {
    my ($attribut) = @_;
    my $error_code = 22;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            for ( my $i = 0 ; $i <= $category_counter ; $i++ ) {

                #print "\t". $category[$i][4]. "\n";
                if (
                       $category[$i][4] =~ /\[\[ /
                    or $category[$i][4] =~ /\[\[[^:]+ :/

                    #or $category[$i][4] =~ /\[\[[^:]+: /
                  )
                {
                    error_register( $error_code,
                        '<nowiki>' . $category[$i][4] . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$category[$i][4].'</nowiki>'."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 23
###########################################################################

sub error_023_nowiki_no_correct_end {
    my ( $attribut, $comment ) = @_;
    my $error_code = 23;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, '<nowiki>' . $comment . '</nowiki>' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 24
###########################################################################

sub error_024_pre_no_correct_end {
    my ( $attribut, $comment ) = @_;
    my $error_code = 24;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, '<nowiki>' . $comment . '</nowiki>' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 25
###########################################################################

sub error_025_headline_hierarchy {
    my ( $attribut, $comment ) = @_;
    my $error_code = 25;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $number_headline = -1;
        my $old_headline    = q{};
        my $new_headline    = q{};
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            foreach (@headlines) {
                $number_headline = $number_headline + 1;
                $old_headline    = $new_headline;
                $new_headline    = $_;

                if ( $number_headline > 0 ) {
                    my $level_old = $old_headline;
                    my $level_new = $new_headline;

                    #print $old_headline."\n";
                    #print $new_headline."\n";
                    $level_old =~ s/^([=]+)//;
                    $level_new =~ s/^([=]+)//;
                    $level_old = length($old_headline) - length($level_old);
                    $level_new = length($new_headline) - length($level_new);

                    #print $level_old ."\n";
                    #print $level_new ."\n";

                    if ( $level_new > $level_old
                        and ( $level_new - $level_old ) > 1 )
                    {
                        error_register( $error_code,
                                '<nowiki>'
                              . $old_headline
                              . '</nowiki><br /><nowiki>'
                              . $new_headline
                              . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$headlines[0].'</nowiki>'."\n";
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 26
###########################################################################

sub error_026_html_text_style_elements {
    my ($attribut) = @_;
    my $error_code = 26;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};
        my $test_text = lc($text);
        if ( index( $test_text, '<b>' ) > -1 ) {
            foreach (@lines) {
                my $current_line    = $_;
                my $current_line_lc = lc($current_line);

                if (    ( $page_namespace == 0 or $page_namespace == 104 )
                    and ( index( $current_line_lc, '<b>' ) > -1 ) )
                {
                    $test = 'found';
                    $test_line = $current_line if ( $test_line eq '' );
                }
            }
        }

        if ( $test eq 'found' ) {
            $test_line = text_reduce( $test_line, 80 );
            $test_line = $test_line . '…';
            error_register( $error_code,
                '<nowiki>' . $test_line . ' </nowiki>' );

            #print "\t". $error_code."\t".$title."\t".$test_line."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 27
###########################################################################

sub error_027_unicode_syntax {
    my ($attribut) = @_;
    my $error_code = 27;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $pos = -1;
            $pos = index( $text, '&#322;' )   if ( $pos == -1 );  # l in Wrozlaw
            $pos = index( $text, '&#x0124;' ) if ( $pos == -1 );  # l in Wrozlaw
            $pos = index( $text, '&#8211;' )  if ( $pos == -1 );  # –
                   #$pos = index( $text, '&#x') if ($pos == -1);
                   #$pos = index( $text, '&#') if ($pos == -1);

            if ( $pos > -1 ) {
                my $found_text = substr( $text, $pos );
                $found_text = text_reduce( $found_text, 80 );
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 28
###########################################################################

sub error_028_table_no_correct_end {
    my ( $attribut, $comment ) = @_;
    my $error_code = 28;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (    $comment ne ''
            and ( $page_namespace == 0 or $page_namespace == 104 )
            and index( $text, '{{end}}' ) == -1
            and index( $text, '{{End box}}' ) == -1
            and index( $text, '{{end box}}' ) == -1 )
        {
            error_register( $error_code,
                '<nowiki> ' . $comment . '…  </nowiki>' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 29
###########################################################################

sub error_029_gallery_no_correct_end {
    my ( $attribut, $comment ) = @_;
    my $error_code = 29;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, '<nowiki>' . $comment . '</nowiki>' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 30
###########################################################################

sub error_030_image_without_description {
    my ( $attribut, $comment ) = @_;
    my $error_code = 30;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $comment ne '' ) {
            if (   $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
            {
                error_register( $error_code,
                    '<nowiki>' . $comment . '</nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$comment."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 31
###########################################################################

sub error_031_html_table_elements {
    my ($attribut) = @_;
    my $error_code = 31;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};
        my $test_text = lc($text);
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            if ( index( $test_text, '<t' ) > -1 ) {
                foreach (@lines) {
                    my $current_line    = $_;
                    my $current_line_lc = lc($current_line);

                    if (
                        $page_namespace == 0
                        and (
                            #index( $current_line_lc, '<table>') > -1
                            #or index( $current_line_lc, '<td>') > -1
                            #or index( $current_line_lc, '<th>') > -1
                            #or index( $current_line_lc, '<tr>') > -1
                            #or
                            $current_line_lc =~
/<(table|tr|td|th)(>| border| align| bgcolor| style)/

                        )
                      )
                    {
                        $test = 'found';
                        $test_line = $current_line if ( $test_line eq '' );
                    }
                }
            }
            if ( $test eq 'found' ) {

                # http://aktuell.de.selfhtml.org/artikel/cgiperl/html-in-html/
                $test_line = text_reduce( $test_line, 80 );
                $test_line =~ s/\&/&amp;/g;
                $test_line =~ s/</&lt;/g;
                $test_line =~ s/>/&gt;/g;
                $test_line =~ s/\"/&quot;/g;

                error_register( $error_code,
                    '<nowiki>' . $test_line . ' </nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$test_line."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 32
###########################################################################

sub error_032_double_pipe_in_link {
    my ($attribut) = @_;
    my $error_code = 32;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            foreach (@lines) {
                my $current_line    = $_;
                my $current_line_lc = lc($current_line);
                if ( $current_line_lc =~ /\[\[[^\]:\{]+\|([^\]\{]+\||\|)/g ) {
                    my $pos              = pos($current_line_lc);
                    my $first_part       = substr( $current_line, 0, $pos );
                    my $second_part      = substr( $current_line, $pos );
                    my @first_part_split = split( /\[\[/, $first_part );
                    foreach (@first_part_split) {
                        $first_part = '[[' . $_;  # find last link in first_part
                    }
                    $current_line = $first_part . $second_part;
                    $current_line = text_reduce( $current_line, 80 );
                    error_register( $error_code,
                        '<nowiki>' . $current_line . ' </nowiki>' );

                   #print "\t". $error_code."\t".$title."\t".$current_line."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 33
###########################################################################

sub error_033_html_text_style_elements_underline {
    my ($attribut) = @_;
    my $error_code = 33;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};
        my $test_text = lc($text);
        if ( index( $test_text, '<u>' ) > -1 ) {
            foreach (@lines) {
                my $current_line    = $_;
                my $current_line_lc = lc($current_line);

                if (    ( $page_namespace == 0 or $page_namespace == 104 )
                    and ( index( $current_line_lc, '<u>' ) > -1 ) )
                {
                    $test = 'found';
                    $test_line = $current_line if ( $test_line eq '' );
                }
            }
        }
        if ( $test eq 'found' ) {
            $test_line = text_reduce( $test_line, 80 );
            $test_line = $test_line . '…';
            error_register( $error_code,
                '<nowiki>' . $test_line . ' </nowiki>' );

            #print "\t". $error_code."\t".$title."\t".$test_line."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 34
###########################################################################

sub error_034_template_programming_elements {
    my ($attribut) = @_;
    my $error_code = 34;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};
        foreach (@lines) {
            my $current_line    = $_;
            my $current_line_lc = lc($current_line);

            my $pos = -1;
            if ( $page_namespace == 0 or $page_namespace == 104 ) {

                $pos = index( $current_line_lc, '#if:' )
                  if ( index( $current_line_lc, '#if:' ) > -1 );
                $pos = index( $current_line_lc, '#ifeq:' )
                  if ( index( $current_line_lc, '#ifeq:' ) > -1 );
                $pos = index( $current_line_lc, '#ifeq:' )
                  if ( index( $current_line_lc, '#ifeq:' ) > -1 );
                $pos = index( $current_line_lc, '#switch:' )
                  if ( index( $current_line_lc, '#switch:' ) > -1 );
                $pos = index( $current_line_lc, '{{namespace}}' )
                  if ( index( $current_line_lc, '{{namespace}}' ) > -1 );
                $pos = index( $current_line_lc, '{{sitename}}' )
                  if ( index( $current_line_lc, '{{sitename}}' ) > -1 );
                $pos = index( $current_line_lc, '{{fullpagename}}' )
                  if ( index( $current_line_lc, '{{fullpagename}}' ) > -1 );
                $pos = index( $current_line_lc, '#ifexist:' )
                  if ( index( $current_line_lc, '#ifexist:' ) > -1 );
                $pos = index( $current_line_lc, '{{{' )
                  if ( index( $current_line_lc, '{{{' ) > -1 );
                $pos = index( $current_line_lc, '#tag:' )
                  if (  index( $current_line_lc, '#tag:' ) > -1
                    and index( $current_line_lc, '#tag:ref' ) == -1 )
                  ; # http://en.wikipedia.org/wiki/Wikipedia:Footnotes#Known_bugs

                if ( $pos > -1 ) {
                    $test = 'found';
                    if ( $test_line eq '' ) {
                        $test_line = $current_line;
                        $test_line = substr( $test_line, $pos );
                    }
                }
            }
        }

        if ( $test eq 'found' ) {
            $test_line = text_reduce( $test_line, 50 );
            error_register( $error_code,
                '<nowiki>' . $test_line . ' </nowiki>' );

            #print "\t". $error_code."\t".$title."\t".$test_line."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 35
###########################################################################

sub error_035_gallery_without_description {
    my ( $attribut, $text_gallery ) = @_;
    my $error_code = 35;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        my $test = q{};
        if (
            $text_gallery ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            #print $text_gallery."\n";
            my @split_gallery = split( /\n/, $text_gallery );
            my $test_line = q{};
            foreach (@split_gallery) {
                my $current_line = $_;

                #print $current_line."\n";
                foreach (@namespace_image) {
                    my $namespace_image_word = $_;

                    #print $namespace_image_word."\n";
                    if ( $current_line =~ /^$namespace_image_word:[^\|]+$/ ) {
                        $test = 'found';
                        $test_line = $current_line if ( $test_line eq '' );
                    }
                }
            }
            if ( $test eq 'found' ) {
                error_register( $error_code,
                    '<nowiki>' . $test_line . ' </nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$test_line."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 36
###########################################################################

sub error_036_redirect_not_correct {
    my ($attribut) = @_;
    my $error_code = 36;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_is_redirect eq 'yes' ) {
            if ( lc($text) =~ /#redirect[ ]?+[^ :\[][ ]?+\[/ ) {
                my $output_text = text_reduce( $text, 80 );

                error_register( $error_code,
                    '<nowiki>' . $output_text . ' </nowiki>' );

                #print "\t". $error_code."\t".$title."\n";
                #print "\t\t".$text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 37
###########################################################################

sub error_037_title_with_special_letters_and_no_defaultsort {
    my ($attribut) = @_;
    my $error_code = 37;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and $category_counter > -1
            and $project ne 'arwiki'
            and $project ne 'jawiki'
            and $project ne 'hewiki'
            and $project ne 'plwiki'
            and $project ne 'trwiki'
            and $project ne 'yiwiki'
            and $project ne 'zhwiki'
            and length($title) > 2 )
        {

            # test of magicword_defaultsort
            my $pos1 = -1;
            foreach (@magicword_defaultsort) {
                $pos1 = index( $text, $_ ) if ( $pos1 == -1 );
            }

            if ( $pos1 == -1 ) {

                # no defaultsort in article
                # now test title
                #print 'No defaultsort'."\n";

                my $test = $title;
                if ( index( $test, '(' ) > -1 ) {

                    # only text of title before bracket
                    $test = substr( $test, 0, index( $test, '(' ) - 1 );
                    $test =~ s/ $//g;
                }

                my $testtext = $test;
                $testtext = substr( $testtext, 0, 3 );
                $testtext = substr( $testtext, 0, 1 )
                  if ( $project eq 'frwiki' );    #request from fr:User:Laddo
                      #print "\t".'Testtext0'.$testtext."\n";

                $testtext =~ s/[-—–:,\.0-9 A-Za-z!\?']//g;
                $testtext =~ s/[&]//g;
                $testtext =~ s/\+//g;
                $testtext =~ s/#//g;
                $testtext =~ s/\///g;
                $testtext =~ s/\(//g;
                $testtext =~ s/\)//g;
                $testtext =~ s/[ÅÄÖåäö]//g
                  if ( $project eq 'svwiki' )
                  ;    # For Swedish, ÅÄÖ should also be allowed
                $testtext =~ s/[ÅÄÖåäö]//g
                  if ( $project eq 'fiwiki' )
                  ;    # For Finnish, ÅÄÖ should also be allowed
                $testtext =~ s/[čďěňřšťžČĎŇŘŠŤŽ]//g
                  if ( $project eq 'cswiki' );
                $testtext =~ s/[ÆØÅæøå]//g if ( $project eq 'dawiki' );
                $testtext =~ s/[ÆØÅæøå]//g if ( $project eq 'nowiki' );
                $testtext =~ s/[ÆØÅæøå]//g if ( $project eq 'nnwiki' );
                $testtext =~ s/[ăîâşţ]//g   if ( $project eq 'rowiki' );
                $testtext =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюя]//g
                  if ( $project eq 'ruwiki' );
                $testtext =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюяiїґ]//g
                  if ( $project eq 'ukwiki' );

                #print "\t".'Testtext1'.$testtext."\n";
                if ( $testtext ne '' ) {

                    #print "\t".'Testtext2'.$testtext."\n";
                    my $found = 'no';
                    for ( my $i = 0 ; $i <= $category_counter ; $i++ ) {
                        $found = "yes"
                          if ( $category[$i][3] eq ''
                            and index( $category[$i][4], '|' ) == -1 );
                    }

                    if ( $found eq 'yes' ) {

                        #print "\t".$title."\n";
                        #print "\t".$test."\n";
                        #for (my $i=0; $i <= $category_counter; $i++) {
                        #	print $category[$i][4]."\n";
                        #}
                        error_register( $error_code, '' );

                        #print "\t". $error_code."\t".$title."\n";
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 38
###########################################################################

sub error_038_html_text_style_elements_italic {
    my ($attribut) = @_;
    my $error_code = 38;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};
        my $test_text = lc($text);
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            if ( index( $test_text, '<i>' ) > -1 ) {

                foreach (@lines) {
                    my $current_line    = $_;
                    my $current_line_lc = lc($current_line);

                    if ( index( $current_line_lc, '<i>' ) > -1 ) {
                        $test = 'found';
                        $test_line = $current_line if ( $test_line eq '' );

                    }
                }
            }

            if ( $test eq 'found' ) {
                $test_line = text_reduce( $test_line, 80 );
                $test_line = $test_line . '…';
                error_register( $error_code,
                    '<nowiki>' . $test_line . ' </nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$test_line."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 39
###########################################################################

sub error_039_html_text_style_elements_paragraph {
    my ($attribut) = @_;
    my $error_code = 39;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};
        my $test_text = lc($text);
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            if ( index( $test_text, '<p>' ) > -1 ) {

                foreach (@lines) {
                    my $current_line    = $_;
                    my $current_line_lc = lc($current_line);

                    if ( index( $current_line_lc, '<p>' ) > -1 ) {
                        $test = 'found';
                        $test_line = $current_line if ( $test_line eq '' );
                    }
                }
            }
            if ( $test eq 'found' ) {
                $test_line = text_reduce( $test_line, 80 );
                $test_line = $test_line . '…';
                error_register( $error_code,
                    '<nowiki>' . $test_line . ' </nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$test_line."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 40
###########################################################################

sub error_040_html_text_style_elements_font {
    my ($attribut) = @_;
    my $error_code = 40;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};
        my $test_text = lc($text);
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            if ( index( $test_text, '<font' ) > -1 ) {
                foreach (@lines) {
                    my $current_line    = $_;
                    my $current_line_lc = lc($current_line);

                    if (   index( $current_line_lc, '<font ' ) > -1
                        or index( $current_line_lc, '<font>' ) > -1 )
                    {
                        $test = 'found';
                        $test_line = $current_line if ( $test_line eq '' );
                    }
                }
            }

            if ( $test eq 'found' ) {
                $test_line = text_reduce( $test_line, 80 );
                $test_line = $test_line . '…';
                error_register( $error_code,
                    '<nowiki>' . $test_line . ' </nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$test_line."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 41
###########################################################################

sub error_041_html_text_style_elements_big {
    my ($attribut) = @_;
    my $error_code = 41;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};
        my $test_text = lc($text);
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            if ( index( $test_text, '<big>' ) > -1 ) {
                foreach (@lines) {
                    my $current_line    = $_;
                    my $current_line_lc = lc($current_line);

                    if ( index( $current_line_lc, '<big>' ) > -1 ) {
                        $test = 'found';
                        $test_line = $current_line if ( $test_line eq '' );
                    }
                }
            }
            if ( $test eq 'found' ) {
                $test_line = text_reduce( $test_line, 80 );
                $test_line = $test_line . '…';
                error_register( $error_code,
                    '<nowiki>' . $test_line . ' </nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$test_line."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 42
###########################################################################

sub error_042_html_text_style_elements_small {
    my ($attribut) = @_;
    my $error_code = 42;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test      = 'no found';
        my $test_line = q{};
        my $test_text = lc($text);

        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            if ( index( $test_text, '<small>' ) > -1 ) {
                foreach (@lines) {
                    my $current_line    = $_;
                    my $current_line_lc = lc($current_line);

                    if ( index( $current_line_lc, '<small>' ) > -1 ) {
                        $test = 'found';
                        $test_line = $current_line if ( $test_line eq '' );
                    }
                }
            }
            if ( $test eq 'found' ) {
                $test_line = text_reduce( $test_line, 80 );
                $test_line = $test_line . '…';
                error_register( $error_code,
                    '<nowiki>' . $test_line . ' </nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$test_line."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 43
###########################################################################

sub error_043_template_no_correct_end {
    my ( $attribut, $comment ) = @_;
    my $error_code = 43;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, '<nowiki>' . $comment . '</nowiki>' );

            #print "\t". $error_code."\t".$title."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 44
###########################################################################

sub error_044_headline_with_bold {
    my ($attribut) = @_;
    my $error_code = 44;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            foreach (@headlines) {
                my $current_line = $_;

                #print $current_line ."\n";
                if (
                    index( $current_line, "'''" ) > -1    # if bold ther
                    and not $current_line =~
                    /[^']''[^']/ # for italic in headlinses   for example: == Acte au sens d'''instrumentum'' ==
                  )
                {
                    # there is a bold in headline
                    my $bold_ok = 'no';
                    if ( index( $current_line, "<ref" ) > -1 ) {

# test for bold in ref
# # ===This is a headline with reference <ref>A reference with '''bold''' text</ref>===
                        my $pos_begin_ref  = index( $current_line, "<ref" );
                        my $pos_end_ref    = index( $current_line, "</ref" );
                        my $pos_begin_bold = index( $current_line, "'''" );
                        if (    $pos_begin_ref < $pos_begin_bold
                            and $pos_begin_bold < $pos_end_ref )
                        {
                            $bold_ok = 'yes';
                        }
                    }
                    if ( $bold_ok eq 'no' ) {
                        $current_line = text_reduce( $current_line, 80 );
                        error_register( $error_code,
                            '<nowiki>' . $current_line . '</nowiki>' );

                   #print "\t". $error_code."\t".$title."\t".$current_line."\n";
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 45
###########################################################################

sub error_045_interwiki_double {
    my ($attribut) = @_;
    my $error_code = 45;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        #print $title."\n";
        #print 'Interwikis='.$interwiki_counter."\n";
        my $found_double = q{};

        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            for ( my $i = 0 ; $i <= $interwiki_counter ; $i++ ) {

#print $interwiki[$i][0]. $interwiki[$i][1]. $interwiki[$i][2]. $interwiki[$i][3]. $interwiki[$i][4]. "\n";
                for ( my $j = $i + 1 ; $j <= $interwiki_counter ; $j++ ) {
                    if ( lc( $interwiki[$i][5] ) eq lc( $interwiki[$j][5] ) ) {
                        my $test1 = lc( $interwiki[$i][2] );
                        my $test2 = lc( $interwiki[$j][2] );

                        #print $test1."\n";
                        #print $test2."\n";

                        if ( $test1 eq $test2 ) {
                            $found_double =
                                '<nowiki>'
                              . $interwiki[$i][4]
                              . '</nowiki><br /><nowiki>'
                              . $interwiki[$j][4]
                              . '</nowiki>' . "\n";
                        }

                    }
                }
            }
        }

        if ( $found_double ne '' ) {
            error_register( $error_code, $found_double );

            #print "\t". $error_code."\t".$title."\t".$found_double."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 46
###########################################################################

sub error_046_count_square_breaks_begin {
    my ($attribut) = @_;
    my $error_code = 46;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $text_test = q{};

#$text_test = 'abc[[Kartographie]], Bild:abd|[[Globus]]]] ohne [[Gradnetz]] weiterer Text
#aber hier [[Link234|sdsdlfk]]  [[Test]]';
#print 'Start 46'."\n";
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            $text_test = $text;

            #print $text_test."\n";
            my $text_test_1_a = $text_test;
            my $text_test_1_b = $text_test;

            if ( ( $text_test_1_a =~ s/\[\[//g ) !=
                ( $text_test_1_b =~ s/\]\]//g ) )
            {
                my $found_text = q{};
                my $begin_time = time();
                while ( $text_test =~ /\]\]/g ) {

                    #Begin of link
                    my $pos_end     = pos($text_test) - 2;
                    my $link_text   = substr( $text_test, 0, $pos_end );
                    my $link_text_2 = q{};
                    my $beginn_square_brackets = 0;
                    my $end_square_brackets    = 1;
                    while ( $link_text =~ /\[\[/g ) {

                        # Find currect end - number of [[==]]
                        my $pos_start = pos($link_text);
                        $link_text_2 = substr( $link_text, $pos_start );
                        $link_text_2 = ' ' . $link_text_2 . ' ';

                        #print 'Link_text2:'."\t".$link_text_2."\n";

                        # test the number of [[and  ]]
                        my $link_text_2_a = $link_text_2;
                        $beginn_square_brackets =
                          ( $link_text_2_a =~ s/\[\[//g );
                        my $link_text_2_b = $link_text_2;
                        $end_square_brackets = ( $link_text_2_b =~ s/\]\]//g );

              #print $beginn_square_brackets .' vs. '.$end_square_brackets."\n";
                        last
                          if ( $beginn_square_brackets eq $end_square_brackets
                            or $begin_time + 60 > time() );

                    }

                    if ( $beginn_square_brackets != $end_square_brackets ) {

                        # link has no correct begin
                        #print $link_text."\n";
                        $found_text = $link_text;
                        $found_text =~ s/  / /g;
                        $found_text =
                          text_reduce_to_end( $found_text, 50 ) . ']]';

            #$link_text = '…'.substr($link_text, length($link_text)-50 ).']]';
                    }

                    last
                      if ( $found_text ne '' or $begin_time + 60 > time() )
                      ;    # end if a problem was found, no endless run
                }

                if ( $found_text ne '' ) {
                    error_register( $error_code,
                        '<nowiki>' . $found_text . '</nowiki>' );

                    #print 'Error 46: '.$title.' '.$found_text."\n";
                    #print $page_namespace."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 47
###########################################################################

sub error_047_template_no_correct_begin {
    my ($attribut) = @_;
    my $error_code = 47;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        my $text_test = q{};

#$text_test = 'abc[[Kartographie]], [[Bild:abd|[[Globus]]]] ohne {{xyz}} [[Gradnetz]] weiterer Text {{oder}} wer}} warum
        ##aber hier [[Link234|sdsdlfk]] {{abc}} [[Test]]';

        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            $text_test = $text;

            #print $text_test."\n";
            my $text_test_1_a = $text_test;
            my $text_test_1_b = $text_test;

            if ( ( $text_test_1_a =~ s/\{\{//g ) !=
                ( $text_test_1_b =~ s/\}\}//g ) )
            {
                #print 'Error 47 not equl $title'."\n";
                my $begin_time = time();
                while ( $text_test =~ /\}\}/g ) {

                    #Begin of link
                    my $pos_end     = pos($text_test) - 2;
                    my $link_text   = substr( $text_test, 0, $pos_end );
                    my $link_text_2 = q{};
                    my $beginn_square_brackets = 0;
                    my $end_square_brackets    = 1;
                    while ( $link_text =~ /\{\{/g ) {

                        # Find currect end - number of [[==]]
                        my $pos_start = pos($link_text);
                        $link_text_2 = substr( $link_text, $pos_start );
                        $link_text_2 = ' ' . $link_text_2 . ' ';

                        #print $link_text_2."\n";

                        # test the number of [[and  ]]
                        my $link_text_2_a = $link_text_2;
                        $beginn_square_brackets =
                          ( $link_text_2_a =~ s/\{\{//g );
                        my $link_text_2_b = $link_text_2;
                        $end_square_brackets = ( $link_text_2_b =~ s/\}\}//g );

              #print $beginn_square_brackets .' vs. '.$end_square_brackets."\n";
                        last
                          if ( $beginn_square_brackets eq $end_square_brackets
                            or $begin_time + 60 > time() );
                    }

                    if ( $beginn_square_brackets != $end_square_brackets ) {

                        # template has no correct begin
                        $link_text =~ s/  / /g;

           #$link_text = '…'.substr($link_text, length($link_text) -50 ).'}}';
                        $link_text =
                          text_reduce_to_end( $link_text, 50 ) . '}}';
                        error_register( $error_code,
                            '<nowiki>' . $link_text . '</nowiki>' );

                        #print 'Error 47: '.$title.' '.$link_text."\n";
                        #print $page_namespace."\n";
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 48
###########################################################################

sub error_048_title_in_text {
    my ($attribut) = @_;
    my $error_code = 48;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        my $text_test = $text;

        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $pos = index( $text_test, '[[' . $title . ']]' );

            if ( $pos == -1 ) {
                $pos = index( $text_test, '[[' . $title . '|' );
            }

            if ( $pos != -1 ) {
                my $found_text = substr( $text_test, $pos );
                $found_text = text_reduce( $found_text, 50 );
                $found_text =~ s/\n//g;
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print 'Error 48: '.$title.' '.$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 49
###########################################################################

sub error_049_headline_with_html {
    my ($attribut) = @_;
    my $error_code = 49;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $text_test = lc($text);
            my $pos       = -1;
            $pos = index( $text_test, '<h2>' )  if ( $pos == -1 );
            $pos = index( $text_test, '<h3>' )  if ( $pos == -1 );
            $pos = index( $text_test, '<h4>' )  if ( $pos == -1 );
            $pos = index( $text_test, '<h5>' )  if ( $pos == -1 );
            $pos = index( $text_test, '<h6>' )  if ( $pos == -1 );
            $pos = index( $text_test, '</h2>' ) if ( $pos == -1 );
            $pos = index( $text_test, '</h3>' ) if ( $pos == -1 );
            $pos = index( $text_test, '</h4>' ) if ( $pos == -1 );
            $pos = index( $text_test, '</h5>' ) if ( $pos == -1 );
            $pos = index( $text_test, '</h6>' ) if ( $pos == -1 );
            if ( $pos != -1 ) {
                my $found_text = substr( $text_test, $pos );
                $found_text = text_reduce( $found_text, 50 );
                $found_text =~ s/\n//g;
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print 'Error 49: '.$title.' '.$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 50
###########################################################################

sub error_050_dash {
    my ($attribut) = @_;
    my $error_code = 50;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $pos = -1;
        $pos = index( lc($text), '&ndash;' );
        $pos = index( lc($text), '&mdash;' ) if $pos == -1;

        if ( $pos > -1
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            my $found_text = substr( $text, $pos );
            $found_text =~ s/\n//g;
            $found_text = text_reduce( $found_text, 50 );
            $found_text =~ s/^&/&amp;/g;
            error_register( $error_code,
                '<nowiki>…' . $found_text . '…</nowiki>' );

            #print "\t". $error_code."\t".$title."\t".$found_text."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 51
###########################################################################

sub error_051_interwiki_before_last_headline {
    my ($attribut) = @_;
    my $error_code = 51;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $number_of_headlines = @headlines;
        my $pos                 = -1;

        #print 'number_of_headlines: '.$number_of_headlines.' '.$title."\n";

        if ( $number_of_headlines > 0 ) {

            #print 'number_of_headlines: '.$number_of_headlines.' '.$title."\n";
            $pos =
              index( $text, $headlines[ $number_of_headlines - 1 ] )
              ;    #pos of last headline
                   #print 'pos: '. $pos."\n";
        }
        if ( $pos > -1
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

            my $found_text = q{};
            for ( my $i = 0 ; $i <= $interwiki_counter ; $i++ ) {

                if ( $pos > $interwiki[$i][0] ) {

                    #print $pos .' and '.$interwiki[$i][0]."\n";
                    $found_text = $interwiki[$i][4];
                }
            }

            if ( $found_text ne '' ) {

                #$found_text = text_reduce($found_text, 50);
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print 'Error 51: '.$title.' '.$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 52
###########################################################################

sub error_052_category_before_last_headline {
    my ($attribut) = @_;
    my $error_code = 52;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $number_of_headlines = @headlines;
        my $pos                 = -1;

        #print 'number_of_headlines: '.$number_of_headlines.' '.$title."\n";

        if ( $number_of_headlines > 0 ) {

            #print 'number_of_headlines: '.$number_of_headlines.' '.$title."\n";
            $pos =
              index( $text, $headlines[ $number_of_headlines - 1 ] )
              ;    #pos of last headline
                   #print 'pos: '. $pos."\n";
        }
        if ( $pos > -1
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

            my $found_text = q{};
            for ( my $i = 0 ; $i <= $category_counter ; $i++ ) {
                if ( $pos > $category[$i][0] ) {
                    $found_text = $category[$i][4];
                }
            }

            if ( $found_text ne '' ) {

                #$found_text = text_reduce($found_text, 50);
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print 'Error 52: '.$title.' '.$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 53
###########################################################################

sub error_053_interwiki_before_category {
    my ($attribut) = @_;
    my $error_code = 53;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (    $category_counter > -1
            and $interwiki_counter > -1
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

            my $pos_interwiki = $interwiki[0][0];
            my $found_text    = $interwiki[0][4];
            for ( my $i = 0 ; $i <= $interwiki_counter ; $i++ ) {
                if ( $interwiki[$i][0] < $pos_interwiki ) {
                    $pos_interwiki = $interwiki[$i][0];
                    $found_text    = $interwiki[$i][4];
                }
            }

            my $found = 'false';
            for ( my $i = 0 ; $i <= $category_counter ; $i++ ) {

                #print $pos_interwiki .' and '.$category[$i][0]."\n";
                $found = 'true' if ( $pos_interwiki < $category[$i][0] );
            }
            if ( $found eq 'true' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }

        }
    }

    return ();
}

###########################################################################
## ERROR 54
###########################################################################

sub error_054_break_in_list {
    my ($attribut) = @_;
    my $error_code = 54;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@lines) {
                my $current_line    = $_;
                my $current_line_lc = lc($current_line);

                #print $current_line_lc."END\n";
                if ( substr( $current_line, 0, 1 ) eq '*'
                    and index( $current_line_lc, 'br' ) > -1 )
                {
                    #print 'Line is list'."\n";
                    if ( $current_line_lc =~
/<([ ]+)?(\/|\\)?([ ]+)?br([ ]+)?(\/|\\)?([ ]+)?>([ ]+)?$/
                      )
                    {
                        $found_text = $current_line;

                        #print "\t".'Found:'."\t".$current_line_lc."\n";
                    }
                }
            }

            if ( $found_text ne '' ) {
                if ( length($found_text) > 65 ) {
                    $found_text =
                        substr( $found_text, 0, 30 ) . ' … '
                      . substr( $found_text, length($found_text) - 30 );
                }
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 55
###########################################################################

sub error_055_html_text_style_elements_small_double {
    my ($attribut) = @_;
    my $error_code = 55;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test_line = q{};
        my $test_text = lc($text);

        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            #print 'a'."\n";
            $test_text = lc($text);
            my $pos = -1;

            #print $test_text."\n";
            if ( index( $test_text, '<small>' ) > -1 ) {

                #print 'b'."\n";
                $pos = index( $test_text, '<small><small>' )  if ( $pos == -1 );
                $pos = index( $test_text, '<small> <small>' ) if ( $pos == -1 );
                $pos = index( $test_text, '<small>  <small>' )
                  if ( $pos == -1 );
                $pos = index( $test_text, '</small></small>' )
                  if ( $pos == -1 );
                $pos = index( $test_text, '</small> </small>' )
                  if ( $pos == -1 );
                $pos = index( $test_text, '</small>  </small>' )
                  if ( $pos == -1 );
                if ( $pos > -1 ) {

                    #print 'c'."\n";
                    my $found_text_1 =
                      text_reduce_to_end( substr( $text, 0, $pos ), 40 )
                      ;    # text before
                    my $found_text_2 =
                      text_reduce( substr( $text, $pos ), 30 );    #text after
                    my $found_text = $found_text_1 . $found_text_2;
                    $found_text =~ s/\n//g;
                    $found_text = text_reduce( $found_text, 80 );
                    error_register( $error_code,
                        '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 56
###########################################################################

sub error_056_arrow_as_ASCII_art {
    my ($attribut) = @_;
    my $error_code = 56;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $pos = -1;
            $pos = index( lc($text), '->' );
            $pos = index( lc($text), '<-' ) if $pos == -1;
            $pos = index( lc($text), '<=' ) if $pos == -1;
            $pos = index( lc($text), '=>' ) if $pos == -1;

            if ( $pos > -1 ) {
                my $test_text = substr( $text, $pos - 10, 100 );
                $test_text =~ s/\n//g;
                $test_text = text_reduce( $test_text, 50 );
                error_register( $error_code,
                    '<nowiki>…' . $test_text . '…</nowiki>' );

                #print 'Error '.$error_code.': '.$title.' '.$test_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 57
###########################################################################

sub error_057_headline_end_with_colon {
    my ($attribut) = @_;
    my $error_code = 57;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            foreach (@headlines) {
                my $current_line = $_;

                #print $current_line."\n";
                if ( $current_line =~ /:[ ]?[ ]?[ ]?[=]+([ ]+)?$/ ) {
                    $current_line = text_reduce( $current_line, 80 );
                    error_register( $error_code,
                        '<nowiki>' . $current_line . '</nowiki>' );

                   #print "\t". $error_code."\t".$title."\t".$current_line."\n";

                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 58
###########################################################################

sub error_058_headline_with_capitalization {
    my ($attribut) = @_;
    my $error_code = 58;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        my $found_text = q{};
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            foreach (@headlines) {
                my $current_line        = $_;
                my $current_line_normal = $current_line;

                $current_line_normal =~
                  s/[^A-Za-z,\/&]//g;    # only english characters and comma

                my $current_line_uc = uc($current_line_normal);
                if ( length($current_line_normal) > 10 ) {

                    #print "A:\t".$current_line_normal."\n";
                    #print "B:\t".$current_line_uc."\n";
                    if ( $current_line_normal eq $current_line_uc ) {

                        # found ALL CAPS HEADLINE(S)
                        #print "A:\t".$current_line_normal."\n";
                        my $check_ok = 'yes';

                        # check comma
                        if ( index( $current_line_normal, ',' ) > -1 ) {
                            my @comma_split =
                              split( ',', $current_line_normal );
                            foreach (@comma_split) {
                                if ( length($_) < 10 ) {
                                    $check_ok = 'no';

                                    #print $_."\n";
                                }
                            }
                        }

                        #print "\t".$check_ok."\n";

                        # problem
                        # ===== PPM, PGM, PBM, PNM =====
                        # 	== RB-29J ( RB-29, FB-29J, F-13, F-13A) ==
                        #  == GP40PH-2, GP40PH-2A, GP40PH-2B ==
                        # ===20XE, 20XEJ, [[C20XE]], [[C20LET]]===

                        if ( $check_ok eq 'yes' ) {
                            $found_text = $current_line;
                        }
                    }
                }
            }
            if (
                $found_text ne ''
                and index( $found_text, 'SSDSDSSWEMUGABRTLAD' ) ==
                -1    # de:TV total
              )
            {
                $found_text = text_reduce( $found_text, 80 );
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 59
###########################################################################

sub error_059_template_value_end_with_br {
    my ($attribut) = @_;
    my $error_code = 59;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $found_text = q{};
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            for ( my $i = 0 ; $i <= $number_of_template_parts ; $i++ ) {

                #print $template[$i][3]."\t".$template[$i][4]."\n";
                if ( $found_text eq '' ) {
                    if ( $template[$i][4] =~
/<([ ]+)?(\/|\\)?([ ]+)?br([ ]+)?(\/|\\)?([ ]+)?>([ ])?([ ])?$/
                      )
                    {
                        $found_text =
                          $template[$i][3] . '=…'
                          . text_reduce_to_end( $template[$i][4], 20 );
                    }
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 60
###########################################################################

sub error_060_template_parameter_with_problem {
    my ($attribut) = @_;
    my $error_code = 60;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $found_text = q{};
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            for ( my $i = 0 ; $i <= $number_of_template_parts ; $i++ ) {

                #print $template[$i][3]."\t".$template[$i][4]."\n";
                if ( $found_text eq '' ) {
                    if ( $template[$i][3] =~ /(\[|\]|\|:|\*)/ ) {
                        $found_text =
                          $template[$i][1] . ', ' . $template[$i][3];
                    }
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 61
###########################################################################

sub error_061_reference_with_punctuation {
    my ($attribut) = @_;
    my $error_code = 61;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $found_txt = q{};
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $pos = -1;
            $pos = index( $text, '</ref>.' )    if ( $pos == -1 );
            $pos = index( $text, '</ref> .' )   if ( $pos == -1 );
            $pos = index( $text, '</ref>  .' )  if ( $pos == -1 );
            $pos = index( $text, '</ref>   .' ) if ( $pos == -1 );
            $pos = index( $text, '</ref>!' )    if ( $pos == -1 );
            $pos = index( $text, '</ref> !' )   if ( $pos == -1 );
            $pos = index( $text, '</ref>  !' )  if ( $pos == -1 );
            $pos = index( $text, '</ref>   !' ) if ( $pos == -1 );
            $pos = index( $text, '</ref>?' )    if ( $pos == -1 );
            $pos = index( $text, '</ref> ?' )   if ( $pos == -1 );
            $pos = index( $text, '</ref>  ?' )  if ( $pos == -1 );
            $pos = index( $text, '</ref>   ?' ) if ( $pos == -1 );

            if ( $pos > -1 ) {
                my $found_text = substr( $text, $pos );
                $found_text = text_reduce( $found_text, 50 );
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 62
###########################################################################

sub error_062_headline_alone {
    my ( $attribut, $comment ) = @_;
    my $error_code = 62;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $number_of_headlines = @headlines;
            my $old_level           = 2;
            my $found_txt           = q{};
            if ( $number_of_headlines >= 5 ) {
                for ( my $i = 0 ; $i < $number_of_headlines ; $i++ ) {

                    #print $headlines[$i]."\n";
                    my $headline_test_1 = $headlines[$i];
                    my $headline_test_2 = $headlines[$i];
                    $headline_test_1 =~ s/^([=]+)//;
                    my $current_level =
                      length($headline_test_2) - length($headline_test_1);

                    if (    $current_level > 2
                        and $old_level < $current_level
                        and $i < $number_of_headlines - 1
                        and $found_txt eq '' )
                    {
                        # first headline in this level
                        #print 'check: '.$headlines[$i]."\n";
                        my $found_same_level = 'no';
                        my $found_end        = 'no';
                        for ( my $j = $i + 1 ;
                            $j < $number_of_headlines ; $j++ )
                        {
                            # check all headlinds behind
                            my $headline_test_1b = $headlines[$j];
                            my $headline_test_2b = $headlines[$j];
                            $headline_test_1b =~ s/^([=]+)//;
                            my $test_level =
                              length($headline_test_2b) -
                              length($headline_test_1b);

                            #print 'check: '.$headlines[$i]."\n";
                            if ( $test_level < $current_level ) {
                                $found_end = 'yes';

                                #print 'Found end'.$headlines[$j]."\n";
                            }

                            if (    $test_level = $current_level
                                and $found_end eq 'no' )
                            {
                                $found_same_level = 'yes';

                                #print 'Found end'.$headlines[$j]."\n";
                            }
                        }

                        if (    $found_txt eq ''
                            and $found_same_level eq 'no' )
                        {
                            # found alone text
                            $found_txt = $headlines[$i];

                        }

                    }

                    if (    $current_level > 2
                        and $old_level < $current_level
                        and $i == $number_of_headlines - 1
                        and $found_txt eq '' )
                    {
                        #found a last headline stand alone
                        $found_txt = $headlines[$i];
                    }
                    $old_level = $current_level;
                }
            }
            if ( $found_txt ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_txt . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_txt.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 63
###########################################################################

sub error_063_html_text_style_elements_small_ref_sub_sup {
    my ($attribut) = @_;
    my $error_code = 63;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $test_line = q{};
        my $test_text = lc($text);

        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            #print 'a'."\n";
            my $test_text = lc($text);
            my $pos       = -1;

            #print $test_text."\n";
            if ( index( $test_text, '</small>' ) > -1 ) {

                #print 'b'."\n";
                $pos = index( $test_text, '</small></ref>' )  if ( $pos == -1 );
                $pos = index( $test_text, '</small> </ref>' ) if ( $pos == -1 );
                $pos = index( $test_text, '</small>  </ref>' )
                  if ( $pos == -1 );
                $pos = index( $test_text, '</small></sub>' )  if ( $pos == -1 );
                $pos = index( $test_text, '</small> </sub>' ) if ( $pos == -1 );
                $pos = index( $test_text, '</small>  </sub>' )
                  if ( $pos == -1 );
                $pos = index( $test_text, '</small></sup>' )  if ( $pos == -1 );
                $pos = index( $test_text, '</small> </sup>' ) if ( $pos == -1 );
                $pos = index( $test_text, '</small>  </sup>' )
                  if ( $pos == -1 );

                if ( $pos > -1 ) {

                    #print 'pos:'.$pos."\n";
                    my $found_text_1 =
                      text_reduce_to_end( substr( $text, 0, $pos ), 40 )
                      ;    # text before
                    my $found_text_2 =
                      text_reduce( substr( $text, $pos ), 30 );    #text after
                          #print 'f1:'."\t".$found_text_1."\n\n";
                          #print 'f2:'."\t".$found_text_2."\n\n";

                    my $found_text = $found_text_1 . $found_text_2;
                    $found_text =~ s/\n//g;

                    #print $found_text."\n";
                    $found_text = text_reduce( $found_text, 80 );
                    error_register( $error_code,
                        '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 64
###########################################################################

sub error_064_link_equal_linktext {
    my ($attribut) = @_;
    my $error_code = 64;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@links_all) {

                # check all links
                if ( $found_text eq '' ) {

                    # if nothing found
                    my $current_link = $_;
                    if ( index( $current_link, '|' ) > -1 ) {

                        # only [[Link|Linktext]]
                        #print "\t".$current_link."\n";
                        my $test_link = $current_link;
                        $test_link =~ s/\[\[//;
                        $test_link =~ s/\]\]//;

                        if (
                            length($test_link) < 2    #  link like [[|]]
                          )
                        {
                            $found_text = $current_link;
                        }
                        else {
                            #print '1:'.$test_link."\n";
                            if (
                                substr( $test_link, length($test_link) - 1, 1 )
                                ne '|'                #  link like [[link|]]
                                and index( $test_link, '||' ) ==
                                -1    # link like [ link||linktest]]
                                and index( $test_link, '|' ) !=
                                0     # link [[|linktext]]
                              )
                            {
                                my @split_link = split( /\|/, $test_link );

                                #print "\t".'0:'."\t".$split_link[0]."\n";
                                #print "\t".'1:'."\t".$split_link[1]."\n";
                                #print '2:'.$test_link."\n";
                                if ( $split_link[0] eq $split_link[1] ) {

                                    # [[link|link]]
                                    #print "\t".$current_link."\n";
                                    $found_text = $current_link;
                                }
                            }
                        }
                    }
                }
            }
            if ( $found_text ne '' ) {
                $found_text = text_reduce( $found_text, 80 );
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 65
###########################################################################

sub error_065_image_description_with_break {
    my ($attribut) = @_;
    my $error_code = 65;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@images_all) {
                my $current_image = $_;
                if ( $found_text eq '' ) {

                    #print $current_image."\n";
                    if ( $current_image =~
/<([ ]+)?(\/|\\)?([ ]+)?br([ ]+)?(\/|\\)?([ ]+)?>([ ])?(\||\])/i
                      )
                    {
                        $found_text = $current_image;
                    }
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 66
###########################################################################

sub error_066_image_description_with_full_small {
    my ($attribut) = @_;
    my $error_code = 66;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@images_all) {
                my $current_image = $_;
                if ( $found_text eq '' ) {

                    #print $current_image."\n";
                    if ( $current_image =~
/<([ ]+)?(\/|\\)?([ ]+)?small([ ]+)?(\/|\\)?([ ]+)?>([ ])?(\||\])/i
                        and $current_image =~ /\|([ ]+)?<([ ]+)?small/ )
                    {
                        $found_text = $current_image;
                    }
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 67
###########################################################################

sub error_067_reference_after_punctuation {
    my ($attribut) = @_;
    my $error_code = 67;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        my $found_text = q{};
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $pos = -1;
            $pos = index( $text, '.<ref' )    if ( $pos == -1 );
            $pos = index( $text, '. <ref' )   if ( $pos == -1 );
            $pos = index( $text, '.  <ref' )  if ( $pos == -1 );
            $pos = index( $text, '.   <ref' ) if ( $pos == -1 );
            $pos = index( $text, '!<ref' )    if ( $pos == -1 );
            $pos = index( $text, '! <ref' )   if ( $pos == -1 );
            $pos = index( $text, '!  <ref' )  if ( $pos == -1 );
            $pos = index( $text, '!   <ref' ) if ( $pos == -1 );
            $pos = index( $text, '?<ref' )    if ( $pos == -1 );
            $pos = index( $text, '? <ref' )   if ( $pos == -1 );
            $pos = index( $text, '?  <ref' )  if ( $pos == -1 );
            $pos = index( $text, '?   <ref' ) if ( $pos == -1 );

            if ( $pos > -1 ) {
                $found_text = substr( $text, $pos );
                $found_text = text_reduce( $found_text, 50 );
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 68
###########################################################################

sub error_068_link_to_other_language {
    my ($attribut) = @_;
    my $error_code = 68;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@links_all) {

                # check all links
                if ( $found_text eq '' ) {
                    my $current_link = $_;
                    foreach (@inter_list) {
                        my $current_lang = $_;
                        if ( $current_link =~
                            /^\[\[([ ]+)?:([ ]+)?$current_lang:/i )
                        {
                            $found_text = $current_link;
                        }
                    }
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 69
###########################################################################

sub error_069_isbn_wrong_syntax {
    my ( $attribut, $found_text ) = @_;
    my $error_code = 69;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne '' )
        {
            error_register( $error_code,
                '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 70
###########################################################################

sub error_070_isbn_wrong_length {
    my ( $attribut, $found_text ) = @_;
    my $error_code = 70;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne '' )
        {
            error_register( $error_code,
                '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 71
###########################################################################

sub error_071_isbn_wrong_pos_X {
    my ( $attribut, $found_text ) = @_;
    my $error_code = 71;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne '' )
        {
            error_register( $error_code,
                '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 71
###########################################################################

sub error_072_isbn_10_wrong_checksum {
    my ( $attribut, $found_text ) = @_;
    my $error_code = 72;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne '' )
        {
            error_register( $error_code,
                '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 73
###########################################################################

sub error_073_isbn_13_wrong_checksum {
    my ( $attribut, $found_text ) = @_;
    my $error_code = 73;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne '' )
        {
            error_register( $error_code,
                '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
        }
    }

    return ();
}

###########################################################################
## ERROR 74
###########################################################################

sub error_074_link_with_no_target {
    my ($attribut) = @_;
    my $error_code = 74;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@links_all) {

                # check all links
                if ( $found_text eq '' ) {
                    my $current_link = $_;
                    if ( index( $current_link, '[[|' ) > -1 ) {
                        $found_text = $current_link;
                    }
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 75
###########################################################################

sub error_075_indented_list {
    my ($attribut) = @_;
    my $error_code = 75;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@lines) {
                my $current_line = $_;
                if (   substr( $current_line, 0, 2 ) eq ':*'
                    or substr( $current_line, 0, 2 ) eq ':-'
                    or substr( $current_line, 0, 2 ) eq ':#'
                    or substr( $current_line, 0, 2 ) eq ':·' )
                {
                    $found_text = $current_line if ( $found_text eq '' );

                    #print "\t".'Found:'."\t".$current_line_lc."\n";
                }
            }

            if ( $found_text ne '' ) {
                $found_text = text_reduce( $found_text, 50 );
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 76
###########################################################################

sub error_076_link_with_no_space {
    my ($attribut) = @_;
    my $error_code = 76;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@links_all) {

                # check all links
                if ( $found_text eq '' ) {
                    my $current_link = $_;
                    if ( $current_link =~ /^\[\[([^\|]+)%20([^\|]+)/i ) {
                        $found_text = $current_link;
                    }
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 77
###########################################################################

sub error_077_image_description_with_partial_small {
    my ($attribut) = @_;
    my $error_code = 77;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@images_all) {
                my $current_image = $_;
                if ( $found_text eq '' ) {

                    #print $current_image."\n";
                    if ( $current_image =~
/<([ ]+)?(\/|\\)?([ ]+)?small([ ]+)?(\/|\\)?([ ]+)?>([ ])?/i
                        and not $current_image =~ /\|([ ]+)?<([ ]+)?small/ )
                    {
                        $found_text = $current_image;
                    }
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 78
###########################################################################

sub error_078_reference_double {
    my ($attribut) = @_;
    my $error_code = 78;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $test_text      = lc($text);
            my $number_of_refs = 0;
            my $pos_first      = -1;
            my $pos_second     = -1;
            while ( $test_text =~ /<references[ ]?\/>/g ) {
                my $pos = pos($test_text);

                #print $number_of_refs." ".$pos."\n";
                $number_of_refs++;
                $pos_first = $pos
                  if ( $pos_first == -1 and $number_of_refs == 1 );
                $pos_second = $pos
                  if ( $pos_second == -1 and $number_of_refs == 2 );
            }

            #my $pos  = index($test_text, '<references');
            #my $pos2 = index($test_text, '<references', $pos+1);
            if ( $number_of_refs > 1 ) {
                $test_text = $text;
                $test_text =~ s/\n/ /g;
                my $found_text = substr( $test_text, 0, $pos_first );
                $found_text = text_reduce_to_end( $found_text, 50 );
                my $found_text2 = substr( $test_text, 0, $pos_second );
                $found_text2 = text_reduce_to_end( $found_text2, 50 );
                $found_text =
                  $found_text . "</nowiki><br /><nowiki>" . $found_text2;
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 79
###########################################################################

sub error_079_external_link_without_description {
    my ($attribut) = @_;
    my $error_code = 79;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $test_text = lc($text);

            my $pos        = -1;
            my $found_text = q{};
            while (index( $test_text, '[http://', $pos + 1 ) > -1
                or index( $test_text, '[ftp://',   $pos + 1 ) > -1
                or index( $test_text, '[https://', $pos + 1 ) > -1 )
            {
                my $pos1 = index( $test_text, '[http://',  $pos + 1 );
                my $pos2 = index( $test_text, '[ftp://',   $pos + 1 );
                my $pos3 = index( $test_text, '[https://', $pos + 1 );

                #print 'pos1: '. $pos1."\n";
                #print 'pos2: '. $pos2."\n";
                #print 'pos3: '. $pos3."\n";

                my $next_pos = -1;
                $next_pos = $pos1 if ( $pos1 > -1 );
                $next_pos = $pos2
                  if ( ( $next_pos == -1 and $pos2 > -1 )
                    or ( $pos2 > -1 and $next_pos > $pos2 ) );
                $next_pos = $pos3
                  if ( ( $next_pos == -1 and $pos3 > -1 )
                    or ( $pos3 > -1 and $next_pos > $pos3 ) );

                #print 'next_pos '.$next_pos."\n";
                my $pos_end = index( $test_text, ']', $next_pos );

                #print 'pos_end '.$pos_end."\n";
                my $weblink =
                  substr( $text, $next_pos, $pos_end - $next_pos + 1 );

                #print $weblink."\n";

                if ( index( $weblink, ' ' ) == -1 ) {
                    $found_text = $weblink if ( $found_text eq '' );
                }
                $pos = $next_pos;
            }

            if ( $found_text ne '' ) {
                $found_text = text_reduce( $found_text, 80 );
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 80
###########################################################################

sub error_080_external_link_with_line_break {
    my ($attribut) = @_;
    my $error_code = 80;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $test_text = lc($text);

            my $pos        = -1;
            my $found_text = q{};
            while (index( $test_text, '[http://', $pos + 1 ) > -1
                or index( $test_text, '[ftp://',   $pos + 1 ) > -1
                or index( $test_text, '[https://', $pos + 1 ) > -1 )
            {
                my $pos1 = index( $test_text, '[http://',  $pos + 1 );
                my $pos2 = index( $test_text, '[ftp://',   $pos + 1 );
                my $pos3 = index( $test_text, '[https://', $pos + 1 );

                my $next_pos = -1;
                $next_pos = $pos1 if ( $pos1 > -1 );
                $next_pos = $pos2
                  if ( ( $next_pos == -1 and $pos2 > -1 )
                    or ( $pos2 > -1 and $next_pos > $pos2 ) );
                $next_pos = $pos3
                  if ( ( $next_pos == -1 and $pos3 > -1 )
                    or ( $pos3 > -1 and $next_pos > $pos3 ) );

                #print 'next_pos '.$next_pos."\n";
                my $pos_end = index( $test_text, ']', $next_pos );

                #print 'pos_end '.$pos_end."\n";
                my $weblink =
                  substr( $text, $next_pos, $pos_end - $next_pos + 1 );

                #print $weblink."\n";

                if ( $weblink =~ /\n/ ) {
                    $found_text = $weblink if ( $found_text eq '' );
                }
                $pos = $next_pos;
            }

            if ( $found_text ne '' ) {
                $found_text = text_reduce( $found_text, 80 );
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 81
###########################################################################

sub error_081_ref_double {
    my ($attribut) = @_;
    my $error_code = 81;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $number_of_ref = @ref;
            my $found_text    = q{};
            for ( my $i = 0 ; $i < $number_of_ref - 1 ; $i++ ) {

                #print $i ."\t".$ref[$i]."\n";
                for ( my $j = $i + 1 ; $j < $number_of_ref ; $j++ ) {

                    #print $i." ".$j."\n";
                    if (    $ref[$i] eq $ref[$j]
                        and $found_text eq '' )
                    {
                        #found a double ref
                        $found_text = $ref[$i];

                        #print 'found'."\n";
                    }
                }
            }
            if ( $found_text ne '' ) {

                #$found_text   = text_reduce($found_text, 80);
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 82
###########################################################################

sub error_082_link_to_other_wikiproject {
    my ($attribut) = @_;
    my $error_code = 82;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@links_all) {

                # check all links
                if ( $found_text eq '' ) {
                    my $current_link = $_;
                    foreach (@foundation_projects) {
                        my $current_project = $_;
                        if (   $current_link =~ /^\[\[([ ]+)?$current_project:/i
                            or $current_link =~
                            /^\[\[([ ]+)?:([ ]+)?$current_project:/i )
                        {
                            $found_text = $current_link;
                        }
                    }
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 83
###########################################################################

sub error_083_headline_only_three_and_later_level_two {
    my ($attribut) = @_;
    my $error_code = 83;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $headlines[0]
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            if ( $headlines[0] =~ /===/ ) {

                my $found_level_two = 'no';
                foreach (@headlines) {
                    if ( $_ =~ /^==[^=]/ ) {
                        $found_level_two = 'yes';    #found level two (error 83)
                    }
                }
                if ( $found_level_two eq 'yes' ) {
                    error_register( $error_code,
                        '<nowiki>' . $headlines[0] . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$headlines[0].'</nowiki>'."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 84
###########################################################################

sub error_084_section_without_text {
    my ($attribut) = @_;
    my $error_code = 84;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $headlines[0]
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            # this article has headlines

            my $number_of_headlines = @headlines;
            my $found_text          = q{};

            for ( my $i = 0 ; $i < $number_of_headlines - 1 ; $i++ ) {

                # check level of headline and behind headline
                my $level_one = $headlines[$i];
                my $level_two = $headlines[ $i + 1 ];

                $level_one =~ s/^([=]+)//;
                $level_two =~ s/^([=]+)//;
                $level_one = length( $headlines[$i] ) - length($level_one);
                $level_two =
                  length( $headlines[ $i + 1 ] ) - length($level_two);

                if ( $level_one == $level_two or $level_one > $level_two ) {

                    # check section if level identical or lower
                    if ( $section[$i] ) {
                        my $test_section   = $section[ $i + 1 ];
                        my $test_section_2 = $section[ $i + 1 ];
                        my $test_headline  = $headlines[$i];
                        $test_headline =~ s/\n//g;

                        $test_section =
                          substr( $test_section, length($test_headline) )
                          if ($test_section);
                        if ($test_section) {

                            $test_section =~ s/[ ]//g;
                            $test_section =~ s/\n//g;
                            $test_section =~ s/\t//g;

                            if ( $test_section eq '' ) {

                                #print "\t x".$test_section_2."x\n";
                                if (
                                    index( $text_without_comments,
                                        $test_section_2 ) > -1
                                  )
                                {
                                    #print $text_without_comments."\n";
                                    $found_text = $test_headline
                                      if ( $found_text eq '' );
                                }
                            }
                        }
                    }
                }
            }

            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 85
###########################################################################

sub error_085_tag_without_content {
    my ($attribut) = @_;
    my $error_code = 85;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            my $found_pos  = -1;

            $found_pos = index( $text, '<noinclude></noinclude>' )
              if ( index( $text, '<noinclude></noinclude>' ) > -1 );
            $found_pos = index( $text, '<onlyinclude></onlyinclude>' )
              if ( index( $text, '<onlyinclude></onlyinclude>' ) > -1 );
            $found_pos = index( $text, '<includeonly></includeonly>' )
              if ( index( $text, '<includeonly></includeonly>' ) > -1 );
            $found_pos = index( $text, '<noinclude>' . "\n" . '</noinclude>' )
              if ( index( $text, '<noinclude>' . "\n" . '</noinclude>' ) > -1 );
            $found_pos =
              index( $text, '<onlyinclude>' . "\n" . '</onlyinclude>' )
              if (
                index( $text, '<onlyinclude>' . "\n" . '</onlyinclude>' ) >
                -1 );
            $found_pos =
              index( $text, '<includeonly>' . "\n" . '</includeonly>' )
              if (
                index( $text, '<includeonly>' . "\n" . '</includeonly>' ) >
                -1 );

            if ( $found_pos != -1 ) {
                $found_text = substr( $text, $found_pos );
                $found_text = text_reduce( $found_text, 80 );
                $found_text =~ s/\n//g;
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 86
###########################################################################

sub error_086_link_with_two_brackets_to_external_source {
    my ($attribut) = @_;
    my $error_code = 86;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text = q{};
            foreach (@links_all) {

                # check all links
                if ( $found_text eq '' ) {
                    my $current_link = $_;
                    if (   $current_link =~ /^\[\[([ ]+)?http:\/\//
                        or $current_link =~ /^\[\[([ ]+)?ftp:\/\//
                        or $current_link =~ /^\[\[([ ]+)?https:\/\// )
                    {
                        $found_text = $current_link;
                    }

                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . ' </nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 87
###########################################################################

sub error_087_html_names_entities_without_semicolon {
    my ($attribut) = @_;
    my $error_code = 87;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $pos       = -1;
            my $test_text = lc($text);

            # see http://turner.faculty.swau.edu/webstuff/htmlsymbols.html
            while ( $test_text =~ /&sup2[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&sup3[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&auml[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&ouml[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&uuml[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&szlig[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&aring[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&hellip[^;]/g ) { $pos = pos($test_text) }; # …
                #while($test_text =~ /&lt[^;]/g) { $pos = pos($test_text) };						# for example, &lt;em> produces <em> for use in examples
                #while($test_text =~ /&gt[^;]/g) { $pos = pos($test_text) };
                #while($test_text =~ /&amp[^;]/g) { $pos = pos($test_text) };
            while ( $test_text =~ /&quot[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&minus[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&oline[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&cent[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&pound[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&euro[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&sect[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&dagger[^;]/g ) { $pos = pos($test_text) }

            while ( $test_text =~ /&lsquo[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&rsquo[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&middot[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&bull[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&copy[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&reg[^;]/g )    { $pos = pos($test_text) }
            while ( $test_text =~ /&trade[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&iquest[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&iexcl[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&aelig[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&ccedil[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&ntilde[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&acirc[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&aacute[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&agrave[^;]/g ) { $pos = pos($test_text) }

            #arrows
            while ( $test_text =~ /&darr[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&uarr[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&crarr[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&rarr[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&larr[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&harr[^;]/g )  { $pos = pos($test_text) }

            if ( $pos > -1 ) {
                my $found_text = substr( $text, $pos - 10 );
                $found_text = text_reduce( $found_text, 50 );

                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

                #print "\t". $error_code."\t".$title."\t".$found_text."\n";
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 88
###########################################################################

sub error_088_defaultsort_with_first_blank {
    my ($attribut) = @_;
    my $error_code = 88;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {

        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and $project ne 'arwiki'
            and $project ne 'hewiki'
            and $project ne 'plwiki'
            and $project ne 'jawiki'
            and $project ne 'yiwiki'
            and $project ne 'zhwiki' )
        {
            my $pos1              = -1;
            my $current_magicword = q{};
            foreach (@magicword_defaultsort) {
                if ( $pos1 == -1 and index( $text, $_ ) > -1 ) {
                    $pos1 = index( $text, $_ );
                    $current_magicword = $_;
                }
            }
            if ( $pos1 > -1 ) {
                my $pos2 = index( substr( $text, $pos1 ), '}}' );
                my $testtext = substr( $text, $pos1, $pos2 );

                #print $testtext."\n";
                my $sortkey = $testtext;
                $sortkey =~ s/^([ ]+)?$current_magicword//;
                $sortkey =~ s/^([ ]+)?://;

                #print '-'.$sortkey."-\n";

                if ( index( $sortkey, ' ' ) == 0 ) {
                    my $found_text = $testtext;
                    error_register( $error_code,
                        '<nowiki>' . $found_text . '</nowiki>' );

                    #print "\t". $error_code."\t".$title."\t".$found_text."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 89
###########################################################################

sub error_089_defaultsort_with_capitalization_in_the_middle_of_the_word {
    my ($attribut) = @_;
    my $error_code = 89;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and $project ne 'arwiki'
            and $project ne 'hewiki'
            and $project ne 'plwiki'
            and $project ne 'jawiki'
            and $project ne 'yiwiki'
            and $project ne 'zhwiki' )
        {
            my $pos1              = -1;
            my $current_magicword = q{};
            foreach (@magicword_defaultsort) {
                if ( $pos1 == -1 and index( $text, $_ ) > -1 ) {
                    $pos1 = index( $text, $_ );
                    $current_magicword = $_;
                }
            }
            if ( $pos1 > -1 ) {
                my $pos2 = index( substr( $text, $pos1 ), '}}' );
                my $testtext = substr( $text, $pos1, $pos2 );

                #print $testtext."\n";
                my $sortkey = $testtext;
                $sortkey =~ s/^([ ]+)?$current_magicword//;
                $sortkey =~ s/^([ ]+)?://;

                #print '-'.$sortkey."-\n";

                if ( $sortkey =~ /[a-z][A-Z]/ ) {
                    my $found_text = $testtext;
                    error_register( $error_code,
                        '<nowiki>' . $found_text . '</nowiki>' );

                    #print "\t". $error_code."\t".$title."\t".$found_text."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 90
###########################################################################

sub error_090_defaultsort_with_lowercase_letters {
    my ($attribut) = @_;
    my $error_code = 90;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and $project ne 'arwiki'
            and $project ne 'hewiki'
            and $project ne 'plwiki'
            and $project ne 'jawiki'
            and $project ne 'yiwiki'
            and $project ne 'zhwiki' )
        {
            my $pos1              = -1;
            my $current_magicword = q{};
            foreach (@magicword_defaultsort) {
                if ( $pos1 == -1 and index( $text, $_ ) > -1 ) {
                    $pos1 = index( $text, $_ );
                    $current_magicword = $_;
                }
            }
            if ( $pos1 > -1 ) {
                my $pos2 = index( substr( $text, $pos1 ), '}}' );
                my $testtext = substr( $text, $pos1, $pos2 );

                #print $testtext."\n";
                my $sortkey = $testtext;
                $sortkey =~ s/^([ ]+)?$current_magicword//;
                $sortkey =~ s/^([ ]+)?://;

                #print '-'.$sortkey."-\n";

                if ( $sortkey =~ /[ -][a-z]/ ) {
                    my $found_text = $testtext;
                    error_register( $error_code,
                        '<nowiki>' . $found_text . '</nowiki>' );

                    #print "\t". $error_code."\t".$title."\t".$found_text."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 91
###########################################################################

sub error_091_title_with_lowercase_letters_and_no_defaultsort {
    my ($attribut) = @_;
    my $error_code = 91;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and $category_counter > -1
            and $project ne 'arwiki'
            and $project ne 'hewiki'
            and $project ne 'plwiki'
            and $project ne 'jawiki'
            and $project ne 'yiwiki'
            and $project ne 'zhwiki' )
        {

            my $pos1              = -1;
            my $current_magicword = q{};
            foreach (@magicword_defaultsort) {
                if ( $pos1 == -1 and index( $text, $_ ) > -1 ) {
                    $pos1 = index( $text, $_ );
                    $current_magicword = $_;
                }
            }
            if ( $pos1 == -1 ) {

                # no defaultsort
                my $subtitle = $title;
                $subtitle = substr( $subtitle, 0, 9 )
                  if ( length($subtitle) > 10 );
                if ( $subtitle =~ /[ -][a-z]/ ) {
                    error_register( $error_code, '' );

                    #print "\t". $error_code."\t".$title."\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 92
###########################################################################

sub error_092_headline_double {
    my ($attribut) = @_;
    my $error_code = 92;

    print $error_code. "\n" if ( $details_for_page eq 'yes' );
    if ( $attribut eq 'check' ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text          = q{};
            my $number_of_headlines = @headlines;
            for ( my $i = 0 ; $i < $number_of_headlines - 1 ; $i++ ) {
                my $first_headline   = $headlines[$i];
                my $secound_headline = $headlines[ $i + 1 ];

                if ( $first_headline eq $secound_headline ) {
                    $found_text = $headlines[$i];
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code,
                    '<nowiki>' . $found_text . '</nowiki>' );

#print "\t". $error_code."\t".$title."\t".'<nowiki>'.$found_text.'</nowiki>'."\n";
            }
        }
    }

    return ();
}

######################################################################
######################################################################
######################################################################

sub error_register {

    my $error_code = shift;
    my $notice     = shift;

    # only register if in script higher than 0 and…
    #	in project is unknown
    #       or in project higher 0

    $notice =~ s/\n//g;

    #print "\t". $error_code."\t".$title."\t".$notice."\n";
    #print "\t". $error_code."\t".$title."\t".$notice."\n" ;

    $page_has_error    = 'yes';
    $page_error_number = $page_error_number + 1;

    #print 'Page errir number: '.$page_error_number."\n";
    $error_description[$error_code][3] = $error_description[$error_code][3] + 1;

    $error_counter = $error_counter + 1;

    insert_into_db( $error_counter, $title, $error_code, $notice );

    return ();
}

######################################################################

# Insert error into database.
sub insert_into_db {
    my ( $error_counter, $article, $code, $notice ) = @_;
    my ( $TableName, $Found );

    $notice = substr( $notice, 0, 100 );    # Truncate notice.

    if ( $dump_or_live eq 'live' ) {
        $TableName = 'cw_error';
        $Found = strftime( '%F %T', gmtime() );
    }
    else {
        $TableName = 'cw_dumpscan';
        $Found     = $revision_time;
        $Found =~ s/Z//;
        $Found =~ s/T/ /;
    }
    my $sth =
      $dbh->prepare( 'INSERT INTO '
          . $TableName
          . ' (Project, Error_ID, Title, Error, Notice, Ok, Found) VALUES (?, ?, ?, ?, ?, ?, ?);'
      ) || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $project, $page_id, $article, $code, $notice, 0, $Found )
      or die "Cannot execute: " . $sth->errstr . "\n";

    return ();
}

######################################################################

# If an article was scanned live, then set this in the table
# cw_dumpscan as true.
sub set_article_as_scan_live_in_db {
    my ( $article, $id ) = @_;

# Update the table cw_dumpscan.
# $sth = $dbh->prepare ('UPDATE cw_dumpscan SET Scan_Live = TRUE WHERE Project = ? AND (Title = ? OR ID = ?);') or die ($dbh->errstr ());
# $sth->execute ($project, $article, $id) or die ('article:' . $article . "\n" . $dbh->errstr ());

    # Update the tables cw_new and cw_change.
    my $sth = $dbh->prepare(
        'UPDATE cw_new SET Scan_Live = TRUE WHERE Project = ? AND Title = ?;')
      or die( $dbh->errstr() . "\n" );
    $sth->execute( $project, $article )
      or die( 'article:' . $article . "\n" . $dbh->errstr() . "\n" );

    $sth = $dbh->prepare(
        'UPDATE cw_change SET Scan_Live = TRUE WHERE Project = ? AND Title = ?;'
    ) or die( $dbh->errstr() . "\n" );
    $sth->execute( $project, $article )
      or die( 'article:' . $article . "\n" . $dbh->errstr() . "\n" );

    return ();
}

######################################################################

# If a new error was found in the dump, then write this into the
# database table cw_dumpscan.
sub insert_into_db_table_tt {
    my ( $article, $page_id, $template, $name, $number, $parameter, $value ) =
      @_;

# Insert error into database (disabled for the moment).
# my $sth = $dbh->prepare ('INSERT INTO tt (Project, ID, Title, Template, Name, Number, Parameter, Value) VALUES (?, ?, ?, ?, ?, ?, ?, ?);') or die ($dbh->errstr ());
# $sth->execute ($project, $page_id, $article, $template, $name, $number, $parameter, $value) or die ($dbh->errstr ());

    return ();
}

# Right trim string, but only to full words (result may be longer than
# $Length characters).

######################################################################

sub text_reduce {
    my ( $s, $Length ) = @_;

    if ( length($s) > $Length ) {
        return substr( $s, 0, index( $s, ' ', $Length ) );
    }
    else {
        return $s;
    }

    return ();
}

######################################################################

# Left trim string merciless, but only to full words (result will
# never be longer than $Length characters).
sub text_reduce_to_end {
    my ( $s, $Length ) = @_;

    if ( length($s) > $Length ) {

        # Find first space in the last $Length characters of $s.
        my $pos = index( $s, ' ', length($s) - $Length );

        # If there is no space, just take the last $Length characters.
        $pos = length($s) - $Length if ( $pos == -1 );

        return substr( $s, $pos + 1 );
    }
    else {
        return $s;
    }
}

######################################################################

sub print_line {

    #prinnt a line for better structure of output
    print '-' x 80;
    print "\n";

    return ();
}

######################################################################

sub two_column_display {

    # print all output in two column well formed
    my $text1 = shift;
    my $text2 = shift;
    printf "%-30s %-30s\n", $text1, $text2;

    return ();
}

######################################################################

sub usage {
    print STDERR "To scan a dump:\n"
      . "$0 -p dewiki --dumpfile DUMPFILE --tt-file TEMPLATETIGERFILE\n"
      . "$0 -p nds_nlwiki --dumpfile DUMPFILE --tt-file TEMPLATETIGERFILE\n"
      . "$0 -p nds_nlwiki --dumpfile DUMPFILE --tt-file TEMPLATETIGERFILE --silent\n"
      . "To scan a list of pages live:\n"
      . "$0 -p dewiki\n"
      . "$0 -p dewiki --silent\n"
      . "$0 -p dewiki --load new/done/dump/last_change/old\n";

    return ();
}

###########################################################################
###########################################################################
## MAIN PROGRAM
###########################################################################
###########################################################################

## GET COMMAND LINE OPTIONS

my ( $load_mode, $DumpFilename, $TTFilename );

my @Options = (
    'load=s'       => \$load_mode,
    'p=s'          => \$project,
    'database|D=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
    'dumpfile=s'   => \$DumpFilename,
    'tt-file=s'    => \$TTFilename,
    'silent'       => \$silent_modus,
    'starter'      => \$starter_modus
);

if (
    !GetOptions(
        'c=s' => sub {
            my $f = IO::File->new( $_[1], '<:encoding(UTF-8)' )
              or die( "Can't open " . $_[1] . "\n" );
            local ($/);
            my $s = <$f>;
            $f->close();
            my ( $Success, $RemainingArgs ) =
              GetOptionsFromString( $s, @Options );
            die unless ( $Success && !@$RemainingArgs );
        },
        @Options
    )
    || defined($DumpFilename) != defined($TTFilename)
  )
{
    usage();
    exit(1);
}

# Check that a project name is given.
if ( !defined($project) ) {
    usage();
    die("$0: No project name, for example: \"-p dewiki\"\n");
}

# Split load mode.
if ( defined($load_mode) && !defined($DumpFilename) ) {
    my %LoadOptions = map { $_ => 1; } split( /\//, $load_mode );

    $load_modus_done = exists( $LoadOptions{'done'} );    # done article from db
    $load_modus_new  = exists( $LoadOptions{'new'} );     # new article from db
    $load_modus_dump = exists( $LoadOptions{'dump'} );    # new article from db
    $load_modus_last_change =
      exists( $LoadOptions{'last_change'} );    # last_change article from db
    $load_modus_old = exists( $LoadOptions{'old'} );    # old article from db
}

$language = $project;
$language =~ s/source$//;
$language =~ s/wiki$//;

if ( !$silent_modus ) {
    print "$0, version $VERSION.\n";
}

two_column_display( 'start:',
        $akJahr . '-'
      . $akMonat . '-'
      . $akMonatstag . ' '
      . $akStunden . ':'
      . $akMinuten );
two_column_display( 'project:', $project );

if ( !$silent_modus ) {
    two_column_display( 'Modus:',
            $dump_or_live . ' ('
          . ( $dump_or_live eq 'dump' ? 'scan a dump' : 'scan live' )
          . ')' );
}

open_db();    # Connect to database.

my $dump_date_for_output;
if ( defined($DumpFilename) ) {
    $dump_or_live = 'dump';

    # GET DATE FROM THE DUMP FILENAME
    $dump_date_for_output = $DumpFilename;
    $dump_date_for_output =~
s/^(?:.*\/)?\Q$project\E-(\d{4})(\d{2})(\d{2})-pages-articles\.xml\.bz2$/$1-$2-$3/;

  # DELETE OLD LIST OF ARTICLES FROM LAST DUMP SCAN IN TABLE cw_dumpscan
  #    $dbh->do( 'DELETE FROM cw_dumpscan WHERE Project = ?;', undef, $project )
  #      or die( $dbh->errstr() );

    # GET DUMP FILE SIZE, UNCOMPRESS AND THEN OPEN VIA METAWIKI::DumpFile
    my $dump;
    $file_size = ( stat($DumpFilename) )[7];

    open( $dump, '-|', 'bzcat', '-q', $DumpFilename )
          or die("Couldn't open dump file '$DumpFilename'");

    $pages = $pmwd->pages($dump);

    # OPEN TEMPLATETIGER FILE
    if (
        !(
            $TTFile = File::Temp->new(
                DIR      => $ENV{'HOME'} . '/var/tmp',
                TEMPLATE => $project . '-' . $dump_date_for_output . '-XXXX',
                SUFFIX   => '.txt',
                UNLINK   => 0
            )
        )
      )
    {
        die("Couldn't open temporary file for Templatetiger\n");
    }
    binmode( $TTFile, ":encoding(UTF-8)" );    # Convert string ouput to UTF-8
}
else {
    $dump_or_live = 'live';
    load_article_for_live_scan();
}

ReadMetadata();

for ( my $i = 1 ; $i <= 150 ; $i++ ) {
    $error_description[$i][3] = 0;
}

# MAIN ROUTINE - SCAN PAGES FOR ERRORS
scan_pages();    # Scan articles.

# UPDATE DATE OF LAST DUMP IN DATABASE FOR PROJECT GIVEN
$dbh->do( 'UPDATE cw_project SET Last_Dump = ? WHERE Project = ?;',
    undef, $dump_date_for_output, $project )
  or die( $dbh->errstr() . "\n" );

# CLOSE FILES.  ONLY NEED TO DO Templatetiger FILE
if ( defined($DumpFilename) ) {

    # Move Templatetiger file to spool.
    $TTFile->close() or die( $! . "\n" );
    if ( !rename( $TTFile->filename(), $TTFilename ) ) {
        die(    "Couldn't rename temporary Templatetiger file from "
              . $TTFile->filename() . ' to '
              . $TTFilename
              . "\n" );
    }
    if ( !chmod( 0664, $TTFilename ) ) {
        die( "Couldn't chmod 664 Templatetiger file " . $TTFilename . "\n" );
    }
    undef($TTFile);
}

update_table_cw_error_from_dump()     if ( $quit_program eq 'no' );
delete_deleted_article_from_db()      if ( $quit_program eq 'no' );
delete_article_from_table_cw_new()    if ( $quit_program eq 'no' );
delete_article_from_table_cw_change() if ( $quit_program eq 'no' );
update_table_cw_starter();

output_little_statistic()
  if ( $quit_program eq 'no' );    # print counter of found errors
output_duration() if ( $quit_program eq 'no' );    # print time at the end

print $quit_reason if ( $quit_reason ne '' );

close_db();                                        # Disconnect from database.

print "Finish\n";
