/*

Add Localized Tag Descriptions
==============================

!!! This script makes UNSUPPORTED modifications to your Runtime database !!!
!!!                       USE AT YOUR OWN RISK                           !!!

This SQL script extends the Historian "Runtime" database by adding one table
and a new view to support localized tag descriptions based on the database
login's Default Language. The database user can be any login (SQL, Windows, 
or Windows Group), but since the language is specific to the login, all 
Windows logins sharing the same Windows group login will have the same 
language. Use SQL Management Studio to assign the appropriate "Default Language"
to each login.

To use this capability, run the SQL Script, and then set the "Default Schema"
of any SQL Login which should see translated descriptions from the original "dbo"
schema to the new "local" schema created by this script. You can use the
SQL Management Studio GUI to set the default schema.

To add more translations, add them to the "Local.TagDescription" table. The "LangID"
column is the SQL Server "langid" as seen in the "sys.syslanguages" table.

License
-------
This script can be used without additional charge with any licensed Wonderware Historian server. 
The terms of use are defined in your existing End User License Agreement for the 
Wonderware Historian software.


Modified: 	18-Jun-2013
By:			E. Middleton

*/

USE Runtime

-- Create special 'Local' schema for this extension to the "Runtime" database
DECLARE @CreateSchema VARCHAR(MAX)
SET @CreateSchema = 'CREATE SCHEMA Local AUTHORIZATION dbo'
IF NOT EXISTS(SELECT * FROM sys.schemas WHERE name='Local')
	EXEC(@CreateSchema)
GO

-- Create a table to hold the translated descriptions
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'Local.TagDescription') AND type in (N'U'))
BEGIN
CREATE TABLE [Local].[TagDescription](
	[TagName] [nvarchar](250) NOT NULL,
	[LocalDesc] [nvarchar](500) NOT NULL,
	[LangID] [int] NOT NULL,
 CONSTRAINT [PK_TagDescription] PRIMARY KEY CLUSTERED 
(
	[TagName] ASC,
	[LangID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- Add some example translations for a few languages (translations compliments of Google)
DECLARE @NewTranslations TABLE(TagName nvarchar(255), LocalDesc nvarchar(512), LangID int)

INSERT @NewTranslations(TagName, LocalDesc, LangID)
	VALUES('SysTimeSec','Hora del sistema: segundo',5), -- Spanish
	('SysTimeSec','Systemzeit: Sekunden',1) -- German

/*
	To find the appropriate value to use for "LangID", run the query below:
	
		select langid, name, alias from sys.syslanguages
*/

-- Add the translations from above which do not already exist
INSERT Local.TagDescription (TagName, LocalDesc, LangID)
	SELECT n.TagName, n.LocalDesc, n.LangID
	FROM @NewTranslations n
	LEFT OUTER JOIN Local.TagDescription o ON o.LangID = n.LangID AND o.TagName = n.TagName
	WHERE o.LangID IS NULL
GO

-- Create a view that mimics the "Tag" table, but which replaces the "Description" column
-- with the localized description from "Local.TagDescription" created above. If there
-- is no translated description, use the "Description" from the "Tag" table as the default.
IF  EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[Local].[Tag]'))
DROP VIEW [Local].[Tag]
GO

IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[Local].[Tag]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [Local].[Tag] AS
SELECT t.[TagName]
      ,[IOServerKey]
      ,[StorageNodeKey]
      ,[wwTagKey]
      ,[TopicKey]
      ,[Description]=ISNULL(l.LocalDesc,t.Description)
      ,[AcquisitionType]
      ,[StorageType]
      ,[AcquisitionRate]
      ,[StorageRate]
      ,[ItemName]
      ,[TagType]
      ,[TimeDeadband]
      ,[DateCreated]
      ,[CreatedBy]
      ,[CurrentEditor]
      ,[SamplesInActiveImage]
      ,[AIRetrievalMode]
      ,[Status]
      ,[CalculatedAISamples]
      ,[ServerTimeStamp]
      ,[DeadbandType]
      ,[CEVersion]
      ,[AITag]
      ,[TagId]
      ,[ChannelStatus]
      ,[AIHistory]
      ,[ChangeVersion]
  FROM [dbo].[Tag] t
  LEFT OUTER JOIN Local.TagDescription l ON l.TagName = t.TagName AND l.LangID=@@LANGID
' 
GO

grant select on Local.Tag to public

/*

-- Login to SQL Server using a login with the desired "Default Language" and then run
-- the query below to add a placeholder translation for every tag that does not already
-- have a translation defined for that language. Then, a user can "Edit" the "TagDescription"
-- table to replace the template description with the desired translation.

INSERT Local.TagDescription (TagName, LocalDesc, LangID)
	SELECT t.TagName, 'ToDo: '+ t.Description, @@LANGID 
	FROM dbo.Tag t
	LEFT OUTER JOIN Local.TagDescription l ON l.TagName = t.TagName AND l.LangID=@@LANGID
	WHERE l.TagName IS NULL 
	AND t.TagName LIKE 'SysT%'

*/
