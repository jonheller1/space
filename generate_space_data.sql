/*

This is all very experimental, do not use this yet.

This file loads and transforms data from the awesome JSR Launch Vehicle Database sdb.tar.gz file into an Oracle database.

TODO:
1. Finish loading files into _staging tables, especially the LAUNCH_STAGING.
2. Transform _staging tables into final tables.
3. Verify data integrity, maybe cleanup tables.
4. Create final presentation tables.
5. Create exports of presentation tables into easy-to-load scripts.
6. Host those exports on different sites.
*/


--------------------------------------------------------------------------------
--#1: Create directories.  You may also need to grant permission on the folder.
--  This is usually the ora_dba group on windows, or the oracle users on Unix.
--------------------------------------------------------------------------------

create or replace directory sdb as 'C:\space\sdb.tar';
create or replace directory sdb_sdb as 'C:\space\sdb.tar\sdb\';



--------------------------------------------------------------------------------
--#2. Auto-manually generate external files to load the file.
-- This is a semi-automated process because the files are not 100% formatted correctly.
--------------------------------------------------------------------------------
create or replace function get_external_table_ddl(
	p_table_name varchar2,
	p_directory varchar2,
	p_file_name varchar2
) return varchar2 is
	v_clob clob;
	v_end_position number;
	v_format_description varchar2(32767);
	v_skip_count number;
	v_width_in_bytes number;
	v_number_of_fields number;


	type string_table is table of varchar2(32767);
	type number_table is table of number;
	v_column_names string_table := string_table();
	v_display_format string_table := string_table();
	v_byte_start_positions number_table := number_table();

	v_column_sql varchar2(32767);
	v_loader_fields varchar2(32767);

	v_template varchar2(32767) := q'[
create table $$TABLE_NAME$$
(
$$TABLE_COLUMNS$$
)
organization external
(
	type oracle_loader
	default directory $$DIRECTORY$$
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip $$SKIP_NUMBER$$
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
$$LOADER_COLUMNS$$
		)
	)
	location ('$$FILE_NAME$$')
)
reject limit unlimited
/]';

begin
	--Read the CLOB.
	v_clob := dbms_xslprocessor.read2clob(flocation => upper(p_directory), fname => p_file_name);

	--Get everything up until the first END.
	v_end_position := dbms_lob.instr(v_clob, chr(10)||'END');

	--Ensure there was a format description found.
	if v_end_position = 0 then
		raise_application_error(-20000, 'Could not find format description.');
	end if;

	v_format_description := dbms_lob.substr(v_clob, v_end_position, 1);
	v_skip_count := regexp_count(v_format_description, chr(10)) + 2;

	v_width_in_bytes := to_number(regexp_substr(v_format_description, 'NAXIS1\s*=\s*([0-9]+)', 1, 1, '', 1));
	v_number_of_fields := to_number(regexp_substr(v_format_description, 'TFIELDS\s*=\s*([0-9]+)', 1, 1, '', 1));

	--Populate arrays of the values.
	for i in 1 .. v_number_of_fields loop
		v_column_names.extend;
		v_display_format.extend;
		v_byte_start_positions.extend;

		v_column_names(v_column_names.count) := regexp_substr(v_format_description, 'TTYPE[0-9]*\s*=\s*''([^'']*)''', 1, i, '', 1);
		v_display_format(v_display_format.count) := regexp_substr(v_format_description, 'TDISP[0-9]*\s*=\s*''([^'']*)''', 1, i, '', 1);
		v_byte_start_positions(v_byte_start_positions.count) := regexp_substr(v_format_description, 'TBCOL[0-9]*\s*=\s*([0-9]*)', 1, i, '', 1);

		--Sometimes it's TPOS instad of TBCOL:
		if v_byte_start_positions(v_byte_start_positions.count) is null then
			v_byte_start_positions(v_byte_start_positions.count) := regexp_substr(v_format_description, 'TPOS[0-9]*\s*=\s*([0-9]*)', 1, i, '', 1);
		end if;
	end loop;

	--Create a list of columns.
	for i in 1 .. v_number_of_fields loop
		v_column_sql := v_column_sql || ',' || chr(10) || '	' || v_column_names(i) ||
			' varchar2(' ||
			case
				when i = v_number_of_fields then (v_width_in_bytes - v_byte_start_positions(i) + 1)
				else (v_byte_start_positions(i+1) - v_byte_start_positions(i))
			end || ')';

		v_loader_fields := v_loader_fields || ',' || chr(10) || '			' || v_column_names(i) || ' (' ||
			v_byte_start_positions(i) || ':' ||
			case
				when i = v_number_of_fields then (v_width_in_bytes)
				else v_byte_start_positions(i+1) - 1
			end || ')' || ' ' ||
			' char(' ||
			case
				when i = v_number_of_fields then (v_width_in_bytes - v_byte_start_positions(i) + 1)
				else (v_byte_start_positions(i+1) - v_byte_start_positions(i))
			end || ')';
	end loop;

	--Return the table columns and the SQL Loader columns.
	return replace(replace(replace(replace(replace(replace(v_template
		,'$$TABLE_NAME$$', p_table_name)
		,'$$TABLE_COLUMNS$$', substr(v_column_sql, 3))
		,'$$DIRECTORY$$', p_directory)
		,'$$SKIP_NUMBER$$', v_skip_count)
		,'$$LOADER_COLUMNS$$', substr(v_loader_fields, 3))
		,'$$FILE_NAME$$', p_file_name);		
