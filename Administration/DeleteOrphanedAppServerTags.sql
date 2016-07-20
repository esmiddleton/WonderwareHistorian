/*

Delete Orphaned Tags
====================

!!! This script makes UNSUPPORTED modifications to your Runtime database !!!
!!!                       USE AT YOUR OWN RISK                           !!!

This SQL script extends the Historian "Runtime" database by adding one stored
procedure that makes it easy to delete "orphaned" tags from the Historian database.

	exec dbo.wwkbDeleteOrphanedTags @DeleteNow

	DeleteNow	Set to '1' to force the tag to actually be deleted. Omit or set to '0' to see
				a list of tags that would have been deleted.

Here's an example of how to invoke the SP:

	exec dbo.wwkbDeleteOrphanedTags

*/
USE [Runtime]
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[wwkbDeleteOrphanedTags]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[wwkbDeleteOrphanedTags]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE procedure [dbo].[wwkbDeleteOrphanedTags] (
	@DeleteNow bit = 0
) as
begin
	set nocount on
	declare @Tags table (TagName nvarchar(256))

	insert @Tags (TagName)
	select AttributeName from aaAttributeData where AttributeName not in (select TagName from Tag) 

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
		begin
			DELETE  FROM PublicNameSpace WHERE Name 
			IN (SELECT aaTagname FROM aaObjectData 
			WHERE aaTagName NOT IN (SELECT aaTagName FROM aaObjectDataPending)) 

			DELETE FROM aaObjectData WHERE ObjectKey NOT IN (SELECT distinct ObjectKey FROM aaAttributeData) AND 
			ObjectKey NOT IN (SELECT ParentKey from aaObjectData) 
			exec dbo.aaCommitChanges
		end
end

GO
