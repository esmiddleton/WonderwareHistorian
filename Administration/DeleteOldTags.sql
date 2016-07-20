/*

Delete Old Tags
===============

!!! This script makes UNSUPPORTED modifications to your Runtime database !!!
!!!                       USE AT YOUR OWN RISK                           !!!

This SQL script extends the Historian "Runtime" database by adding one stored
procedure that makes it easy to delete "stale" tags from the Historian database.

	exec dbo.wwkbDeleteOldTags @DaysOld, @LiveDaysOld, @DeleteNow

	DaysOld		Used to select tags that where created at least this many days ago--only older
				tags will be deleted.

	LiveDaysOld	The number of days old that the most recent value must be before the tag is
				deleted. NOTE: When the server starts up, it will store a NULL value with the
				current time of the server. This means that if no value was sent to the Historian
				for the tag in the last 90 days, but the server was started yesterday, the
				tag will still not be deleted.

	DeleteNow	Set to '1' to force the tag to actually be deleted. Omit or set to '0' to see
				a list of tags that would have been deleted.

Here's an example of how to invoke the SP:

	exec dbo.wwkbDeleteOldTags 90, 60, 1

*/
USE [Runtime]
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[wwkbDeleteOldTags]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[wwkbDeleteOldTags]
GO

/****** Object:  StoredProcedure [dbo].[wwkbDeleteOldTags]    Script Date: 1/9/2014 10:28:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE procedure [dbo].[wwkbDeleteOldTags] (
	@DaysOld int = 90,
	@LiveDaysOld int = @DaysOld,
	@DeleteNow bit = 0
) as
begin
	set nocount on
	declare @Tags table (TagName nvarchar(256))

	insert @Tags (TagName)
	select t.TagName 
		from Tag t
		inner remote join Live l on l.TagName = t.TagName
		where DateTime < dateadd(day, -@LiveDaysOld, getdate())
		and vValue is NULL
		and DateCreated < dateadd(day, -@DaysOld, getdate())
		and IOServerKey <> 1

	declare OldTags cursor fast_forward for
		select TagName from @Tags
	open OldTags

	declare @TagToDelete nvarchar(256)
	fetch OldTags into @TagToDelete

	while @@FETCH_STATUS=0
		begin
			if @DeleteNow=1 
				begin
					exec dbo.aaDeleteTag @TagName=@TagToDelete
					print 'Deleted "' + @TagToDelete + '"'
				end
			else
				print '"' + @TagToDelete + '" would be deleted.'
			fetch OldTags into @TagToDelete
		end

	close OldTags
	deallocate OldTags

	if @DeleteNow=1 
		exec dbo.aaCommitChanges
end

GO