end get_external_table_ddl;
/






--------------------------------------------------------------------------------
--#3. Create external tables.
--------------------------------------------------------------------------------

/*
x A. organization
x B. family
x C. vehicle
x D. engine
x E. stage
x F. vehicle_stage
x G. reference
x H. site
x I. platform
 J. launch
*/


select get_external_table_ddl('organization_staging', 'sdb_sdb', 'Orgs') from dual;
select get_external_table_ddl('family_staging', 'sdb_sdb', 'Family') from dual;
select get_external_table_ddl('vehicle_staging', 'sdb_sdb', 'LV') from dual;
select get_external_table_ddl('engine_staging', 'sdb_sdb', 'Engines') from dual;
select get_external_table_ddl('stage_staging', 'sdb_sdb', 'stages') from dual;
select get_external_table_ddl('vehicle_stage_staging', 'sdb_sdb', 'LV_Stages') from dual;
select get_external_table_ddl('reference_staging', 'sdb_sdb', 'Refs') from dual;
select get_external_table_ddl('site_staging', 'sdb_sdb', 'Sites') from dual;
select get_external_table_ddl('platform_staging', 'sdb_sdb', 'Platforms') from dual;
select get_external_table_ddl('launch_staging', 'sdb', 'lvtemplate') from dual;


--select get_external_table_ddl('launch_staging', 'sdb', 'all') from dual;

/*
Directions for manually checking results:
1. Check the first row (to ensure that the SKIP was correct)
2. Check each column (to ensure the widths are correct)
3. Check that there is no .BAD file in the directory (to ensure nothing broke SQL*Loader and couldn't even load)
4. Check the row count against the file line count
*/


--Auto-generated:
create table organization_staging
(
	Code     varchar2(9),
	UCode    varchar2(9),
	StateCode varchar2(7),
	Type     varchar2(17),
	Class    varchar2(2),
	TStart   varchar2(13),
	TStop    varchar2(13),
	ShortName varchar2(18),
	Name     varchar2(81),
	Location varchar2(53),
	Longitude varchar2(13),
	Latitude varchar2(11),
	Error    varchar2(8),
	Parent   varchar2(13),
	ShortEName varchar2(17),
	EName    varchar2(61),
	UName    varchar2(230)
)
organization external
(
	type oracle_loader
	default directory sdb_sdb
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip 59
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
			Code     (1:9)  char(9),
			UCode    (10:18)  char(9),
			StateCode (19:25)  char(7),
			Type     (26:42)  char(17),
			Class    (43:44)  char(2),
			TStart   (45:57)  char(13),
			TStop    (58:70)  char(13),
			ShortName (71:88)  char(18),
			Name     (89:169)  char(81),
			Location (170:222)  char(53),
			Longitude (223:235)  char(13),
			Latitude (236:246)  char(11),
			Error    (247:254)  char(8),
			Parent   (255:267)  char(13),
			ShortEName (268:284)  char(17),
			EName    (285:345)  char(61),
			UName    (346:575)  char(230)
		)
	)
	location ('Orgs')
)
reject limit unlimited
/

