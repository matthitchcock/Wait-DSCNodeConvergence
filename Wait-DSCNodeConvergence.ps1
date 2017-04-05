<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2017 v5.4.136
	 Created on:   	04-Apr-17 11:18 PM
	 Created by:   	matthew.hitchcock@microsoft.com
	 Organization: 	Microsoft
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

function Wait-DSCNodeConvergence
{
	[CmdletBinding()]
	[OutputType([array])]
	param
	(
		[string]$ComputerName,
		[PScredential]$Credential,
		[datetime]$DateTime = (Get-Date)
	)
	
	# 1. Build an Array of Sessions
	$NewSessionparam = @{
		ComputerName = $Computer
	}
	
	if ($Credential)
	{
		$NewSessionparam.Add("Credential", $Credential)
	}
		
	# 2. Loop through the sessions measure convergence
	
	[System.Array]$Output = @()
	foreach ($Computer in $ComputerName)
	{
		$DSCNode = New-Object -TypeName System.Management.Automation.PSCustomObject -Property [Ordered]@{
			ComputerName = $Computer
			ConvergeAfterTime = $DateTime
			StartTime = (Get-Date)
			CapturedEndTime = ""
			State = ""
			DurationMinutes = ""
			SessionInfo = (New-PSSession @NewSessionparam -ErrorAction SilentlyContinue)
		}
		
		$Output += $DSCNode
	}
	
	if (($Output.Where{
				$PSitem.SessionInfo.State -eq "Opened"
			}) -eq $Output.Count)
	{
		
		do
		{
			# Here is where we run the Invoke-Command to DSCConfigurationStatus and update the object
			Write-Verbose -Message "Waiting for for update ..."
			
			Start-Sleep -Seconds 60
			
			foreach ($DSCNode in $Output)
			{
				if (($DSCNode.Status -ne "Success") -and ($DSCNode.StartDate -lt $DateTime))
				{
					$StatusData = Invoke-Command -SessionName $DSCNode.SessionInfo -ScriptBlock {
						Get-DscConfigurationStatus
					} -ErrorAction SilentlyContinue # CONSIDER ERROR VARIABLE SO IF SERVER REBOOTED NEED TO REBUILD SESSION
					
					if ($StatusData)
					{
						# Update $DSCNode with $StatusData attributes
						# Compare the time to the ConvergedAfterTime, if later then update the data, if not then "Waiting"
						if ($StatusData.StartDate -lt $DateTime)
						{
							$DSCNode.Status = "Waiting for Run"
						}
						else
						{
							$DSCNode.Status = $StatusData.Status # Check property Names etc
						}
						
						
						if ($DSCNode.Status -eq "Success")
						{
							# Set the End time and average time, etc.
							$DSCNode.CapturedEndTime = Get-Date
							$DSCNode.DurationMinutes = ($DSCNode.CapturedEndTime - $DateTime).Minutes
						}
					}
					else
					{
						$DSCNode.State = "Not Reachable"
						# NOW NEED TO REBUILD THE SESSION
						
						do
						{
							$NewSessionparam.ComputerName = $DSCNode.ComputerName
							
							$RebuiltSession = New-PSSession @NewSessionparam -ErrorAction SilentlyContinue
						}
						until ($RebuiltSession)
						
						$DSCNode.SessionInfo = $RebuiltSession
						
					}
				}
			}
			
			Write-Host $Output
		}
		
		until (($Output.Where{
					$PSitem.State -eq "Success"
				}) -eq $Output.Count) # Update "Success" with real value
		
		
		# 3. Close all sessions
		foreach ($DSCNode in $Output)
		{
			Remove-PSSession -Session $DSCNode.SessionInfo
		}
		
		Write-Verbose -Message "Convergence is complete"
		return $output
		
	}
	else
	{
		Write-Verbose -Message "Could not Open all session - Convergence monioring stopped"	
	}
	
}
