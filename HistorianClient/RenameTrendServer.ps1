#	This PowerShell script changes the name of a Historian server stored in "aaTrend" files.
#
#	It must be run from the 32-bit PowerShell command line:
#
#	In order to run Powershell scripts, you must first enable scripts--by default, they are disabled. You must
#	either: a) enable unrestricted script execution, or b) install a Root CA certificates and enable signed scripts.
#	To change script execution settings, launch Powershell with "Run as administrator" and type the following 
#	at the command line:
#
#		Set-ExecutionPolicy Unrestricted
#
#	Or
#
#		Set-ExecutionPolicy AllSigned
#
#	You can find more information about execution policy online at: http://technet.microsoft.com/en-us/library/ee176961.aspx
#
#	Usage:
#
#		powershell -sta RenameTrendServer.ps1 [-path <pathToSearchForCRVFiles>] -o <OldServerName> -n <NewServerName> [-d]
#
#	The optional "path" parameter will accept a specific aaTrend file name, or will search a path recursively for all aaTrend files.
#
# 	The optional "d" parameter will decrypt an older format "aaTrend" file into the plain text XML used by Historian Client 10.1 and later
#
#	This script is UNSUPPORTED and is released "as is" without warranty of any kind.
#
#	18-Nov-2013
#	E. Middleton

param (
	[string]$o = "",
	[string]$n = "",
	[string]$path = ".",
	[switch]$d
)
Write-Host("Rename Historian server using in Historian Client aaTrend Files")
		

# ==============================================
#		Main Function
# ==============================================

function RenameServer($path,$oldServer,$newServer,$decrypt) {

	# Load the trend as an XML document
	[System.Xml.XmlDocument]$doc = New-Object System.Xml.XmlDocument

	Write-Host("Finding all aaTrend files in '" + $path + "'")

	$serversNotReachble = @()
	
	# Loop through all aaTrend files in the specified path
	Get-ChildItem $path -Include "*.aaTrend" -Exclude "*-New.aaTrend" -Recurse | % {
		Write-Host("Loading '"+$_.FullName+"'...")

		$isDirty = $false
		$doc.Load($_.FullName) # Read the aaTrend file
		
		if ($doc.root.TagList.AAWRAPPED -ne $null) {
			[System.Xml.XmlElement]$wrappedList = $doc.SelectSingleNode("//root/tagList")
			
			# Use an internal class to read encrypted elements of an aaTrend file (Historian Client 10.1 and earlier)
			[System.Xml.XmlElement]$unwrapped = [ArchestrA.HistClient.Util.aaXmlTools]::UnwrapElement( $doc, $doc.DocumentElement, $wrappedList)
			Write-Host "   Converted to plain text"
			$isDirty = $decrypt
		}

		$tags = $doc.SelectNodes("//root/tagList/trendItems/trendItem")
		foreach ($tag in $tags) {
			 if ($tag.SERVER_NAME -ne $null) {
				if (!($serversNotReachble -contains $tag.SERVER_NAME) -and (!(Test-Connection -Cn $tag.SERVER_NAME -BufferSize 16 -Count 1 -ea 0 -quiet)) ) {
					Write-Host("   *** Server '"+$tag.SERVER_NAME+"' is not reachable.")
					$serversNotReachble += $tag.SERVER_NAME
				 }
			}

			if ( $tag.SERVER_NAME -eq $oldServer ) {
				Write-Host "  " $tag.SERVER_NAME "" $tag.TAG_NAME "changed to" $newServer
				$tag.SERVER_NAME = $newServer
				$isDirty = $true
			}
		}

		if ($isDirty) {
			Write-Host "   Saving file..."
			#$newName = $_.BaseName+"-New"+$_.Extension
			$doc.Save($_.FullName)
		} else {
			Write-Host "   Nothing to change."
		}
	}
}



