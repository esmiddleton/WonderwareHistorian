Wonderware Historian Tools
==========================

This is a collection of mostly SQL Server queries that work with Wonderware Historian to extract useful information. Most are packaged as stored procedure "CREATE" scripts and add UNSUPPORTED objects to your "Runtime" database. Except as may be noted in specific scripts, the additions do not alter existing database objects, only add new ones alongside the standard product ones. 

As a convention, database objects created by these scripts use the "wwkb" prefix in the name (Wonderware Knowledge Base), a holdover from when there was a set of utilities distributed on a "knowledge base" CD. 

Unsupported
-----------

The primary implications of being UNSUPPORTED are:

1. These scripts have had LIMITED testing and may not work completely as intended and may have unintended side effects.
1. They include NO WARRANTY OF ANY KIND. AVEVA Group plc assumes NO responsibility for these scripts or any unintended consequences of using them.
1. By using them, you assume FULL responsibility for the consequences.
1. The scripts/objects may fail to work following a product update (patch, service pack, major release) that makes changes to existing database objects.
1. The objects will not be automatically recreated in a new "Runtime" database.
1. Wonderware/AVEVA assumes no responsibility to answer questions or assist with the use of the scripts themselves (although, to the degree they leverage standard product features, those are of course supported).
