#!/usr/local/bin/perl


# Error exception
$SIG{__DIE__} = \&die_error;
$SIG{__WARN__} = \&warn_error;


load_moduls();
declare_global_variables();
load_projects();
insert_project_into_db();
day_loop();
close_db();



sub load_moduls{
	#################################################################
	# Load Module
	#################################################################
	#use lib "C:/perl/lib";
	use strict;
	use warnings;
}

sub declare_global_variables {
	#################################################################
	# Declaration of variables (global)
	#################################################################
	our @projects;
	our $starttime = time();
	our $run_modus = 'done';
	our $loop_number = 0;
	our $last_rung_change = 'false';
	our $dbh;
	
	get_time();
	
	our $start_day = $akMonatstag;
	our $start_month = $akMonat;
	

}


sub load_projects{

	use DBI;
    open_db();

	########################
	# Load from cw_project
	my $sql_text = " select project from cw_project where project not like '%_test' order by project;";
	my $result = '';
	my $sth = $dbh->prepare( $sql_text );
	#print '<p class="smalltext"/>'.$sql_text."</p>\n";					  
	$sth->execute();
	my $union_sql_text = '';
	my $i = 0;
	while (my $arrayref = $sth->fetchrow_arrayref()) {	
		foreach(@$arrayref) {
			$result = $_;
			push(@projects, $result );
		}
	}

	#@projects = ('pdcwiki','yiwiki');
	
	my $number_of_projects = @projects;
	print  $number_of_projects.' projects in database'."\n";
	close_db();
}



sub insert_project_into_db{
	open_db();
	my $current_project = $_;
	my $sql_text = "truncate cw_starter;";
	my $result = '';
	my $sth = $dbh->prepare( $sql_text );
	#print '<p class="smalltext"/>'.$sql_text."</p>\n";					  
	$sth->execute;		
	foreach (@projects){
		my $current_project = $_;
		my $sql_text = " insert into cw_starter (project, errors_done, errors_new, errors_dump, errors_change, errors_old, last_run_change) values('".$current_project."', 0,0,0,0,0,'false');";
		my $result = '';
		my $sth = $dbh->prepare( $sql_text );
		#print '<p class="smalltext"/>'.$sql_text."</p>\n";					  
		$sth->execute;		
	}
	close_db();
}



sub day_loop{

	# loop over the day
	
	
	
	
	do {

		
		if ($loop_number > 0) {		# not in the first run
			if ($last_run_change eq 'false') {
				my $new_run_modus = '';
				
				$new_run_modus = 'new'			if ($run_modus eq 'done');
				$new_run_modus = 'dump' 		if ($run_modus eq 'new');
				$new_run_modus = 'last_change' 	if ($run_modus eq 'dump');
				$new_run_modus = 'old' 			if ($run_modus eq 'last_change');
				$new_run_modus = 'new'			if ($run_modus eq 'old');			# only one time at day the done! so old --> new
				$run_modus = $new_run_modus;
				
				#only new,dump,old
				#$run_modus = 'old'			if ($run_modus eq 'dump');
				#$run_modus = 'dump'			if ($run_modus eq 'done');
				
				print "\n";
				print '##########################################################'."\n";
				print 'New run_modus: '.$run_modus."\n";
				print '##########################################################'."\n";
			
			}
		}
		
		$loop_number = $loop_number +1;

		
		
		# loop over all projects
		foreach(@projects) {
			my $current_project = $_;
			my $statement = 'nice -n 19 perl checkwiki.pl -p '.$current_project.' -m live load='.$run_modus.' starter silent';
			print "\n".$statement."\n";
			system($statement);
			print 'Back in startet.pl'."\n";
			#sleep(3);
		}
		
		print 'Check'."\n";
		
		check_last_run_change();
		
		get_time();
		print 'Start time:'.$start_day.'. '.$start_month.'.'."\n";
		print 'Current time:'.$akMonatstag.'. '.$akMonat.'. '.$akStunden.':'.$akMinuten."\n";
		
	}
	until (    $start_day != $akMonatstag
			or $start_month != $akMonat
			or ($akStunden >= 23 and $akMinuten >= 30 )			# half hour before 0:00 
			#or ($akStunden >= 8 and $akMinuten >= 0 )			# test
			#or $run_modus eq 'old' 		#last modus
			);

	
	

}


sub check_last_run_change{
	
	
	
	open_db();
	print '##################################################'."\n";
	print 'check last run change'."\n";
	# count the change of last run
	my $sql_text = "select ifnull(sum(current_run),0) from cw_starter;";
	my $result = '';
	my $sth = $dbh->prepare( $sql_text ) ||  die "Kann Statement nicht vorbereiten: $DBI::errstr\n";
	print $sql_text."\n";					  
	#$sth->execute or die $sth->errstr; # hier geschieht die Anfrage an die DB	
	$sth->execute;
	print 'Begin Schleife'."\n";
	while (my $arrayref = $sth->fetchrow_arrayref()) {	
		foreach(@$arrayref) {
			$result = $_;
		}
	}
	print 'Sum of current_run= '.$result."\n";
	
	my $limit = 200;
	if ($result >= $limit ){
		print 'In the last run was more then '.$limit.' change -> same run_modus.'."\n";
		$last_run_change = 'true';
	} else { 
		print 'Not more then '.$limit.' were change -> next run_modus.'."\n\n";
		$last_run_change = 'false';
	}
	print 'last_run_change='.$last_run_change."\n";
	
	# set back to false
	#print 'set back to false'."\n";
	$sql_text = " update cw_starter set last_run_change = 'false'; ";
	$sth = $dbh->prepare( $sql_text );
	$sth->execute;
	
	# set back to false
	#print 'set back to false'."\n";
	$sql_text = " update cw_starter set current_run = 0; ";
	$sth = $dbh->prepare( $sql_text );
	$sth->execute;
	
	close_db();
	
}

sub open_db{
	#load password
	open(PWD, "</home/sk/.mytop");
	my $password = '';
	do {
		my $test = <PWD>;
		if ($test =~ /^pass=/ ) {
			$password = $test;
			$password =~ s/^pass=//g;
			$password =~ s/\n//g;
		}
	}
	while (eof(PWD) != 1);
	close(PWD);
	#print "-".$password."-\n";

	#Connect to database u_sk
	$dbh = DBI->connect( 'DBI:mysql:u_sk_yarrow:host=sql',
							'sk',
							$password ,
							{
							  RaiseError => 1,
							  AutoCommit => 1
							}
						  ) or die "Database connection not made: $DBI::errstr" . DBI->errstr;
	$password = '';	
}

sub close_db{

	# close database
	$dbh->disconnect();
	
}


sub get_time{
	our ($akSekunden, $akMinuten, $akStunden, $akMonatstag, $akMonat,
	    $akJahr, $akWochentag, $akJahrestag, $akSommerzeit) = localtime(time);
	our $CTIME_String = localtime(time);
	$akMonat 	= $akMonat + 1;
	$akJahr 	= $akJahr + 1900;	
	$akMonat   	= "0".$akMonat if ($akMonat<10);
	$akMonatstag = "0".$akMonatstag if ($akMonatstag<10);
	$akStunden 	= "0".$akStunden if ($akStunden<10);
	$akMinuten 	= "0".$akMinuten if ($akMinuten<10);
}