if (!([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq "STA")) {
	Write-Host "*** This must run as a single-threaded script. Run this from within PowerShell with:"
	Write-Host "       powershell -STA <script>"
} else {
	if ([System.Runtime.InterOpServices.Marshal]::SizeOf([System.IntPtr]) -eq 8) {
		Write-Host "*** This must run as a 32-bit script. Restart from the x86 PowerShell application"
	} else {
		if (!( ([System.Reflection.Assembly]::LoadFrom("C:\Program Files (x86)\Common Files\ArchestrA\aaHistClientUtil.dll")) -or
			([System.Reflection.Assembly]::LoadFrom("C:\Program Files\Common Files\ArchestrA\aaHistClientUtil.dll")) )) {
			Write-Host "*** Unable to load the Historian Client assembly 'aaHistClientUtil.dll'"
		} else {
			RenameServer $path  $o $n $d
		}
	}
}

# SIG # Begin signature block
# MIIFRQYJKoZIhvcNAQcCoIIFNjCCBTICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUMBixkWajLV/WM9vGnB4IkpI/
# BB+gggLOMIICyjCCAjegAwIBAgIQJO71/NcyMrpDHsnquRF7ZjAJBgUrDgMCHQUA
# MCwxKjAoBgNVBAMTIUVNaWRkbGV0b24gTG9jYWwgQ2VydGlmaWNhdGUgUm9vdDAe
# Fw0xMzExMjIxNDUyNTZaFw0zOTEyMzEyMzU5NTlaMCcxJTAjBgNVBAMTHEVNaWRk
# bGV0b24gUG93ZXJzaGVsbCBTY3JpcHQwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
# ggEKAoIBAQC+g0J1dVh/EdS7ZnUda4PAXiguCBmRJimd7MP2zjWyyiPBLUOJ34/r
# Gnpcpsw0Tv/Jhdthy+QT+/GsC8IYYT4H1LZjBn34mWNYenVWEx4VhtF8AlMOgluu
# reyXwvgb7tOan9LMSq95GX1gB1bu8VIP46mkEseLwQkj3seFLBzul5EK6jh6dCDy
# UsRf7sU2Nahn49PTL7IJkXmKyRLL4FdxGrTyNQYMoNQfpz80+DfK6aizdgj+NoX+
# U/dNcyrL4RGHD6GW7xMrBANZImFB0zVJzZzWrbjce+GnR24sGRkGP97rb0s6bKL7
# Ew5ppeMIEoWAd6dqfB5mjVDfkJnmnW4BAgMBAAGjdjB0MBMGA1UdJQQMMAoGCCsG
# AQUFBwMDMF0GA1UdAQRWMFSAEGTCsuZs1jSf4kOvR/K1wnuhLjAsMSowKAYDVQQD
# EyFFTWlkZGxldG9uIExvY2FsIENlcnRpZmljYXRlIFJvb3SCEJRY54rmdPG1T5BQ
# dNMMsu4wCQYFKw4DAh0FAAOBgQAdHtqCsi9KVrHRj79N+oicSCHrbVR/8FkpqlgY
# +lChqtWei+WKquCzlsfY+1qwe172QiWbKv7355sw2qyL6s1iMo6pG/eNZMlWvAMV
# 1yxwhiwTuqMrApyIxtRP1VWTbldhbKgFUnzlA+w7eiJHfdYLgp5u0zg2lgGJ8ZlX
# 2cMuhDGCAeEwggHdAgEBMEAwLDEqMCgGA1UEAxMhRU1pZGRsZXRvbiBMb2NhbCBD
# ZXJ0aWZpY2F0ZSBSb290AhAk7vX81zIyukMeyeq5EXtmMAkGBSsOAwIaBQCgeDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEW
# BBTOwvUF2cWP/7cxdyjW5SNARCu5gTANBgkqhkiG9w0BAQEFAASCAQAOAVbr5kgI
# Jic+Gl1swZla7tMPR8TpEVpXJHmftKYlWcB3/o+f2qrBPrPQYd477amR3KZ1McL1
# x1LsLHYB1D1tWIAErCF0Sk6dFr5HnmG0o6xCRtKAYf9CUd6a/qpim7IX+WHVsOz0
# Mllpg25VjIlTcnPaSwLIZ28a2CQmHzK9gng/8yrUPxZ885W4RnJAwfaWm50f8u9o
# j+mtKRcS9iEIALpYzJnS50WifDccFMgqrg5X6aLXfNzVxwqWNeKPQK9FZwB0XM5F
# 31Cc8ndKxOJAkM24Fqv+sF1ezZYOUs4rkiMdU6oIIksAQCxtuLi6eXnV+Bz6rFpy
# RZuxWFTsABC3
# SIG # End signature block
