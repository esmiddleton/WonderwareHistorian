/*


!!! This script makes UNSUPPORTED modifications to your Runtime database !!!
!!!                       USE AT YOUR OWN RISK                           !!!


License
-------
This script can be used without additional charge with any licensed Wonderware Historian server. 
The terms of use are defined in your existing End User License Agreement for the 
Wonderware Historian software.

Modified: 	18-Feb-2010
By:			E. Middleton



This SQL script selects data from an existing Historian system and creates output
in the form of a FastLoad CSV file. It assumes the column separator character
will be a pipe (|). This can be achieved using the osql command-line utility as:

	sqlcmd -E -s "," -S . -d Runtime -m-1 -h-1 -W -r1 -Q "exec wwkbExportToFastLoadCSV" -o FastLoad.csv

This script will return the data for 24 hours at a time. Each execution will
retrieve the day following the previous execution. To configure the time period to export
and the Public Name Space group to exports, enter values in the System Paremeters with names
starting with "FastLoad".

To make it easier to always have unique file names, you can use this in a Windows .BAT file containing:

	@for /f "tokens=*" %%i in ('sqlcmd -E -d Runtime -Q "set nocount on; select Value from SystemParameter where Name='FastLoadCount'" -h-1 -W') DO @set Label=%%i
	sqlcmd -E -s "," -S . -d Runtime -m-1 -h-1 -W -r1 -Q "exec wwkbExportToFastLoadCSV" -o FastLoad-%Label%.csv

*/


USE Runtime

-- Add some new System Parameters if they don't exist already
IF NOT EXISTS (SELECT * FROM SystemParameter WHERE Name LIKE 'FastLoad%')
	BEGIN
		DECLARE @Midnight AS DATETIME
		SET @Midnight = DATEADD(Day, 0, DATEDIFF(Day, 0, GetDate()))
		INSERT INTO SystemParameter (Name, Value, Editable, Description, Status)
		VALUES ('FastLoadStartDate', CAST(CONVERT(nvarchar(35),DATEADD(day,-1,@Midnight),120) AS sql_variant), 1, 'Oldest data to export',0),
		('FastLoadEndDate', CONVERT(nvarchar(35),@Midnight,120), 1, 'Newest data to export',0),
		('FastLoadCount', 0, 1, 'Number of times the export has executed',0),
		('FastLoadPublicGroup', 'Time', 1, 'Public Name Space Group to export',0),
		('FastLoadLastEndDate', NULL, 1, 'The end time used for the last export',0)
	END

	
-- Delete the existing (if any) stored procedure
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[wwkbExportToFastLoadCSV]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[wwkbExportToFastLoadCSV]
GO

CREATE PROCEDURE wwkbExportToFastLoadCSV
AS
SET NOCOUNT ON
--SET FORCEPLAN ON

DECLARE @HoursToExport AS INT
SET @HoursToExport = 24 -- The number of hours to export per execution


-- Bound the retrieval period base on the last execution
DECLARE @OverallStartTime AS DateTime
SET @OverallStartTime = (SELECT CAST(Value AS DateTime) FROM SystemParameter WHERE Name='FastLoadStartDate') 

DECLARE @OverallEndTime AS DateTime
SET @OverallEndTime = (SELECT CAST(Value AS DateTime) FROM SystemParameter WHERE Name='FastLoadEndDate') 

DECLARE @LastEndTime AS DateTime
SET @LastEndTime = (SELECT CAST(Value AS DateTime) FROM SystemParameter WHERE Name='FastLoadLastEndDate') 

DECLARE @EndTime AS DateTime
DECLARE @StartTime AS DateTime
SET @StartTime = ISNULL(@LastEndTime,@OverallStartTime)
SET @EndTime = DATEADD(hour,@HoursToExport,@StartTime)


DECLARE @GroupName AS NVARCHAR(MAX)
SET @GroupName = (SELECT CAST(Value AS NVARCHAR) FROM SystemParameter WHERE Name='FastLoadPublicGroup') 

IF @OverallStartTime <= @StartTime 
	BEGIN
		-- Output header information for the FastLoad CSV file
		PRINT 'ASCII'
		PRINT '|'
		-- Username, Time format (1=local, 0=UTC), Time Zone, Block Behavior (10=Original with tagname, 11=Original with wwTagKey), Time span (0=to present, 1=CSV span only)
		PRINT 'wwkbExportToFastLoadCSV|0|UTC|10|1' -- For UTC time
		-- PRINT 'wwkbExportToFastLoadCSV|1|Server Local|10|1' -- For server local time

		DECLARE @Tags TABLE (TagName NVARCHAR(200))
		INSERT @Tags (TagName)
			SELECT t.TagName
			FROM dbo.PublicNameSpace ns
			LEFT JOIN dbo.PublicGroupTag pgt
				ON pgt.NameKey = ns.NameKey
			LEFT JOIN dbo.Tag t
				ON pgt.wwDomainTagKey = t.wwTagKey
			WHERE ns.Name = @GroupName
			AND t.DateCreated < @EndTime
		    --AND t.TagName NOT LIKE 'Sys%' -- Use to omit system tags

		-- Output the actual data
		SELECT CAST(
		  T.TagName+'|'+	-- TagName or wwTagKey, depending on flag in header above
		  '0|'+ 			-- Value type (0=original)
		  CONVERT(nvarchar(10), H.DateTime, 111)+'|'+ -- Date in YYYY/MM/DD format
		  LEFT(CONVERT(nvarchar(25), H.DateTime, 14),12)+'|'+ -- Time in HH:MM:SS.SSS format (truncate to milliseconds)
		  '0|'+	 			-- Value units (0=EU, 1=raw)
		  CAST(H.vValue AS NVARCHAR(MAX))+'|'+	-- Value
		  CAST(H.QualityDetail AS NVARCHAR(10))-- Quality detail
		  AS NVARCHAR(MAX))
		FROM @Tags T 
		  INNER REMOTE JOIN History H 
		  ON T.TagName = H.TagName
		WHERE wwRetrievalMode = 'Delta'
		  AND H.wwTimeZone='UTC' -- Omit this line for server local time (not recommended)
		  AND H.DateTime > @StartTime 
		  AND H.DateTime <= @EndTime
		  --AND QualityDetail <> 65536
 		  --ORDER BY DateTime, H.TagName -- Not actually required

		UPDATE SystemParameter SET Value= CONVERT(nvarchar(35),@EndTime,120) WHERE Name='FastLoadLastEndDate'
		UPDATE SystemParameter SET Value=CAST(a.Value AS INT)+1
			FROM SystemParameter INNER JOIN SystemParameter a ON SystemParameter.Name=a.Name
			WHERE SystemParameter.Name='FastLoadCount'
	END
ELSE
	PRINT 'All done.'

GO

/*

wwkbExportToFastLoadCSV

*/
