/*

	The stored procedure created by this script will calculate the "on" times for COMBINATIONS of discrete
	tags. For a list of discrete tags, it calculates the times, in milliseonds, that:

		.	None of them where "on"
		.	All of them where "on"
		.	Any of them where "on"

	It takes as parameters start/end times to use and a comma-separated list of tagname. 
	
	The "NotFinal" column indicates when the end time is later than the last value received for any of the tags queried.

	Related to forum thread "How to get pump runtimes when they ran at same time?" at:
	https://softwareforums.schneider-electric.com/wonderware/technical_support/f/7/p/19691/68750#68750


	Example Usage:

		exec wwkbAnyAllDiscrete '2016-07-08 6:00', '2016-07-08 8:00','Motor1.State,Motor2.State,Motor3.State'


	Example Output:

	  StartDateTime            EndDateTime              NoneMsecs  AllMsecs  AnyMsecs  NoneCount  AllCount  AnyCount  ChangeCount  NotFinal
		2016-07-08 06:00:00.000  2016-07-08 08:00:00.000  3737072    3991      1751512   550        5         838       1699         0


	Limitations:

		.	It will NOT support tagnames that include any special characters that are not allowed in an unbracketed 
			SQL Server column name, such as spaces.
		.	Requires Wonderware Historian 2014 (11.5) or later

*/

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[wwkbAllDiscretesOn]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[wwkbAllDiscretesOn]
GO


CREATE PROCEDURE wwkbAnyAllDiscrete 
   @startdate DATETIME2,
   @enddate DATETIME2, 
   @tags NVARCHAR(MAX)
AS 

   DECLARE @sql115 nvarchar(MAX)
   -- Generate a 'wide' query to total all the tag values, but subtract "1" from all but the last tag 
   -- so that when all equal "1", the total will be "1"
   SET @sql115 = N'select StartDateTime=min(DateTime),EndDateTime=max(dateadd(millisecond,Msecs,DateTime)),
			NoneMsecs=sum(NoneMsecs),AllMsecs=sum(AllMsecs),AnyMsecs=sum(AnyMsecs),
			NoneCount=sum(NoneCount),AllCount=sum(AllCount),AnyCount=sum(AnyCount),
			ChangeCount=count(*),
			NotFinal=sum(NotFinal) 
	   from (
	   select DateTime,
		NoneMsecs=CASE WHEN AnyCount=0 THEN Msecs ELSE 0 END,
		AllMsecs=CASE WHEN AllCount=1 THEN Msecs ELSE 0 END,
		AnyMsecs=CASE WHEN AnyCount>0 THEN Msecs ELSE 0 END,
		NoneCount=CASE WHEN AnyCount=0 THEN 1 ELSE 0 END,
		AllCount=CASE WHEN AllCount=1 THEN 1 ELSE 0 END,
		AnyCount=CASE WHEN AnyCount>0 THEN 1 ELSE 0 END,
		NotFinal=CASE WHEN Msecs IS NULL THEN 1 ELSE 0 END,
		Msecs
	   FROM OPENQUERY(INSQL, ''SELECT DateTime, 
		AllCount=[' + REPLACE(@tags,',',']-1+[') + '],
		AnyCount=[' + REPLACE(@tags,',',']+[') + '],
		Msecs=wwResolution FROM WideHistory
	   WHERE DateTime >= "' + CONVERT(varchar(26), @startdate, 121) + '"
	   AND DateTime <= "' + CONVERT(varchar(26), @enddate, 121) + '"
	   AND wwRetrievalMode = "delta"'')
	   ) deltaRows'

   EXEC (@sql115)
GO

