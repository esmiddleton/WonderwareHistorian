/*
Find Tags Not Configured For Replication And Start Replicating Them
===================================================================

!!! This script makes UNSUPPORTED modifications to your Runtime database !!!
!!!                       USE AT YOUR OWN RISK                           !!!

This SQL script extends the Historian "Runtime" database adding one stored procedure
and a new System Parameter to set the "Default" replication group.

The stored procedure (as delivered) filters out "System Tags" and filters out
local Replication Groups.

This stored procedure uses a new System Parameter named "ReplicationDefaultGroup":

	*			=	All replication groups (except local ones)
	(Simple)	=	All Simple Replication (the default)
	(None)		=	Stop automatically creating replication entities
	GroupName	=   The name of a specific replication group (e.g. "15 Minutes")

To add all "missing" replication and commit the changes:

	EXEC wwkbAddMissingReplicatedTags


OPTIONAL
--------
This script also includes a database trigger that will automatically create the 
replicated tags any time a new tag is added. This trigger may negatively impact
tag creation performance, particularly for bulk tag creation, such as when
deploying numerous Galaxy objects or importing a tag configuration CSV. This part
of the script is commented out (as distributed) for this reason.

It also includes script to create a SQL Agent job that will normally execute every hour.

*/

USE [Runtime]
GO


-- Add a new System Parameter if it doesn't exist already
-- By default, this will use "Simple" replication for all tags
IF NOT EXISTS (SELECT * FROM SystemParameter WHERE Name = 'ReplicationDefaultGroup')
	INSERT INTO SystemParameter (Name, Value, Editable, Description, Status)
	VALUES ('ReplicationDefaultGroup','(Simple)',1,'Name of default replication group: "(Simple)"=Simple Replication, "*"=All, "(None)"=Disable',0)

-- Delete the existing (if any) stored procedure
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[wwkbAddMissingReplicatedTags]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[wwkbAddMissingReplicatedTags]
GO

-- Create the new stored procedure
CREATE PROCEDURE dbo.wwkbAddMissingReplicatedTags
	@DEBUG AS BIT = 0,
	@AutoCommit AS BIT = 1