create table family_staging
(
	Family   varchar2(21),
	Class varchar2(1)
)
organization external
(
	type oracle_loader
	default directory sdb_sdb
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip 12
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
			Family   (1:21)  char(21),
			Class (22:22)  char(1)
		)
	)
	location ('Family')
)
reject limit unlimited
/


create table vehicle_staging
(
	LV_Name  varchar2(33),
	LV_Family varchar2(21),
	LV_SFamily varchar2(21),
	LV_Manufacturer varchar2(21),
	LV_Variant varchar2(11),
	LV_Alias varchar2(20),
	LV_Min_Stage varchar2(4),
	LV_Max_Stage varchar2(2),
	Length varchar2(6),
	Diameter varchar2(6),
	Launch_Mass varchar2(9),
	LEO_Capacity varchar2(9),
	GTO_Capacity varchar2(9),
	TO_Thrust varchar2(9),
	Class varchar2(2),
	Apogee varchar2(7),
	Range  varchar2(6)
)
organization external
(
	type oracle_loader
	default directory sdb_sdb
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip 58
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
			LV_Name  (1:33)  char(33),
			LV_Family (34:54)  char(21),
			LV_SFamily (55:75)  char(21),
			LV_Manufacturer (76:96)  char(21),
			LV_Variant (97:107)  char(11),
			LV_Alias (108:127)  char(20),
			LV_Min_Stage (128:131)  char(4),
			LV_Max_Stage (132:133)  char(2),
			Length (134:139)  char(6),
			Diameter (140:145)  char(6),
			Launch_Mass (146:154)  char(9),
			LEO_Capacity (155:163)  char(9),
			GTO_Capacity (164:172)  char(9),
			TO_Thrust (173:181)  char(9),
			Class (182:183)  char(2),
			Apogee (184:190)  char(7),
			Range  (191:196)  char(6)
		)
	)
	location ('LV')
)
reject limit unlimited
/

--WARNING: Column manually renamed
create table engine_staging
(
	Engine_Name varchar2(21),
	Engine_Manufacturer varchar2(21),
	Engine_Family varchar2(21),
	Engine_Alt_Name varchar2(13),
	Oxidizer varchar2(11),
	Fuel varchar2(21),
	Mass varchar2(11),
	Impulse varchar2(9),
	Thrust varchar2(11),
	Specific_Impulse varchar2(7),
	Duration varchar2(7),
	Chambers varchar2(4),
	first_launch_date varchar2(13),
	Usage varchar2(20)
)
organization external
(
	type oracle_loader
	default directory sdb_sdb
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip 49
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
			Engine_Name (1:21)  char(21),
			Engine_Manufacturer (22:42)  char(21),
			Engine_Family (43:63)  char(21),
			Engine_Alt_Name (64:76)  char(13),
			Oxidizer (77:87)  char(11),
			Fuel (88:108)  char(21),
			Mass (109:119)  char(11),
			Impulse (120:128)  char(9),
			Thrust (129:139)  char(11),
			Specific_Impulse (140:146)  char(7),
			Duration (147:153)  char(7),
			Chambers (154:157)  char(4),
			first_launch_date (158:170)  char(13),
			Usage (171:190)  char(20)
		)
	)
	location ('Engines')
)
reject limit unlimited
/

