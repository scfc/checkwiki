-- This file is prepared for use on Tools with:

-- $ mysql -htools-db < install.sql

-- To use it in other environments, p50380g50450__checkwiki_p needs to
-- be replaced with the name of the user database.

-- Create Checkwiki database.
CREATE DATABASE IF NOT EXISTS p50380g50450__checkwiki_p;

-- Connect to database.
USE p50380g50450__checkwiki_p;

-- Table cw_project.
CREATE TABLE IF NOT EXISTS cw_project
(ID BIGINT,
 Project VARCHAR(100),
 Lang VARCHAR(100),
 Last_Dump VARCHAR(100),
 WikiPage VARCHAR(400),
 Translation_Page VARCHAR(400));

-- Table cw_dumpscan.
CREATE TABLE IF NOT EXISTS cw_dumpscan
(Project VARCHAR(20) NOT NULL,
 Title VARCHAR(100) NOT NULL,
 Error SMALLINT NOT NULL,
 Notice VARCHAR(200),
 Ok INT,
 Found DATETIME,
 PRIMARY KEY (Project, Title, Error)
);

-- Table cw_error.
CREATE TABLE IF NOT EXISTS cw_error
(Project VARCHAR(20) NOT NULL,
 Title VARCHAR(100) NOT NULL,
 Error SMALLINT NOT NULL,
 Notice VARCHAR(200),
 Ok INT,
 Found DATETIME,
 PRIMARY KEY (Project, Title, Error)
);

CREATE INDEX ProjectIndex
ON cw_error (Project, Error);

-- Table cw_error_desc.
CREATE TABLE IF NOT EXISTS cw_error_desc
(Project VARCHAR(100),
 ID INT,
 Prio INT,
 Name VARCHAR(255),
 Text VARCHAR(4000),
 Name_Trans VARCHAR(255),
 Text_Trans VARCHAR(4000));

-- Table cw_overview (for overview, updated by cron job with merge).
CREATE TABLE IF NOT EXISTS cw_overview
(ID INT,
 Project VARCHAR(100),
 Lang VARCHAR(100),
 Errors BIGINT,
 Done BIGINT,
 Last_Dump VARCHAR(4000),
 Last_Update VARCHAR(4000),
 Project_Page VARCHAR(4000),
 Translation_Page VARCHAR(4000));

-- Table cw_overview_errors.
CREATE TABLE IF NOT EXISTS cw_overview_errors
(Project VARCHAR(100),
 ID INT,
 Errors BIGINT,
 Done BIGINT,
 Name VARCHAR(4000),
 Name_Trans VARCHAR(4000),
 Prio INT);

-- Table cw_statistic_all (longtime statistics).
CREATE TABLE IF NOT EXISTS cw_statistic_all
(Project VARCHAR(100),
 Daytime DATETIME,
 Errors BIGINT);

-- Table cw_statistic (statistics for all Errors and 100 days).
CREATE TABLE IF NOT EXISTS cw_statistic
(Project VARCHAR(100),
 ID INT,
 Nr INT,
 Daytime DATETIME,
 Errors BIGINT);

-- Table cw_new.
CREATE TABLE IF NOT EXISTS cw_new
(Project VARCHAR(20),
 Title VARCHAR(100),
 Daytime DATETIME
);

-- Table cw_change.
CREATE TABLE IF NOT EXISTS cw_change
(Project VARCHAR(100),
 Title VARCHAR(4000),
 Daytime DATETIME,
 Scan_Live BOOLEAN DEFAULT FALSE);

-- Table tt (Templatetiger).
CREATE TABLE IF NOT EXISTS tt
(Project VARCHAR(100),
 ID	INT,
 Title VARCHAR(4000),
 Template INT,
 Name VARCHAR(4000),
 Number INT,
 Parameter VARCHAR(4000),
 Value TEXT);