AS
BEGIN
	SET NOCOUNT ON
	
	-- Read the configured Replication Group name from System Parameters
	DECLARE @DefGroups AS NVARCHAR(50)
	SET @DefGroups = (SELECT CAST(Value AS NVARCHAR(50)) FROM SystemParameter WHERE Name='ReplicationDefaultGroup')

	-- Create a list of Replication Groups based on the System Parameter
	DECLARE @DefGroupList AS TABLE( ReplicationGroupKey INT)
	IF @DefGroups = '*' 
		BEGIN
			INSERT INTO @DefGroupList (ReplicationGroupKey)
			SELECT ReplicationGroupKey FROM ReplicationGroup
		END
	ELSE
		IF @DefGroups = '(Simple)'
			BEGIN
				INSERT INTO @DefGroupList (ReplicationGroupKey)
				SELECT ReplicationGroupKey FROM ReplicationGroup
				WHERE ReplicationTypeKey = 1
			END
		ELSE
			IF @DefGroups <> '(None)'
				BEGIN
					INSERT INTO @DefGroupList (ReplicationGroupKey)
					SELECT ReplicationGroupKey FROM ReplicationGroup
					WHERE ReplicationGroupName = @DefGroups
				END

	IF @DEBUG = 1
		SELECT * FROM @DefGroupList ORDER BY ReplicationGroupKey

	-- Define a cursor to step through the list of "missing" Replication Entities
	DECLARE AddReplicatedTag CURSOR LOCAL FAST_FORWARD FOR
		SELECT 
			t.TagName AS SourceTagName,
			g.ReplicationGroupName,
			s.ReplicationServerName,
			g.ReplicationTypeKey
		FROM Tag t
		LEFT OUTER JOIN @DefGroupList l
		ON 1=1 -- Dummy value to force JOIN
		LEFT OUTER JOIN ReplicationTagEntity r
		ON t.TagName = r.SourceTagName AND l.ReplicationGroupKey = r.ReplicationGroupKey
		LEFT OUTER JOIN ReplicationGroup g
		ON l.ReplicationGroupKey = g.ReplicationGroupKey
		LEFT OUTER JOIN ReplicationServer s
		ON s.ReplicationServerKey = g.ReplicationServerKey
		LEFT OUTER JOIN AnalogTag a
		ON a.TagName = t.TagName
		WHERE r.SourceTagName IS NULL
		AND t.AcquisitionType <> 3 -- Not a System Tag
		AND s.ReplicationServerName <> 'Local Replication' -- Skip "loopback" replication
		AND t.TagType <> 5 -- Is not an Event tag
		AND t.CreatedBy <> 'ReplicationService' -- Is not a Replicated tag
		AND t.TagType <> 7 -- Is not a Summary tag
		AND ((g.ReplicationTypeKey = 1) -- Is simple replication
			OR (t.TagType=1 AND a.RawType IN (1,2,4) AND g.ReplicationTypeKey = 2) -- Is an AnalogSummary for an floating point analog tag
			OR (t.TagType=1 AND a.RawType = 3  AND g.ReplicationTypeKey IN (2,3)) -- Is for an integer analog tag
			OR (t.TagType=2 AND g.ReplicationTypeKey = 3) -- Is a StateSummary for a discrete tag
			OR (t.TagType=3 AND g.ReplicationTypeKey = 3) -- Is a StateSummary for a string tag
		)

	-- Use the cursor above to add each missing Replication Entity
	OPEN AddReplicatedTag

	DECLARE @Tag AS NVARCHAR(512)
	DECLARE @Group AS NVARCHAR(512)
	DECLARE @Server AS NVARCHAR(512)
	DECLARE @Type AS TINYINT
	DECLARE @TagAdded AS BIT
	SET @TagAdded = 0

	FETCH NEXT FROM AddReplicatedTag
	INTO @Tag, @Group, @Server, @Type
		
	WHILE @@FETCH_STATUS = 0
	BEGIN
		IF @DEBUG=1
			PRINT @Tag + ', ' + CASE WHEN @Group='' THEN 'Simple' ELSE @Group END + ', ' + @Server + ', ' + CAST(@Type AS NVARCHAR(10))
		ELSE
			BEGIN
				EXEC aaAddReplicationTagEntity 
					@SourceTagName = @Tag, 
					@ReplicationGroupName = @Group,
					@ReplicationServerName = @Server,
					@ReplicationTypeKey = @Type
				SET @TagAdded = 1
			END

		
		FETCH NEXT FROM AddReplicatedTag
		INTO @Tag, @Group, @Server, @Type
	END

	CLOSE AddReplicatedTag
	DEALLOCATE AddReplicatedTag
	
	IF @DEBUG=0 AND @AutoCommit = 1 AND @TagAdded = 1
		EXEC dbo.aaCommitChanges
END
GO

/*
-- Automatically replicate tags each time one is added. This may slow the performance
-- of adding tags, particularly for bulk operations, such as deploying objects or
-- important a tag configuraton CSV file.

IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[dbo].[tI_TagAutoReplicate]'))
DROP TRIGGER [dbo].[tI_TagAutoReplicate]
GO

create trigger [dbo].[tI_TagAutoReplicate]
on [dbo].[Tag]
for insert
as
begin
	exec dbo.wwkbAddMissingReplicatedTags @AutoCommit=0
end
*/


-- As an alternative to the Trigger above, set up a SQL Agent job

-- Create a SQL Agent job to run the above SP and attach it to the hourly
-- schedule created for a standard "Runtime" database job.

USE msdb

-- Clean up
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'Add Missing Historian Replicated Tags')
BEGIN
	EXEC dbo.sp_delete_jobstep @job_name=N'Add Missing Historian Replicated Tags', @step_id=1
	EXEC dbo.sp_delete_job @job_name=N'Add Missing Historian Replicated Tags'
END

EXEC dbo.sp_add_job
    @job_name = N'Add Missing Historian Replicated Tags', 
    @enabled = 1,
    @description = N'Add Historian replication entities for newly created tags',
    @delete_level = 0;
GO

EXEC sp_add_jobstep
    @job_name = N'Add Missing Historian Replicated Tags',
    @step_name = N'Add Tags',
    @subsystem = N'TSQL',
    @database_name = N'Runtime',
    @command = N'EXEC Runtime.dbo.wwkbAddMissingReplicatedTags'
GO

DECLARE @Job AS uniqueidentifier
SET @Job = (SELECT TOP 1 job_id FROM msdb.dbo.sysjobsteps WHERE command='exec aaUserDetailUpdate')
DECLARE @Schedule AS INT
SET @Schedule = (SELECT TOP 1 schedule_id FROM msdb.dbo.sysjobschedules WHERE job_id=@Job)

EXEC sp_attach_schedule
   @job_name = N'Add Missing Historian Replicated Tags',
   @schedule_id = @Schedule;
GO