--WARNING: Some comments on the right-hand side are dropped, but I don't think that matters.
create table vehicle_stage_staging
(
	LV_Mnemonic varchar2(34),
	LV_Variant varchar2(11),
	Stage_No varchar2(3),
	Stage_Name varchar2(21),
	Qualifier varchar2(2),
	Dummy    varchar2(2),
	Multiplicity varchar2(3),
	Stage_Impulse varchar2(10),
	Stage_Apogee varchar2(7),
	Stage_Perigee varchar2(6)
)
organization external
(
	type oracle_loader
	default directory sdb_sdb
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip 37
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
			LV_Mnemonic (1:34)  char(34),
			LV_Variant (35:45)  char(11),
			Stage_No (46:48)  char(3),
			Stage_Name (49:69)  char(21),
			Qualifier (70:71)  char(2),
			Dummy    (72:73)  char(2),
			Multiplicity (74:76)  char(3),
			Stage_Impulse (77:86)  char(10),
			Stage_Apogee (87:93)  char(7),
			Stage_Perigee (94:99)  char(6)
		)
	)
	location ('LV_Stages')
)
reject limit unlimited
/

--WARNING: This file was manually adjusted.
create table stage_staging
(
	Stage_Name varchar2(21),
	Stage_Family varchar2(21),
	Stage_Manufacturer varchar2(21),
	Stage_Alt_Name varchar2(21),
	Length varchar2(6),
	Diameter varchar2(6),
	--Launch_Mass varchar2(7),
	--Dry_Mass varchar2(11),
	--Launch_Mass (97:103)  char(7),
	--Dry_Mass (104:114)  char(11),
	Launch_Mass varchar2(8),
	Dry_Mass varchar2(10),
	Thrust varchar2(9),
	Duration varchar2(7),
	Engine varchar2(19),
	NEng varchar2(3),
	Class varchar2(1)
)
organization external
(
	type oracle_loader
	default directory sdb_sdb
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip 47
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
			Stage_Name (1:21)  char(21),
			Stage_Family (22:42)  char(21),
			Stage_Manufacturer (43:63)  char(21),
			Stage_Alt_Name (64:84)  char(21),
			Length (85:90)  char(6),
			Diameter (91:96)  char(6),
			Launch_Mass (97:104)  char(8),
			Dry_Mass (105:114)  char(10),
			Thrust (115:123)  char(9),
			Duration (124:130)  char(7),
			Engine (131:149)  char(19),
			NEng (150:152)  char(3),
			Class (153:153)  char(1)
		)
	)
	location ('Stages')
)
reject limit unlimited
/

--WARNING: This works, but the file format has "#" comments that don't work well.
create table reference_staging
(
	Cite     varchar2(21),
	Reference varchar2(120)
)
organization external
(
	type oracle_loader
	default directory sdb_sdb
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip 12
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
			Cite     (1:21)  char(21),
			Reference (22:141)  char(120)
		)
	)
	location ('Refs')
)
reject limit unlimited
/

--WARNING: Two of the columns had to be manually resized.
create table site_staging
(
	Site    varchar2(9),
	Code     varchar2(13),
	Ucode   varchar2(13),
	Type    varchar2(5),
	StateCode varchar2(9),
	TStart   varchar2(13),
	TStop   varchar2(13),
	ShortName   varchar2(18),
	Name varchar2(81),
	Location  varchar2(53),
	Longitude varchar2(13),
	Latitude varchar2(11),
	Error varchar2(7),
	Parent  varchar2(13),
	--ShortEName   varchar2(18),
	--EName varchar2(60),
	--ShortEName   (272:289)  char(18),
	--EName (290:349)  char(60),
	ShortEName   varchar2(17),
	EName varchar2(61),
	UName varchar2(15)
)
organization external
(
	type oracle_loader
	default directory sdb_sdb
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip 59
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
			Site    (1:9)  char(9),
			Code     (10:22)  char(13),
			Ucode   (23:35)  char(13),
			Type    (36:40)  char(5),
			StateCode (41:49)  char(9),
			TStart   (50:62)  char(13),
			TStop   (63:75)  char(13),
			ShortName   (76:93)  char(18),
			Name (94:174)  char(81),
			Location  (175:227)  char(53),
			Longitude (228:240)  char(13),
			Latitude (241:251)  char(11),
			Error (252:258)  char(7),
			Parent  (259:271)  char(13),
			ShortEName   (272:288)  char(17),
			EName (289:349)  char(61),
			UName (350:364)  char(15)
		)
	)
	location ('Sites')
)
reject limit unlimited
/


