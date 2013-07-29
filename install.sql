-- This file is prepared for use on Tools with:

-- $ mysql -htools-db < install.sql

-- Check if utf8 with 'SHOW SESSION VARIABLES LIKE 'character_set%'';

-- To use it in other environments, p50380g50450__checkwiki_p needs to
-- be replaced with the name of the user database.

-- Create Checkwiki database.
CREATE DATABASE IF NOT EXISTS p50380g50450__checkwiki_p;

-- Connect to database.
USE p50380g50450__checkwiki_p;


-- Table cw_project.
CREATE TABLE IF NOT EXISTS cw_project
(ID SMALLINT NOT NULL,
 Project VARCHAR(100) NOT NULL,
 Lang VARCHAR(100),
 Last_Dump VARCHAR(100),
 WikiPage VARCHAR(400),
 Translation_Page VARCHAR(400) )
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;


-- Table cw_dumpscan.
CREATE TABLE IF NOT EXISTS cw_dumpscan
(Project VARCHAR(20) NOT NULL,
 Title VARCHAR(100) NOT NULL,
 Error SMALLINT NOT NULL,
 Notice VARCHAR(400),
 Ok INT,
 Found DATETIME,
 PRIMARY KEY (Project, Title, Error) )
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;


-- Table cw_error.
CREATE TABLE IF NOT EXISTS cw_error
(Project VARCHAR(20) NOT NULL,
 Title VARCHAR(100) NOT NULL,
 Error SMALLINT NOT NULL,
 Notice VARCHAR(400),
 Ok INT,
 Found DATETIME,
 PRIMARY KEY (Project, Title, Error) )
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;

CREATE INDEX Error_index ON cw_error (Error, Project, Ok);


-- Table cw_new.
CREATE TABLE IF NOT EXISTS cw_new
(Project VARCHAR(20) NOT Null,
 Title VARCHAR(100) NOT Null,
 PRIMARY KEY (Project, Title) )
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;


-- Table cw_error_desc.
CREATE TABLE IF NOT EXISTS cw_error_desc
(Project VARCHAR(100) NOT NULL,
 ID SMALLINT NOT NULL,
 Prio SMALLINT NOT NULL,
 Name VARCHAR(255),
 Text VARCHAR(4000),
 Name_Trans VARCHAR(255),
 Text_Trans VARCHAR(4000) )
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;


-- Table cw_overview (for overview, updated by cron job with merge).
CREATE TABLE IF NOT EXISTS cw_overview
(ID SMALLINT,
 Project VARCHAR(100) NOT NULL,
 Lang VARCHAR(100),
 Errors MEDIUMINT,
 Done MEDIUMINT,
 Last_Dump VARCHAR(100),
 Last_Update VARCHAR(100),
 Project_Page VARCHAR(400),
 Translation_Page VARCHAR(400) )
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;


-- Table cw_overview_errors.
CREATE TABLE IF NOT EXISTS cw_overview_errors
(Project VARCHAR(100) NOT NULL,
 ID SMALLINT,
 Errors MEDIUMINT,
 Done MEDIUMINT,
 Name VARCHAR(400),
 Name_Trans VARCHAR(400),
 Prio SMALLINT)
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;


-- Table cw_change.
CREATE TABLE IF NOT EXISTS cw_change
(Project VARCHAR(100),
 Title VARCHAR(100),
 Daytime DATETIME,
 Scan_Live BOOLEAN DEFAULT FALSE)
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;


-- Table tt (Templatetiger).
CREATE TABLE IF NOT EXISTS tt
(Project VARCHAR(100),
 ID SMALLINT,
 Title VARCHAR(100),
 Template INT,
 Name VARCHAR(4000),
 Number INT,
 Parameter VARCHAR(4000),
 Value TEXT);