create table platform_staging
(
	Code   varchar2(11),
	Ucode     varchar2(12),
	StateCode   varchar2(8),
	Type    varchar2(17),
	Class    varchar2(2),
	TStart   varchar2(13),
	TStop   varchar2(13),
	ShortName   varchar2(18),
	Name varchar2(81),
	Location  varchar2(41),
	Longitude varchar2(13),
	Latitude varchar2(10),
	Error varchar2(20),
	Parent  varchar2(13),
	ShortEName   varchar2(17),
	EName varchar2(61)
)
organization external
(
	type oracle_loader
	default directory sdb_sdb
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip 56
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
			Code   (1:11)  char(11),
			Ucode     (12:23)  char(12),
			StateCode   (24:31)  char(8),
			Type    (32:48)  char(17),
			Class    (49:50)  char(2),
			TStart   (51:63)  char(13),
			TStop   (64:76)  char(13),
			ShortName   (77:94)  char(18),
			Name (95:175)  char(81),
			Location  (176:216)  char(41),
			Longitude (217:229)  char(13),
			Latitude (230:239)  char(10),
			Error (240:259)  char(20),
			Parent  (260:272)  char(13),
			ShortEName   (273:289)  char(17),
			EName (290:350)  char(61)
		)
	)
	location ('Platforms')
)
reject limit unlimited
/




--drop table launch_staging;

--WARNING: Had to change the filename to "all", and change "group" to "payload_group", change skip to 0.
--TODO: There are some problems with the fields at the end.
create table launch_staging
(
	Launch_Tag varchar2(15),
	Launch_JD varchar2(11),
	Launch_Date varchar2(21),
	LV_Type  varchar2(25),
	Variant  varchar2(7),
	Flight_ID varchar2(21),
	Flight   varchar2(25),
	Mission  varchar2(25),
	Platform varchar2(10),
	Launch_Site varchar2(9),
	Launch_Pad varchar2(17),
	Apogee   varchar2(7),
	Apoflag  varchar2(2),
	Range    varchar2(5),
	RangeFlag varchar2(2),
	Dest     varchar2(13),
	Agency   varchar2(13),
	Launch_Code varchar2(5),
	Payload_Group    varchar2(25),
	Category varchar2(25),
	LTCite   varchar2(21),
	Cite     varchar2(21),
	Notes    varchar2(32)
)
organization external
(
	type oracle_loader
	default directory sdb
	access parameters
	(
		records delimited by x'0A' characterset 'UTF8'
		readsize 1048576
		skip 0
		fields ldrtrim
		missing field values are null
		reject rows with all null fields
		(
			Launch_Tag (1:15)  char(15),
			Launch_JD (16:26)  char(11),
			Launch_Date (27:47)  char(21),
			LV_Type  (48:72)  char(25),
			Variant  (73:79)  char(7),
			Flight_ID (80:100)  char(21),
			Flight   (101:125)  char(25),
			Mission  (126:150)  char(25),
			Platform (151:160)  char(10),
			Launch_Site (161:169)  char(9),
			Launch_Pad (170:186)  char(17),
			Apogee   (187:193)  char(7),
			Apoflag  (194:195)  char(2),
			Range    (196:200)  char(5),
			RangeFlag (201:202)  char(2),
			Dest     (203:215)  char(13),
			Agency   (216:228)  char(13),
			Launch_Code (229:233)  char(5),
			Payload_Group    (234:258)  char(25),
			Category (259:283)  char(25),
			LTCite   (284:304)  char(21),
			Cite     (305:325)  char(21),
			Notes    (326:357)  char(32)
		)
	)
	location ('all')
)
reject limit unlimited
/

select * from launch_staging;
