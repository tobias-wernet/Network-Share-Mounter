#################################################################
# Network Share Mounter											#
# Life Imaging Center, Albert-Ludwigs-Universität Freiburg		#
#																#
# Tobias Wernet													#
# 15.11.2023													#
# v 1.6.2.1										 				#		
#																#
# Changelog:													#
#	- Rename													#
#   - added About                                               #
#   - added switch for transient / persistence mapping			#
#	- Introducing groupshares.json								#
#   - Anpassung an PowerShell Pro Tools Compiler				#
#	- smaller improvements and clean-up 						#
#	- include RZ Home Drive in public domain					#
#	- changed authentication username notation					#
#	- updated GUI												#
#	- added cmdkey for credential manager storage				#
#	- switch to "net use" (from New-PSDrive) for pers. mapping 	#
#   - 															#
#	- Initial Script (adapted from Workstation Status Tool)		#
#																#		
#																#
#################################################################


# Tell  OS GUI/Tool is DPIAware (native API Call)
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class ProcessDPI {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetProcessDPIAware();      
}
'@
$null = [ProcessDPI]::SetProcessDPIAware()

# ErrorAction Definition
$ErrorActionPreference = "SilentlyContinue"

# UTF8 Encoding
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Add Windows Forms
Add-Type -AssemblyName System.Windows.Forms
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
[void] [System.Windows.Forms.Application]::EnableVisualStyles() 

# Various Variables
$version = "1.6.2.1"
$lastdate = "15.11.2023"
$tool = "Network Share Mounter"
$user = 'xUIDx'

# Check for JSON config file
If (-not(Test-Path .\groupshares.json))
{
	$Message = [System.Windows.Forms.MessageBox]::Show("groupshares.json required! $([System.Environment]::NewLine)The $tool requires a valid json config file with network share definitions. $([System.Environment]::NewLine)","$tool",0,[System.Windows.Forms.MessageBoxIcon]::Exclamation)
	BREAK
} else
{
	
}

# Importing Config from JSON Config File
# Please note, that backslashes require proper escaping in JSON files
try 
{
	$jsoninput = get-content .\groupshares.json | out-string | convertfrom-json -ErrorAction Stop
	$groupshares = $jsoninput.groupshares
	$validJson = $true
} catch
{
	$validJson = $false
}

if (-not ($validJson)) 
{
    $Message = [System.Windows.Forms.MessageBox]::Show("groupshares.json is not valid! $([System.Environment]::NewLine)The $tool requires a valid json config file to parse the network share definitions. $([System.Environment]::NewLine)","$tool",0,[System.Windows.Forms.MessageBoxIcon]::Exclamation)
	BREAK
} 

# Windows Authentication API Credential Function
function global:external_authentication
{
	param
	(
		[Parameter()]
		[string]$domain
	)
	# Get credentials to authenticate via external Domains and map external network shares
	# Credentials are temporarily stored in a secure PS credential object (and only valid in the owner's user session for the current runtime/session of the script/tool)

	# Prompt for Credentials and verify them by using the DirectoryServices.AccountManagement assembly.
	Add-Type -AssemblyName System.DirectoryServices.AccountManagement
	
	# Extract the current user's domain and also pre-format the user name.
	# Pre-Define the external Domainserver for authentication (if configured in the initial list of external shares)
	$script:UserDomain = $domain
	$UserName = $null
	
	# Define the starting number (always #1) and the desired maximum number of attempts, and the initial credential prompt message to use.
	$Attempt = 1
	$MaxAttempts = 3
	$CredentialPrompt = "Please provide your credentials for the selected domain $([System.Environment]::NewLine)$domain $([System.Environment]::NewLine)to continue. $([System.Environment]::NewLine) $([System.Environment]::NewLine)Please only enter your user name and NOT the domain.$([System.Environment]::NewLine)$([System.Environment]::NewLine)"
	
	# Set ValidAccount to false so it can be used to exit the loop when a valid account is found (and the value is changed to $true).
	$ValidAccount = $False

	# Loop through prompting for and validating credentials, until the credentials are confirmed, or the maximum number of attempts is reached.
	Do {
		# Blank any previous failure messages and then prompt for credentials with the custom message.
		$FailureMessage = $Null
		$Message = $Null
		$script:credx = Get-Credential -Username "" -Message $CredentialPrompt
		# Check for @ and \ as indication that a domain was provided and display an error if true.
		if (($($credx.UserName) -like "*\*") -or (($($credx.UserName)) -like "*@*"))
		{
			$Message = [System.Windows.Forms.MessageBox]::Show("Only usernames are allowed. Do not enter the corresponding domain $([System.Environment]::NewLine)$domain $([System.Environment]::NewLine)via @ or \ since it will be automatically populated.","$tool",0,[System.Windows.Forms.MessageBoxIcon]::Exclamation)
		}  
				
				# Only start verification if no domain was provided by the user
		If (-not($Message))
		{
			# Verify the credentials prompt wasn't bypassed.
			If ($credx) 
			{
				$UserName = $Domain+"\"+$credx.GetNetworkCredential().UserName
				$global:user = $credx.UserName
				# Test the user name and password (verification against defined domain controler).
				$ContextType = [System.DirectoryServices.AccountManagement.ContextType]::Domain
				Try 
				{
					$PrincipalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext $ContextType,$UserDomain
				} 
				Catch 
				{
					If ($_.Exception.InnerException -like "*The domain server could not be contacted*") 
					{
						$FailureMessage = "Could not contact a domain server for the specified domain $([System.Environment]::NewLine)$domain $([System.Environment]::NewLine)on attempt #$Attempt out of $MaxAttempts."
					} Else 
					{
						$FailureMessage = "Unpredicted failure: `"$($_.Exception.Message)`" on attempt #$Attempt out of $MaxAttempts."
					}
				}
				# If there wasn't a failure talking to the domain test the validation of the credentials, and if it fails record a failure message.
				If (-not($FailureMessage)) 
				{
					$ValidAccount = $PrincipalContext.ValidateCredentials($credx.GetNetworkCredential().UserName,$credx.GetNetworkCredential().Password)
					If (-not($ValidAccount)) 
					{
						$FailureMessage = "Authentication failed: Bad user name or password used on credential prompt attempt #$Attempt out of $MaxAttempts.$([System.Environment]::NewLine)$([System.Environment]::NewLine)Please provide credentials for the selected domain $([System.Environment]::NewLine)$domain $([System.Environment]::NewLine)to continue."
					}
				}
			# Otherwise the credential prompt was (most likely accidentally) bypassed so record a failure message.
			} Else 
			{
				Break
			}
		}
		# If there was a failure message recorded above, display it, and update credential prompt message.
		If ($FailureMessage) 
		{
			$Attempt++
			If ($Attempt -le $MaxAttempts) 
			{
				$CredentialPrompt = "Authentication error. $([System.Environment]::NewLine)Please provide your credentials for the selected domain $([System.Environment]::NewLine)$domain $([System.Environment]::NewLine)to continue.$([System.Environment]::NewLine)$([System.Environment]::NewLine)Please try again (attempt #$Attempt out of $MaxAttempts):"
			} 
		}
	} Until (($ValidAccount) -or ($Attempt -gt $MaxAttempts))
	if ($Attempt -gt $MaxAttempts)
	{
		# Break function if exceeded max. attempts.
		Break
	}
}

# Function for GUI buffer update
function SetDoubleBuffered()
{
    param([System.Windows.Forms.Control] $TargetControl)

    [System.Reflection.PropertyInfo] $DoubleBufferedProp = [System.Windows.Forms.Control].GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
    $DoubleBufferedProp.SetValue($TargetControl, $True, $Null)
}

# Function of the Drive OK button
function global:handler_click_drive_OK 
{
	$global:letter = $lettertemp
}

# Function of the Drive Cancel button
function global:handler_click_drive_CANCEL 
{
	$global:letter = $null
}

# Function of the remove share button
function global:handler_click_REMOVESHARE 
{
	param
	(
		[Parameter()]
		[string]$Para1
	)
	# String modification is required for the individual UNC paths of the RZ Home share
	$global:fullpath = $Para1
	$fullpath = $fullpath -replace 'xUIDx',$user
	$gshare = Get-PSdrive | where-object {$_.DisplayRoot -eq $fullpath}
	if ($gshare)
	{
		$drive = $gshare.Name+":\"
		$netdrive = $gshare.Name+":"
		$Result = [System.Windows.Forms.MessageBox]::Show("Do you want to disconnect the network share $fullpath on $drive ? $([System.Environment]::NewLine)You can re-connect it again any time.","$tool",4,[System.Windows.Forms.MessageBoxIcon]::Question)
		
		if($Result -eq "Yes")
		{
			Remove-PSDrive $gshare.Name -Force 2>$null
			net use "$netdrive" /delete /y 2>$null
			$objGroupShareButton.Enabled = $false
		}
	}
}

# Function for the map network share button
function global:handler_click_MAPSHARE 
{
	param
	(
		[Parameter()]
		[string]$Para1
	)
	# String modification is required for the individual UNC paths of the RZ Home share
	$global:fullpath = $Para1
	$fullpath = $fullpath -replace 'xUIDx',$user
	$gshare = Get-PSdrive | where-object {$_.DisplayRoot -eq $fullpath}
	if ($gshare)
	{
		$drive = $gshare.Name+":\"
		[System.Windows.Forms.MessageBox]::Show("Network share already connected. $([System.Environment]::NewLine)A network share mapping to $fullpath is already mapped to drive $drive.$([System.Environment]::NewLine)Opening $drive in Windows Explorer.","$tool",0,[System.Windows.Forms.MessageBoxIcon]::Information)
		& explorer.exe $drive
	} else
	{
		# Set variable for info text wording depending on mapping choice
		if ($objPersistanceCheck.Checked -eq $true)
		{
			$maptype = "persistent"
		} 
		if ($objTempCheck.Checked -eq $true)
		{
			$maptype = "temporary"
		}

		$Result = [System.Windows.Forms.MessageBox]::Show("Network share not found on the local system. $([System.Environment]::NewLine)A network share mapping to $fullpath is not present for your user account on the current system. $([System.Environment]::NewLine)Would you like to set-up a $maptype mapping to the selected network share?","$tool",4,[System.Windows.Forms.MessageBoxIcon]::Question)
		if($Result -eq "Yes")
		{
			$domain = ($groupshares | where-object {$_.group -eq $objGroupDriveList.SelectedItem}).domain
			external_authentication ($domain)
			$global:fullpath = $Para1
			$fullpath = $fullpath -replace 'xUIDx',$user
						
			if ($credx)
			{
				# Populate list of drive letters and eliminate letters already in use	
				$AllLetters = 65..90 | ForEach-Object {[char]$_ }
				$letters = (get-psdrive).name 
				$freeletters = $allletters | where {$letters -notcontains "$($_)"}
				
				## GUI selection for drive letter for network share
				#This creates the drive letter form 
				$driveForm = New-Object System.Windows.Forms.Form 
				$driveForm.Text = "$tool"
				$driveForm.Size = New-Object System.Drawing.Size(400,400) 
				$driveForm.Autosize = $true
				$driveForm.StartPosition = "CenterScreen"
				$driveForm.Icon = [System.Drawing.Icon]::FromHandle(([System.Drawing.Bitmap]::new($iconstream).GetHIcon()))
				$driveForm.FormBorderStyle = 'Fixed3D'
				$driveForm.MaximizeBox = $false
				$driveForm.KeyPreview = $True
				$driveForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") 
				{$driveForm.Close()}})
				$driveForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
				{$driveForm.Close()}})
				
				$objpictureBoxUFR = New-Object Windows.Forms.PictureBox
				$objpictureBoxUFR.Location = New-Object System.Drawing.Size(30,10)
				$objpictureBoxUFR.Size = New-Object System.Drawing.Size(320,36)
				$objpictureBoxUFR.Autosize = $true
				$objpictureBoxUFR.Image = $imgUFR
				$driveForm.controls.add($objpictureBoxUFR)
				
				#This creates a header 
				$objGroupShareLabel = New-Object System.Windows.Forms.Label
				$objGroupShareLabel.Location = New-Object System.Drawing.Size(30,60) 
				$objGroupShareLabel.Size = New-Object System.Drawing.Size(150,400)
				$objGroupShareLabel.Font = New-Object System.Drawing.Font("Arial",12,[System.Drawing.FontStyle]::Bold)			
				$objGroupShareLabel.Text = "$tool"
				$objGroupShareLabel.Autosize = $true
				$driveForm.Controls.Add($objGroupShareLabel)	
		
				#This creates a label for the Header
				$driveFormLabel = New-Object System.Windows.Forms.Label
				$driveFormLabel.Location = New-Object System.Drawing.Size(30,125) 
				$driveFormLabel.Size = New-Object System.Drawing.Size(350,30) 
				$driveFormLabel.Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Bold)
				$driveFormLabel.Text = "Select drive letter for:"
				$driveFormLabel.Autosize = $true
				$driveForm.Controls.Add($driveFormLabel)
				
				#This creates a label for the share name
				$driveFormLabel1 = New-Object System.Windows.Forms.Label
				$driveFormLabel1.Location = New-Object System.Drawing.Size(30,155) 
				$driveFormLabel1.Size = New-Object System.Drawing.Size(350,40) 
				$driveFormLabel1.Font = New-Object System.Drawing.Font("Arial",8)
				$driveFormLabel1.Text = "$groupshare_sel"
				$driveFormLabel1.Autosize = $true
				$driveForm.Controls.Add($driveFormLabel1)

				#This creates a label for the drop-down Header
				$driveFormLabel2 = New-Object System.Windows.Forms.Label
				$driveFormLabel2.Location = New-Object System.Drawing.Size(30,200) 
				$driveFormLabel2.Size = New-Object System.Drawing.Size(350,30) 
				$driveFormLabel2.Autosize = $true
				$driveFormLabel2.Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Bold)
				$driveFormLabel2.Text = "Available drive letters:" 
				$driveForm.Controls.Add($driveFormLabel2)
		
				# This creates the drive list drop-down menu
				$driveFormDriveList = New-Object System.Windows.Forms.ComboBox
				$driveFormDriveList.Location = New-Object System.Drawing.Size(30,230) 
				$driveFormDriveList.Text = "Drive letter"
				$driveFormDriveList.Width = 250
				$driveFormDriveList.Autosize = $true
				
				# Populate the drop-down list with free drive letters
				$freeletters | ForEach-Object {[void] $driveFormDriveList.Items.Add($_)}
				$driveFormDriveList.add_SelectedIndexChanged({
					$global:lettertemp = $driveFormDriveList.SelectedItem
				})
				$driveForm.Controls.Add($driveFormDriveList)
					
				#This creates the OK button and sets the event
				$OKButtond = New-Object System.Windows.Forms.Button
				$OKButtond.Location = New-Object System.Drawing.Size(30,280)
				$OKButtond.Size = New-Object System.Drawing.Size(75,30)
				$OKButtond.Text = "OK"
				$OKButtond.Autosize = $true
				$OKButtond.Add_Click({handler_click_drive_OK; $driveForm.Close()})
				$driveForm.Controls.Add($OKButtond)
					
				#This creates the Cancel button and sets the event
				$CancelButtond = New-Object System.Windows.Forms.Button
				$CancelButtond.Location = New-Object System.Drawing.Size(110,280)
				$CancelButtond.Size = New-Object System.Drawing.Size(75,30)
				$CancelButtond.Text = "Cancel"
				$CancelButtond.Autosize = $true
				$CancelButtond.Add_Click({handler_click_drive_CANCEL; $driveForm.Close()})
				$driveForm.Controls.Add($CancelButtond)
								
				SetDoubleBuffered $driveForm
				[void] $driveForm.ShowDialog()
				
				if ($letter)
				{
					# various variables and string modifications
					$dletter = $letter+":"
					$user = $credx.GetNetworkCredential().UserName
					$domain = $UserDomain
					$userstring = $user+"@"+$domain
					$fullpath = $Para1
					$pos = $fullpath.IndexOf("\")      
					$servertemp = $fullpath.Substring($pos+2)
					$pos = $servertemp.IndexOf("\")
					$server = $servertemp.Substring(0, $pos)
					$fullpath = $fullpath -replace 'xUIDx',$user
					

                    if ($objPersistanceCheck.Checked -eq $true)
                    {
                        # Calling cmdkey to write credentials to Windows Credential Store
                        & cmdkey /add:$server /user:$userstring /pass $credx.GetNetworkCredential().Password
                        # Calling net use to set persistent mapping
                        start-sleep -milliseconds 500
                        & net use  $dletter $fullpath /savecred /persistent:Yes
                        start-sleep -milliseconds 500
                        # Calling cmdkey again to overwrite credentials of net use in Windows Credential Store
                        & cmdkey /add:$server /user:$userstring /pass $credx.GetNetworkCredential().Password
                        
                        # Open mapped network drive by drive letter and call explorer.exe
                        $drive = (get-psdrive | where-object {$_.DisplayRoot -eq $fullpath}).Name+":\"
                        $objGroupShareButton.Enabled = $true
                        & explorer.exe $drive
                    } 
                    if ($objTempCheck.Checked -eq $true)
                    {
                        # Calling net use to set transient mapping
                        & net use  /persistent:No $dletter $fullpath /user:$userstring $credx.GetNetworkCredential().Password
                        
                        # Open mapped network drive by drive letter and call explorer.exe
                        $drive = (get-psdrive | where-object {$_.DisplayRoot -eq $fullpath}).Name+":\"
                        $objGroupShareButton.Enabled = $true
                        & explorer.exe $drive
                    }
				}
			}
		}
	}
}

# Function for About Menu Entry
function global:About 
{
			#This creates the About window 
			$aboutForm = New-Object System.Windows.Forms.Form 
			$aboutform.Text = "$tool"
			$aboutform.Size = New-Object System.Drawing.Size(500,460) 
			$aboutform.Autosize = $true
			$aboutform.StartPosition = "CenterScreen"
			$aboutform.Icon = [System.Drawing.Icon]::FromHandle(([System.Drawing.Bitmap]::new($iconstream).GetHIcon()))
			$aboutform.FormBorderStyle = 'Fixed3D'
			$aboutform.MaximizeBox = $false
			$aboutform.KeyPreview = $True
			$aboutform.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
			{$aboutform.Close()}})
			
			#This creates a label for the About Header
			$aboutformLabel = New-Object System.Windows.Forms.Label
			$aboutformLabel.Location = New-Object System.Drawing.Size(10,10) 
			$aboutformLabel.Size = New-Object System.Drawing.Size(450,30) 
			$aboutformLabel.Font = New-Object System.Drawing.Font("Arial",12,[System.Drawing.FontStyle]::Bold)
			$aboutformLabel.Text = "$tool"
			$aboutformLabel.Autosize = $true
			$aboutform.Controls.Add($aboutformLabel) 
			
			#This creates a label for the About version Text
			$aboutformLabel = New-Object System.Windows.Forms.Label
			$aboutformLabel.Location = New-Object System.Drawing.Size(10,50) 
			$aboutformLabel.Size = New-Object System.Drawing.Size(150,40) 
			$aboutformLabel.Autosize = $true	
			$aboutformLabel.Font = New-Object System.Drawing.Font("Arial",10)
			$aboutformLabel.Text = "Version $version ($lastdate)"
			$aboutform.Controls.Add($aboutformLabel) 

            #This creates the info text
			$aboutformLabel = New-Object System.Windows.Forms.Label
			$aboutformLabel.Location = New-Object System.Drawing.Size(10,100) 
			$aboutformLabel.Size = New-Object System.Drawing.Size(450,100) 
			$aboutformLabel.Autosize = $true	
			$aboutformLabel.Font = New-Object System.Drawing.Font("Arial",8)
			$aboutformLabel.Text = "This software is provided `"as is`" without any warranty. `r`nThere is no official support. `r`nHowever, we are happy to receive feedback and will consider `r`nimplementing features or bug fixes on request."
			$aboutform.Controls.Add($aboutformLabel) 
	
			#This creates a label for the Copyright text
			$aboutformLabel = New-Object System.Windows.Forms.Label
			$aboutformLabel.Location = New-Object System.Drawing.Size(10,200) 
			$aboutformLabel.Size = New-Object System.Drawing.Size(450,150) 
			$aboutformLabel.Font = New-Object System.Drawing.Font("Arial",8)
			$aboutformLabel.Text = "Copyright © 2023 - Alle Rechte vorbehalten. `r`n`r`nTobias Wernet `r`nUniversity of Freiburg `r`nSignaling Campus Freiburg `r`nLife Imaging Center `r`nHabsburgerstr. 49 `r`n79104 Freiburg im Breisgau"
			$aboutform.Controls.Add($aboutformLabel) 
			
			#This creates a label for Contact E-Mail
			$aboutformLink = New-Object System.Windows.Forms.LinkLabel
			$aboutformLink.Location = New-Object System.Drawing.Size(10,360) 
			$aboutformLink.Size = New-Object System.Drawing.Size(300,40)
			$aboutformLink.Autosize = $true			
			$aboutformLink.Font = New-Object System.Drawing.Font("Arial",8)
			$aboutformLink.Text = "tobias.wernet@biologie.uni-freiburg.de"
			$aboutformLink.LinkColor ="blue"
			$aboutformLink.add_Click({[system.Diagnostics.Process]::start("mailto:tobias.wernet@biologie.uni-freiburg.de")})
			$aboutform.Controls.Add($aboutformLink) 
	
			#This creates the OK button and sets the Close event
			$OKButtona = New-Object System.Windows.Forms.Button
			$OKButtona.Location = New-Object System.Drawing.Size(10,415)
			$OKButtona.Size = New-Object System.Drawing.Size(75,30)
			$OKButtona.Text = "OK"
			$OKButtona.Autosize = $true
			$OKButtona.Add_Click({handler_click_drive_OK; $aboutform.Close()})
			$aboutform.Controls.Add($OKButtona)
			
            #This creates the picture box for the UFR logo
			$objpictureBoxUFRa = New-Object Windows.Forms.PictureBox
			$objpictureBoxUFRa.Location = New-Object System.Drawing.Size(150,410)
			$objpictureBoxUFRa.Size = New-Object System.Drawing.Size(240,50)
			$objpictureBoxUFRa.Autosize = $true
			$objpictureBoxUFRa.Image = $imgUFR
			$aboutform.controls.add($objpictureBoxUFRa)
			
			SetDoubleBuffered $aboutform
			[void] $aboutform.ShowDialog()
}


function global:Workstation_GUI 
{
	#This creates the main GUI form and sets its size and position
	$global:objForm = New-Object System.Windows.Forms.Form 
	$objForm.Text = "$tool"
	$objForm.Size = New-Object System.Drawing.Size(400,520) 
	$objForm.AutoSize = $false
	$objForm.FormBorderStyle = 'Fixed3D'
	$objForm.MaximizeBox = $false
	$objForm.StartPosition = "CenterScreen"

	$objForm.KeyPreview = $True
	$objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") 
		{handler_click_OK; $objForm.Close()}})

	$objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
		{handler_click_Cancel; $objForm.Close()}})
		
	# This creates and bas64 encodes the UFR Icon
	$iconBase64 = 'iVBORw0KGgoAAAANSUhEUgAAALQAAAC0CAMAAAAKE/YAAAAACXBIWXMAAAsSAAALEgHS3X78AAAAY1BMVEX///82S5s2S5s2S5s2S5s2S5s2S5s2S5s2S5s2S5s2S5s2S5s2S5s2S5s2S5s2S5s2S5tPXqNib6pzfbGCi7iQl7+co8Worsy0uNK+wtjJzN7T1eTc3url5+/u7/X39/r////3z4JCAAAAEHRSTlMAECAwQFBgcICQoLDA0ODwVOCoyAAABLdJREFUeNrtndmWojAQhmVRwiaFuIQWhfd/yrmARphBLTTbf878l9pNf51TVUkqpGqzUSg/jESaZTRTlqUiCv2NgwpFktNL5UkUusPrbeM3vBPyeOvZJw4EG3gEF4FV4nhPH2kfW+L2xYfEA7cw75u7jL5WtjPqet8N8nS4TbmlHxekTEVswkr8hBQr8bUbBmmQXiOJCtKiItI3Ve9Jm/Z6pngvJa1KPRzL0GgjXkYGlCkd7G1BRlRs1Q1zTMYUKxpsPyeDyn0k01BpIhEZ19dRJCELSgAindrY5+VkSbmHETbUUAcFWVQR4DF/Ru1ZZiYqPBwf/NyuXWBeTZ2RE8qcnwe/nBsjckbsdciWHBJzzecXLkEXPk7gWBlCYnJMMZhBM83aK9yDfjufZ+SgMpgIzY7WLhrHWwNJyVGlL3K55KyeZ4L37kLvwbzwpS+66oUvfVGQ0xKLiztyXL7Lu5UVuxjnB3ppqGP3oWOs0PEkgAgCkDA9GVaXumma5keeSlXT4k4vcSnv3UPHj5+zM7j2P7VdpwQ6Mxfvzl2nCHoW9bS64alTBy0MuWHZKoSeuGKgc6AvnUJoCszMhjel0LER6zg8YNtLRUTlsSQF9hGYccN7qeJ5gYnYIUfok9KpPDcDreZ5+bDAIyPQjaIHegbypMqhtwaW/8qhY/0mrR66N2pyBLq6/DRNI98+kZfAO8tB56ffSCI6yCU1Y5gePzpMf/N3ejwPM+d76JAVpZung9VM49mxY+o4/c0eshon+wsrQZY4AH1uVyxMEpYfaoee7hIqlieSdehq+iXDt1k7Lc3Q5XTT27L2XKF16Hr6HSeah5xMOhO6apY0DmM7flTNoA+zf+jKgI4461Im9KrJ5QH9M4OWDGjBOdDSCv3LfK9PFXOSTTlpGq3QfYS+rdk3Ztah2UYxhSYHoM8rF2EuQF8ID3r9QtsB6CMg9J0AoSUi9BERmgChb4jQzX9ozh+4I0J3gNBHO9DFV0vT2g70uvX031vl1hb0mu1Wd5hn8jo70Omqje185Ts71TQJLTgphHr5gOrWWYKOOMmaiRn8PMZ5vsszCR1y0mLTdMp1GOs+z9lagfZZBwH3WQ5ISnntadvaCjTvyOXyJCknpQ3onPcS4b9vPwyrSivQCfOQeXGo28oOdMR90/u6yGwHOuQeyZW3JWY70CsOP+s5cx/6bEDna46Zq0ki+Tpsoc9jovz5zPT7E/V8DJY/Zihed6BfnmTdNPU37zAq0NbAqxPK5Rl4SUW1cqQ3eh/rUgMvXqlWAHAp52/tkV6tnwc8MPsIIC5tPbMOoPghsC65jDstx6/WLqVpDF5kUKUdzP3JZTeEvZwDeQ0K8sIZ5tU+yEuUmNdVIS8GY17BhrzsjllWALOAA2SpDMyiJJDlXzAL7WCWNIIsHoVZpguzIBpk6TnMIn+Y5RQxC1dilgjFLMYKWfYWs8AwZilnzKLZdu3686LqiIXgMUvuYzY3AG0jgdmwA7M1CmYTGsx2P6CNlTBbWIE2C8NsywbaAE9Xq8FCez9KwKaOmw1k+8zeSOAalfZvtcC1hO2tBK/5br/1hWtzPHDDNZQe3BKudfc4xUdYTdInvmmoHf0fx2XHQvaPImAAAAAASUVORK5CYII='
	$iconBytes = [Convert]::FromBase64String($iconBase64)
	# initialize a Memory stream holding the icon
	$iconstream = [System.IO.MemoryStream]::new($iconBytes, 0, $iconBytes.Length)
	
	# This creates and bas64 encodes the UFR Logo
	$logoBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAUAAAAAkCAYAAAD4guNSAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAN9JJREFUGBntwQe8Z3dd5//X+/s951dumTt3ZjJJIIWQBAIYUcAGCBKaiqLYcEGRXRFUWJFlxbbq2lZ0bYtgoagoKIKICqjUIB0pEQKE9Dopk5m5M7f8yjnn+3n/7525k9wJE0LyJ7s8Hub51MOe9HKOmrYTTj/hflS5ZkNE4caD1xBRkMRRZishMhtEQZgAAhDrDF034QFnPpyoxaUXf5jt8yeyvHaAE0+6L8vtQcZL+xFghJI4HptZmWdGih1Vqt7UK71Pt6lFiKOEaKOjRizWQ4qDDQmx6paxCwmxVek6EAgREQQtG4yZH+5kbbSEc8VAFQhaRCpBIeilTG0Y90QKkyzG3YjTzvoq7r/tXD560ds4uLKXuupzDAMCJZjdMcNoKnbNV6htueyqJebm+/RTopczETDugtYtu+dP4uDKXpjtQ1soa2PSsE/d77P3hgN848Pvw+MefgYljG22GvQrXvPGT9eXX7v0zJlBPt3mrVnpQ0IcFQ7MJhswt5A4yhH0ZodUgz6O4BY205XRfSLiB0hplK1XD3uD/Z0LTWmwPZR5ptFJSvrHJD4uia26rvB5bI6ROC5bgNmq6absXjiF0094AE034aicaj5zzQdoSzvTq/pPCPvxEqc4LKwl5fRBiT8HpmyyzYa66lPnHuMY0ayuMNOfRzKjmHLllcv81I89nJ973iPZ8PFP38QTnv7XnHP6PMG6gE6QbboI6pzpKTOuQU1hPtdI4rYEdA4OTqePI3He3HD4731Vry8ETdcxbVok7bTjiUDFEZb4EHAZxyMQCRNkEm3p2Dazk239Ga5Zuoo699hgwDZHSUIStzDYZitjtrJEUuLkmXn6ueLm0QoHx2PqnNlgQClRpUTpWkIipUTu1TRrY3KVuZUIBzjIEpoZoJTpltdQzjTdiF6eYWY4x3iyAggrEAmnhHqZGE+giIovK+YIcQwxh3mNg+/AJkp5buTyeKELQRwlhBD/EdkgicWFAV0x4WCrmUFN23V/2E7aZ7mXsPxCSOcJPsQ6c+dIIuWM2SThiFNKKe8AnUUEgZ4i5SeJWAYy5pVhP802BM/PveoxEheY/1d0FvbLI+IxNtiGJIRxxHdbvA24iluISbvG/GCRc+79MD45/ijjtYNgQHxJJERKidsSoinxgxZ/URnW1ka0vd5Z/dz7DQrGZt2ZwGvZynoucBlbSImUIChg/kOr+DIiEg4D5hjikQTfwTqRKPaJjZsfzin/pM0tDBQXKmX+o8lZNE3HX//DZ7AhJUgS5ogqp684cHD0n4fDCrHOGgR+fuAPsU4Ic4s54HHAPFCAAN4J7GOdlGinU6btBMxWPyJ0FuIw40eutavfCrzO5mttP411Ethe6Lr48ZT0IzZfyJnAI4AxMARuBN4BmC+KSUokZTYIYUxOecH2G+z4KtZJgAQYEIYGMFtIIkrHtFkjokCYLymJtWhoxy23JUNk/UyVEocJmrZ9UVXql4RZRWxogQkw4FZrbGGbnDJZUNwh/mOr+DJhoMqZ3KsZr45JSdzCrIJBHCYE1t5wwQYbJMBQXJAy/9HkLKbTwgUX3sj2+T437VsjJ1FVCRtsTxYWeiu9Xt5ug20QN0scZgw2m84yfjWwjU2CbwPeyjpJdG3LfG+OKlWEAyHCsX+ZVRIJY4QYerhU3DFlPBZpYhiwzjaYmylCHJGUKBhjtvhWw0u41edkPRho2MIcX5377F+9kUF/nvnhIl2ZUuWaG5aufGbTTr+qyj2OMoSULgA7JcZAxwYBBgxCSIm7gzGtTDfXQwgwtxLqyn61hgQqgZyWVCkUgLk9ZpMkbGOMuceGxJeZqleR6gorQc6QM+TqA1L6XeFxsclJ7+1X+dUgkhIuZjotCCHEf0Q2SDDoZx75tafx7Y+7HzmJmUHNwnyf7fODy3Kqft1m2RhJn81ZL8tZpCTEMVogOFbDJmMkkVOPYTVHP8/Sz7P08+xfJqV/MmZdI+mPeuq/Q0qY9O+BXgyshgvK6eOnLp7y8vuecAan7zyNs088i5MWTsQ2ttkiOFYGzBbG3J6kRNs1LI/203QjSjSEWw6N9j0WgpwyG4SW69z7PqFHAI/MSd9SV+nGKieqJBJCNncvQTFVB72ZAfWgT28woDcY0Bv0qWeHv+RSrqMYct7Xm+n9rPrdiLqAuUNdCUjiHreq+DLiMCmLmfkhaytjbFASBlcpvxD7rcXsSlX+51JiZdoVdi4OaRoxPTTlHmCbyaTlEV9zGpNpx8cvvIENSiIp/Xal6v1NtGelXL0Fx0HbRBjbSGJTAcbAdm7VsckYJA5NlwibYR7SuSBY6uf+t49j7Sm1emsV+V/GXmPsCcmZlPllW+9WxGm9fv2mYW84qlWjSqw1a+w5uIfiQkqJLVqONQHMJmO+EGN6VZ/ltX203RoiAc5t1y7WVR9jsCGnP7H8RgnCbJiyLsJEMRukxN3PuCmoKTiDxS1Slc5P8I0ufmTvpMVPVl13odcmlGK+EAlKCQ6ttizM96gy99hU8f+QJG4rwuQsZucHjJfHuCtIogiw3y0gIphOO7pSGA4qptOOe9zKwGja8dVfcTIXX7mf0bgjJREUWseHLX84Sof6FWA86SCBMRuECp8vjDlKCAPLzRL0YJiHFBcqVTFfL7xxrazRI9PSIAsbejnTdt37pEROFfvW9qKqAosDh/bRRkudaoLAGCHWmc9XjLkzUsqMmwmlFDA556rKyhhjoBJ7qhw0YZApDqIkHAYB5otigySOykncWRbUFiowbhqOKoBzugq4qiyvYZtoC1FAEscjoGkLiwsDmmLC5h63qjiGkRJKmQ2y+VIQYqukxLp+RJnBNjACGjZFmJwzWdCVgpJwYp0QEDbG5JzoSshgiVsISEBwRALEF6dESeBQSgixlSADO4BTgAGwH7gOaQTmrrIh54QiJWA3cAqwF3QNmKOSEpvmgFOA7cAUuNZmqapSkThMwGjcEmGOsk0QCGEXlCtQ4jjGQlNjNgh1wJTbkASIlWaZtmpoS8MwD5nrzbI6XqE4tknpRCiLQGv7Juz9SnnaNoUDZR/VzAxt0xJdS13VGHOUMUIHONbI2NwFSYlcZ0CNwyvGHCaxbtR2hTAICLPOJO6YAHHYCcBpwDJwKeumTWErgYAF4HRgDjgIXIO0whYWVAamHba5RSU2lPGUgkCgJLC4LQHjpuWkHds58/RFbv7EVTghYB7YDkyBJaDhFiIchIO7g8JIBvPFqIGTgZOAK4B9HF8f+0TgRCCAG4T2SanheOynY37U+HUV8EvALmAq5WHXTd+Gyz+yLiI4jm8CvhcYAQNgCfF/gP2YDduB/wYsAp2kXtNNX9d20/cNhgvYPmvaTf4LSY+/ed/V9wZZSldFiX9RpVcqpRskSClhCSSQTgR+EpgHpoLZrsRrI/y++WF/x3jU/WLbBjMDpphtARe14g+KCQQhaKbBpOvIEhts6NX5TODHAWFb0vaZ3uxv2+WiaTclHGwQLNr+zrCfavurA7YJUhel66Q9dD4f6S+U9AG2aNsJdrDpm4GnAGNgAFzt8EuAtapXMRo1T1bT/vCglx/uiPlO6Tcj4pdkITaIpky/09J3xnj6cJlTVFfZJaIdT5aqKl2wsjJ9Y1f8+pS0yuebBV4gdCIwBs0RfivyW4EHAT8KFGDZ+GRgF5uMM/B84FuAGaAPTIHfFGlfYJrSUNxRXAaTbvIkWd/VlO4bkHYDFQq3XaxhrpR5Z4nuryrlC6tUoUq02Riz7mnAI4FVoDV+CMe6L/DbQAEqYBb4KPAq4EzguYCAwnHYbsE94AFsElAinlbsU5I0BIaCEfBbwH7g64FnAhNgYLy3ov69RF6yIPAjsJ8n6zEnnzi3/cMfv/Yvf/G33/MjVRKrk2A4qFg3sP29Rt/liIcV2CUpdSVKSb5eJb/X8BqJd7PJgAVIbHoq5lHAWCn1gZuA3wIajqPYVCn3Tz9pB3PDHiXK07Kr7y7RPaQEC0adki+x/beSXgfcaAe93KOXe9hGEuueCjwGWAVmgc8CLwOC47sP8BNADXRAD/Mq5E+UXqZUGTf6QexHASvAHPBh7D/lVk93xLPayfShShpgnm75DRJkiejY8ABL3+fx9EmG+1v07SCpGiFd1LaTNwv9taSrJ11QVUJd+d0ynb6AlFDiogrzQmCedSnVrK7e5Iz+0YABO0DC3OIbMD/OJonVlHkNsD8K2CwaXoiZEWLSjRjObL/hpBPOet+1+z739La0v7syWtpd5QqHwYKkexE8vJTyg91k+vQS/miECQdkMJyMeQHQZ1NSusqK95U2GgUPS0kPd0AOmCpiKbUfQPExEMVm27aanfWAYrMhSaysTn98ddz+t0Sii45e1V86deGUn5+b2cnley9h3IwBfR32H3aOhwQmSRxmY+gZzmZaznaVn238+8DPAhPb7NpxKpMb17ADSY81PJt1FhC+ajhbvzQl8Lj59b37l3+uRLBt24CmLayuTa6fHfYY5AFFsU32HxxYufkZVZVRgS5awokoMBjkk4eD+uTLrjzwrWtr7TPrOv/oju3DzzZNh2QgAM1ing/sYp0tiLIm8VbMOZjncfuE+X4+358C+4RISkC+36RM/nCtGz02ISQwxmGSEmEGgp2O8jDM86n0MxIvmXSQqwxRWPdtmP/E7TsB80KOdbbEq4DTbV7AXRDhb0rSN2HWCbHBr5TYD3xNmOeAKRT67h9YTquvnlTTpTrqn5y6/V0CJSV2Lfa48OKbbvjHt3+OM05f5Jsfcw4ppwcb/3aJeFwYksRRFjh8JuPmTOX0n4G/BJ4HLLOuqiu6rrDpydhPY5Ok/cDvAw3HUcLMz/av76IMPnfF3lf2e/npQhhjjBARcYLNI0qK5xo/vYv233YMd3JwtMS+tX0MqgHGT8L8IJtsPo70x0BwmLmN0zEvYKuIT4A+MV3oU4Y9SrP2PVqOJxsDwlFOU0p/inJt8xfI3x9hjMnKJKWlQsEhyGx4kc0vluJZMGBkYQe5qvttmT582o4e3qv6L4gSP7Nrcfhno1F5wrhtXpBSonSF/szgjARczS1MUt6XUialTEqZ41jhWMvAlFuNgevZIBBipj/3gRv2XvLwa675zGuqqr9bVERA0xrlxAZVIqKcPVkd//PaobUz9+09yHg0BcS6NeBmNtlmZlitzM/0uWzP/pXVZvo78zN9SjHkBBHJbfvolIwodF3LibtmeNDZu7jfGYvc7z6LPPCsnXVXyhO6zmyQMinl37h++fobG8H8zE7C5QmB3yXrIQiSxFGSwgbbqErYQTdtfjLCr1ZOGHPavR5IrzfEGKS9bCG4HqWVtUOTH50cXP653qBidm7AaNwiifucunj5tOvYv7o2gHiN7Gf0csXBQxNG047hYOZzw0HvA9vme1eULnAEM8OanTsG3/j+f7vm3X/1958++wMfu462DZLEugZY5liH2CAFd01wmFj3INvvDsdjM0ISBpLSgSpXn1LSxRIgDpMYro6a/7O2Mv7pRz/sJHYu9Jg2HeDCnVc4wtxVErfRAgYBOsBhBkOV+3vbdvma0f59TxX59xIoSRgzbQsnbJ+/6rRTF9ixc8DcsPqq5O7dxX4ciCSxRbDOGOUEgtL5B8GvtzSfJPp1jW023cSxrgFabked0tqkaa/7t4uu/PnLrt3/9JwSVZXYIIRtQEiiOM6y/Xal9HVddOyc3cVMPUMXHdgrHGsZaLl9K8Ayx9rPOoVRMQSrbCrRUeX62vn5RcLxx8Xx/RgkkZQw3t+52+MQQtjxa7Z/E2lWYp0xrKrKH029fJEdJCXq3COI3YdWJ396wuLM4+9z74Wva9oOy+ScP1RK+WAFZI6V+MLEFyYgsc42g3rmwGiyvPDZy6954aCepd8bTFLiExE+ODOs77c6npyVlMhknBJJ7Kzr/HMD1z+MwAYJAYktIixs+lWNzfltdJemlM4Wwgqi9ZNT5JcaT91A6URn0xWQYNr50auj9gERIAlH1zVl+veL8ydx0o77cvPSnnPWJgdfMzfYPssGG6Qrc0ovcxf/Gr1q3JvpnRGHxj/URXyPJFJdM25G3zfed+B9nJ5eOh2PcBgk1iW2SDld0YzaM9sSv5nrzGE206bQ71ecvHt+9crrlxhNmyfNDGa/XUpM28JZ91m8vOniudNx74KZYTeua88dGnVfN6zSS9zFqf1exf6l0YkXfPrGPx4MqicP+2ktJbFOfD6xTnAD0keADlgD5m0/FOixSdK/AzcBNTAEloEVGwQqUV4M3DsrsaFzHJL4Rcybe1Vveepp5eCU4u5Fmfx9UqIElLb91TPvNf/Pe6479Kmru4P0e/nTkj4KrAAFONX2OdxqJOkjQAAZWBR8DIRhv8T5QAV0HF8BZ5uHAAusEyC4rMDlWaqBocQSsGqbdYlNmYq26q4ddLnf3+9f66qgdkYCIaIYR9k3P99nbdye8K73X/7G3TsGOyI4aiVJv4P9dkgH+zmd0Dme0ZbywwZylWijPDGa9mfcq3++2GyROVYGxO0RRfDimV79zRqkiaS/MLxD0kTwkK5rntVGd+qgmiEchL0wna69qnX30EE9nNa5ZtpNQEkcS3xhCRDHShxljuFSyMP6itzrfXW33P4XSdhgAiFSSksS+wMI+0mli5+XxIa2a1iY2/nirPyqQ9OD+6pe1dOkOzOslwX+6gz0exXX3bjyutmZ3jgn7Y+uPKNKvfc7vFxxNwtHlviVmcHCuUrpPUH8j15VfbRto9zv7F1zn7hg7wurml/o3FGlzKHVCYsLwyd87UNOOWVldXrdJVfsp5RAiM+TxKA/pKp7S6Xt3jYaHTrbSiCB4xtR3Fc5XdQncf3BCfumHVFMrhKHbl7+1ixyf1ARNjmnt9ZVdemJC/dm2qzRxvRXpXSCJMBI6XPGT05Kl5YISKLq15+JNH1rSfnX3bU/i0S/HnJw3w0v+kzz3r8NdzeaDrHO5igBhhnBT+WsbbZJ4oqADy5s619fCtd88GN7Lpyb7bFtpv/krgmKzbQt8QNP+coXvPXdl73t4suWqaqMI61ESn/vKu/vps17iwuLC0McfiRwP8QF3BHxYeBRHBHAWcA7gFO41c8BbwcEJKAAJYkN5xXHtwkRGAMn9Gefu9pNX1tIlOjYYLhpJg+e5dApU08fPj/TY9xM679602XPOPPE0/77SYuFleny/xb8PlA44geAP+NWV4OfCDIgIAMtR1wIPJEvzCAB7wQ/inUBDKr8smL/QVcsiQQUoLCFDVVV07XT3p61G/9nGvTPiklBFddK+kBKunI0bm8+sDT+yFefezLYv/SZS/be94SdszgM4oDQk4EPsClLF6Xce68zn2ia8cssSCnRjqc/3XTx6lC6RCkjF0DcSfM232zT5EpPltI7ojMWRJS33OuE+/5l17R/vmf/5Y8a9GfJytjxoMv3X/6sfSs3vWxbfxtVqjHm7lRVNW3b3H9p6abzIkzKCYlP1qn3EdtLncuFOWlvFTl1tP+DTQ5T1fm3e73BzxLGDrAR3pty/Z0u5V9LlPvMDCtWVqc7lg6O2bF98b9NaP7Jk4KjpeLutxDhc5XSv6WUv8UuE9vYJud0aMe2bb/YdNOzx+Px91cp0+9VRPEpN+9dvX8pvs7mdjmC6XQCEln1a5GebdxLZEzIjm+m+CLZdE1DuOAwymmW8OOURImOrgvue6/7/e3s7Cz/fsX7IPSwmXr2SbODBcCMxm3pD/r/tc7p0hIBGShBN5pi7AS/Ynis7a+tc5+2a07du3b1U/ozvT9KvUSMBeIYth9nMySJulf972jL/7I5iIQd2IGVk4OTJCFMv5fLW999+VIpoosJXbcNNGCQp8xWc+9rB9VLSnTnhMvbSHyiSulzBkoJjsugDKrAHQ3iqAZIbGG7kVT4PGLdNJHeC5xkfD+hyxqXN+fUZ2Y4x8GVG5EyyWJYDVciyl+Mp5OHRzI5J0z3NQfWDuZB3SujJkdxmQpxOxJQgOCIllsZaLkDRgInNoWNQLNVVdbc0dpkjpDEBtuA6VU9xs3aw9Ymy1+3PDrEOfc9+eX7l7pfnk6763MSzbRjtp9pu7jX0tLoP+3YPkMYIgpOfl4mf0BKHNVEgA25/kOhp2A/LksEkW0/VeJXxV0msFF+FkrvYIsSwUx/4coTd977h664+bOfGHhuMadMcdBMVr9v+8yOV+BoMHc/yS7lO20vpJxXZuveT3dq/zgCEwIMJEI8mNDXCXCYlNP+2cWZ35jpD1k7NMKYDRIkcY2r9Ipoy69HmJxE6uWJdw3/ZdjbRnNwlebAQRJ3OyNpksgvACasE2CbXp3ZtjDE0l9VqaJzMDOo6SL47KU3b7/yuiVsI4njkcCY6bRhbbr64ZSqjyYJMEJExFOVklRVUAJPp9C1xGj6aEp8RUoJWfTq6rJDk31vuWH/VQzqPr2qfkKEh9h0XbBr5+zbFrf13tk2hXDgLFSCdnVMR0DERFX1WmTsgJTpa3Bev6lT7oTF55G0rUSpw91Ppbp6ke2DrJMgbMbjln03rvnA/vESgiolqpzqD378mpdfdvX+Rw37NSCqDBUFlWB+dvH5c4PFJ0bE7xreA4y5AzYogRJgjuoB4liVbWyzlTHG7xd6tNBjkvT4SnraoZguOyWSBYgNwiy3a0zdXpGV2FDnmiaanXsO7tl+4/JNdKVDiC36HCsBQzBg7gwjjFjXAzKbBNj0wzCoKmoJ2xyPEeEyGy6Dey3e71fvc+qO55Qo12OIMAsnbaN3wjxX3bj8lKbpduQkSnTU1eCTM735vy4uGLCEZRoH064hSkPdr16GVMwRSTwpJycJsLizjEnSxwWvMbcKm9m6z3RtL3uXLr1q5+yuP++iYEy4MKgH5y4OFu+XlbEMEnc7aSFQuzAcfHddVX8UttnCNkF3f7BYJwnBZ6ar06WlpX2MpytkVdAakyAKRHxCUrBBQkqsXXdzXrliD82hVShQcbcTSB9zig+yQWLaBcZ8+rM30rQmSuzNKTdAry1Bkpid68/arDO3T8gmpQIGxOs66xFinSAcD6tyPldKn4oShAORiPATjJUQQQL5LYdG+w/2mWGx3plGGj9s1IypyHRdsGtxZuTwWTfvG+3q5SwMCKQEtkg6hDSPBYIkKCXOHXfeGfhmiWNIiaabMFfPnd+W6W9TAsJsWF1rOee0Rc79xrPo2vDNB9f+6V8/ed1Th4OanMTunbMPiOCf2lLeX+V4p83729J+ctSsjSftmKo/YNgfEG1HOAibO5SBwhfNNpK4LSWux7rehkqpb3xOuJwJ7ATmkcLE1VPH10pig22Q+jnnodggbsN8PnMLA+KOGHEHzKZKogtzu2wEF9xr531/uW33EA6UE3nHHGm2x85eprlx+aHtwRFhcBTqfm9Prx48dDxdFVCzSaxTAmKaUm8ndGadUoIoDyjEKYJrxF0j8vkp2eqMWSewoZcrmuky4/ESw6r3nnHbvgBElSrarl0ccfC+M9uqT68tBxHmbiYMOeuP6pTe0RazwRhJyBkCBJUxhwnCnpSJPfUKyiKrwmFCUDDrWsDcwqKJYJ0JlETFHZBYJ44yBvPFMyj506oBAwJ34BCHlhtSAiV1ggboiU0GAeYLMCBQMiQQ+ts05X8FnhcCk2PaPCWl9KlwR7FJxKKtJ7NBrHObqd7gyNRVH0uztu8NRkkMBrUvu3L/dyKe1O9X2TY2x3BEoZQKiQ0JUewT65zmMrq5RHAMm0SCPq8Y5BmM8UyftiuoFOphj9ntQ0oE06y/r+v6vV1XHpX7NREGMyv0xEmz9sSxV5sq9y4VvLeU9m11Gr435byUCjjDuJ0i7oC58wzK3MqBknDhLMMzKTx50o3OnkxX+1KSzTqDQRgQRyVA69hkcycZEF8SBguUhBBH2eYIk1JGql575d6PFe0LojX1fJ9U13jU0U2C0pZ7GyNMnfuMpitPXJssP7bKFbbFbZQuXNpJUlLFUWaGaXdvcrqGnMDcKUIE5bOss9kkshKr7ZRVxBHdDVVKY/AQCyxAOw3YYO5eZoO9qzf8074T/STaEJMS4IQAc9g1bLJNSun+g5lhVaJ0XTvFDiwhjCTWnRVBRhwhltJMvpEtKm6HgLA5cHBCCRAQNv1e9uLCgK4LvmjmBnfcKlgnqiqzSRCAAbHJ3BGBgdKCkhC6UU5vDLpnVhIgSpRvpl9+uZk0dF3LoJ59GPYZkhhPO3Yvzn5icWHbB1MS1960j4OrS4M61XN1qrHNOtV1rmwq29wuCXFEsRFsP21ucSEMVy7vI0kcFSXIuW7LrrkL3K9wBJKo20J18xp7xuKqj+xBgpmZ3vLOk7Y9bfnGg6+N8KMxIBAbhKSe7Qe1pX1QTvnHJpPRx/uk362U/spAL1e0peNLLnEsQQQ/bvjVcOzAIAkjDjMg1onjMGDuImPsDsiAkcRWRtxpBsTnsY2kkLggosMhcpXpVsaUgyMOM5laM6ozGIxJShmRbXM8kkAcJoEN4ajutfPeu8fNmKXREjll7hQTytUBbiHAODoMmCMEI2AVNESQspiMyq7JWiElkIRt7oQAzBfNSOnSqdnTlYIQxRlHkG2Q2HRBoGuNT5VERDk9ws+S0h+zSYBZZ3rg5xgjhG2E/pVgiS0qPo/ZEDZVTjzukfclZxE2/bri5v1r1ccuvJ6F+QER5g4JbDpacyuB2ErcRbbJVaLfq7BN2H9WpumZYSOJdQ9ux93D7rX97I9tG+7kir2fempxg5SQEg5ec3B5ldIGnhT6UYEgkpE56jqJ6yUG3C7RdQWD6yrVEbC/GTU2SOIYWWDvjX0rK5EEBgTttDDMiQedNk+UoIS5aa2wvOo9yToP6cctnoT9OOMKjEhsSClhTDsZP9TKr+3V/Z2DqvcHkmhKixBfKhIgjmHz3Ai/VIAkjtA4Jb1F0kfBV0TEBISUH2WXF4EB8f+HbVLOVLnGCLsQbQsSRtxpAgJsczySWLdss19KCAggakEtjkoBMreQ2AtcA1RA4naUEoShrnJKkFa71XHrlkTirhCYLWww62yMOUKA2MqOGgI788WQuIVNBdR8kWSjpD0rpYzsYENGkE3nYIsV279F8AdJCSGaZvI7uUqVpD+1PeKIr8T8huGrJbFBSdi81B1mi4qtbJTqkITCKItelajqhA29XibntCOCOysh7hY2pAR1TxgoHR9j7AsR5yJwMCzt5DsW50742EmL91+84qZPfkcQpBD9QT44OmHmr9XLtPtHSD1Sr5rEuFll3EBdQQTK+ZUSv+8oFYjjkQBpLUGWNKNkVrvpfhvEsSRArJXVaYcNAgfY5iFffwYn7xhgYG3U8sGPXMLsIJNm+wG8lLa8vBBnJaVvSKRHB/EN4TgjSsk5V/TqPhGFUTd5Sa+qPor5MF9CxiRnckkYc5g4q6P8BhiRCIKuTD6UVD+7qupPpwQ2hyUbO/YjXgTirhG3MlImVz3swGRyqmi7FpeCJO4UAwIlIcRRttliDEwNFJthqpjNNcVmQ1IqqzEZTdyRldj0asyvIVcg8XmMEBJrmCSY0brVyepB1kniThOpRLdTgG3CpqoqqipTOpNTZoMdMy5lzoABOxj2hvuqKjOejAmbrSRCMhskaFtoG4gIumJmhtW2fl/DthSEuENK2DFRcSfMBgOWcTa3MtnVy3rUXzv25PtSSn0cM11b/iCl9DzgMttD4MHGOwW0XaHrzLZt/d+s6vT+CLNVBYhNWYlxNBnEYY15/8euZaaeZa4/S4lg3+rSQ+fnKyLMl4OUE21TWF6Z4DCYkar8egbVuZjDqtx79DUrl7Anrn9ktO2unDM2VOQ3VVT7RUapIugQWjG6yvC1YDYIFrPqQyERLhgQW1gUzH1PX2SQKi69Zv9a1RPJwgEdt2FAsqrMUVHMzsUhi9tnGE0LKYnxtLBycMRgxwzVcEAupiiaYn1W6LOJ/Kouuple7n9j7tXPG01Xvk0YSWQlxtPmGYIPK/GlYLawEiWCJMB+AjAvRFda+r2ZQwszO57ble7T42YVG7AorSkR5DqdnnIiwtwZQoSDphuxoco9kjIb7MA2G5QzKYIowd3GHCaJUoKYTpA5TIAqriKJIwxOJ0tpGQWO4DCJDWKdEl2Bk3ZtY2F7n4sv3z+qqwRtBhkU3Fm2ySk90EBOiVqJnMW4TDh95wO51/YzUEpcv3TlSRdf9/Fhvx4iCRDrrhPCHJbYwnbGFpLZYMBi+8KQqkpMps2ZbdciiS+WJAMGcZQMs+ojjjBmxa1L6p7Toz53ZTT5qpwS/V6mhO+fpPuzzgYJogtmhvUqSb8f4V9IySgJmVskoGWTJEqU0yM6SnR0UZCECNpomJbxGVXlRycSXzZsLOF+Dw37aNgjbxu+GaU1d4EEqP/Q6fKhk1ZvvvabnIQRzjDr4V/OXdMxuGTMztU+96p3cm/vYKGa+3iXDQYLbL5FeFYIITICc5gkUkqklLR0cPymvQfWXpmSHiGBUxApuB0JEJtKCR5y7snMzlXUdaLfz/T7iZQTyvrKMm1/Oly+Ptei6iUkEZh1I/DbZoYL315V9V85AkmUKKhO56qXKxuMuRMSkNhCyEKIhBW0aunNZRjURNIDcSCJ4g6l9KHtcydfsG12J6musAMLFndt4+T7nEA96J3TNB0ShxkwxhgjjDlMbEhsCheqlMu2wSntzrkzqFKPcHBbjiDXNZKwzZ0iwOAwtrGNbW5DgFiXDK2CUU+0g4rpIDPpJ5jrfyIhsLEh7G/O/Xp3rnqghOrMBtukVJFTjySxutb83c371l6bkr5JSdjcZULYPq8EGqhmW387UkIS03bMgfGN3HzwapbX9j6clBFig6R9k2Zy+ep0DSWQ1LDJNutOVK53IOEwKZv5mYpdi33Ovs9Oti/WP7B/aUzOiTtBgNiiTpkECBAgBOaBXZRXT5vuwbsWZ67YNt//u1J8aU4KNgiU3Nq+pK3qv7rvGbu/9Zyzdv7CtCnUmiFa0ZHoLDqLCljCBgnbCH1jTloMWAobpYTdsVY6Ju30ZcmazcoY82XDJtcVVc4EIPuTtt9Vsp7MOiXPQPoZTXksSQjRlObfD/jAh5IypXTsSLvY1utTLEpXzncpI1X1DIZw3G+ap8+x+d2eKpKhOBBmgxLIPG/vvrXvjDBzs71nuPGbgGfbHBJ3LGdx9TWrHNjX0pUgJTGddt87nMnPlfQV3aTZST+/HemJqiBliNZIonNHM11mpqpft9w1T2NTciIp0XLHbOMwJMAEUrBFwEAYKXFYV5gdJLoWJoXepINk06sGtO2Ya2/6FAwHpF6NS0uuRdN1eMLMcFD94L59LYvbK8KBnNqEpk4JY3DgANuAihKHtV1LNRgOHnbuOcOb9t3UXnbtQaDjuGyquqZrG+4UAwJJSOIo29yejBjTsUKDEAg0nr4lBQeqVO8AY3tXaZufoPh/pDpDL+O2AZvDHEg85dDK+CntUjA70/tPpY3zU/L3IfZzVwhsHmL4AYu/tM2GKtUcGh1gaXoDa2vLJ9LxrEFvFmGKgyQ+1at6l0OAIOR9nY04whFnpUH/odFN3x6lgEQSXHvdMpdfNn1OvbDyyJ2LM5QS3FUG+jmTEcEtTiP4l5TSqftX1q542Lknf8vaqLvkkxfdeO+F+d6ZbfEsQimxXApXppn+HhIkJSaTCXn+XrjtaHuCKGyoUs6fweVRESAJm/uEeYXEfwZWgAy6N6X8TiJ9S5YOGveBIV8uJOgK0XWAwID4e0tPFkdE+PkkYZtJN+L0Ex/02hO233sy7SbkXLN86AZWVvdTVT0q8kdne3P/Mu2m35VzAoM7fk3WPlW8BhPcQsn2D5USvzMc1GwoETWoVkpTDgvuSM6JS67ciw2IoxbmZ/uPdkCqEqXz4zHPzEl/DkaskwCzOlmmSvUTpYxtqlTTlMnFFDpJbDC3T1VG4gix5C5WjdkgoDh+Iil9WHAzG6R+iSiTcdM1bdmrlNhgQ07pUSr+Jvq992CBIaXEof1r+eb9K7974u65M+fnB2AwpiLtqsg72uSbicA2VZ3pVZkS3juddkiQVDOZjk+d6vLnrzUHXjxppm2vlxPQAxogOMom50zXcucICDAG80WxhIpR13JU4D39wdwbuuiek0hIorTdzydzk6r0x0DLFsbfHi6v7fUyvV5FCSuJ+arS2DYR3DVGUF6OY49SfrcsjKlSjRI7J6n/qtTLuyAwJjCDPPibft3vRtNVwh3FfNqIKmU2Vd1k7XckfgilfweH0UKvz7Mbr/5madO039eo7bwocZcIWC0NWxmeLzg1SrB9YfjBz1118JLSFQaDak9bvMcGDMWCBHky4cqrGqqUScm0XYMSCHNUtbzcvnnaTH7shF2zEBCYYn93gq8Q+pjx4jS6rwnHCUJXK6VX2PFLfBlJiM4dnVuOENj/UKl3nVI+xTaIIySE1vqp+qdh7pPC1LnHKtBFByWRU2ZYD3553I4f3zVlvlfXCA0tXh3298i8E7ge2B32t8rxJAlsKDZ1ShdXOf9EQ0xkIMRhNl9IyiZsjhL8pZyfYeIbpQS2wK9ycF/QayTdzDqhXYGe2UT33IQ4wuSU3iCgCzaZ4wqTBzUMB2BQlW9q9x260mvTs1VnDGTpccB7wO9jg/TQ0XLzohKcb+f3SUbisLBnQH+Z2/Ibls4HXLryFcOZ+lm7q/knjkbdp07Y0c9diQclEoWyOxy/SqRXYM9IOr+UWC6YCH86SilVXeW6zkRE/tBH9/xKnevHDgfVx8M+O0rXtlGeDeznNmRzPMZ8QQbEF6WUjm0z29k+3E4QbJBERPzK1QeufnIFJ6eUUEo4/JKwn6Iu3gxcJ2muRHmizfcIZRvsQGY0d8Li0/tzw9FkeY3VfQdJOXMnLaeUPu7wY8al/Uc3o1da8XbMpHPzgOL2OZhzkdnQdg2D/tyF59znEX8G4srr/o218QEGVe8j01JuDPskIRDg+AqjdwPvlTRq3X5NF3HfXl/M5eELJtE+zfIjhbirIgCz1YMlsKBO6Ulra81PgP8lJ01txFHmMIU1WmsQVZtzOpBTHlEEmKOqh37lye+5+Iq975pMuscO+xUYBNjcH3z/nETTFZoumBsMn2HHAeNfE2KTAXMrA4VjFb6wAIJjmVsFEBzLbDIGZXopg8ymA5V6b5+0k/+SU+ao4mChP/e28fI1n7106UoksI2qGXrVEBMYY/tTdV3/QOnitVFiLlcJDG0p3y749iRhNhilTJQCNiSuNjwduA4DxSA2FI4VgNmiThVZbDU1PKvrynuim55cVT0QKdr4hVb6qSR/lnVhzhGaEUcYk5T+ROhdwkhmnW1uK9ggEZMxVa8mVRWE0dzwTyaj6RNcAuXEEfFAWw9kXRKMJu0gKdGfnTu/nY7fNhk3TxwMajY4c0pZm7zMJlJS0LpaWWuYHdZ8//ee+11v/OeLfvzg6vhBO7cPiTBBfK+Kvxc4IKUHYJYLiVzrisr6s9GoedbMsCanhA1hP1oRjwYRcLFsjkuJ4zDGYLYwGwwIJCGJTWGbLQIINuWUWR4fYttgnl7dp0RBEpjrZ+vZ72qjeasjdkgJkoiuPIa2e4xSYoMjSEk4jA0klmS+O+d8qUvQThoksa5wrA4wtzJbSIreMD1rOvJPlRI/utwtPb/K+fmJzFo5SEqZnBI2YBOwNlsPnpVzry1ROG3nGUR3Mr3c23P96r7fv3bpmhf3c42UQGLdAvDttikuhGG+GvxxlfXKrsR/lQFxVOEoscEcKwCzhRVYZouDyQmRiOLFJP8foYnNISBzWyLlnJAYRZcua7rJv0C8HLTEpvSt5505fvbTH/qMlPSxvUsjUhJHmA3TpmMwqDlhYe4nm7Z5b+fuoUJssQAMudUQOIVj3YsvbBuwjWNt51bzwG6ONccxTJVqenlAnfvUeQDiFTllbmGTBV2lN63ITKrEOCcmVWKkhkJBiA3GgP5x966Fxw9nqk9MmwCJJIHAgCQ2LK9O2FD1qjcinQd8nA0RgMEG+2SOdS9gwBadAwMGDBgI+5JBb/a8+dnFf7aNbSRhe9A5HoL9ENsztilRQCDppTbPA7pis6kHzHOs7WwyogJqQxVBf1D/XepXLw6bsNlgQ0ThMMOhlSYtrUxJ0TbzM/Vz5uf7H7HBBiE25KwUUC2vTmnabv8pJ29/6q4TZi6/bv+hV9Z1uilswITNpgIUY2YW55nfvehtu7b/3MK24fld19CVjpQTYIw4zJGLC+EgHISDcBAObkcP2M6xZsCAwWwyYMA7ONZuYI4tEolDo0N0pWODbWyTlD481587L6X8Djs4QqDEEQKJtVFDIKq6+pesdJ7F+STomo7pygilxLqTOdZ9gJpb9YEBR9nbU8UprvRTKad/qHONi5g2HXXdpwR0XSCz4WpLTzT+NzuwgxKFEoW2tPSq/m8leIUdGIgoYLPBQNMEOee/y7l6wWqZPsDmHCG22MU6J+EsSMxxrF1AzSZjeuoz0JCBBgw0YKDBnzuguEPiMOMB+ETwLvAu8C7wLvAu8A5ghx2n1FX/mw6NDrx4Mh39g5J2syk/+gnPZH6ut3LxZfvesHRgcmhurreAPUSpzTntWVlr/n5+bvCCnQszf3PzwVWqnHcoKSP9G9JnBO/L5p2y1xxmXQKGwOcEHwMuAv4J+BxbSCCBBBJZUk/SpyT9m6SLDG8BrhUgyEANXAx8FLhY6C1CVwohhBCWCYJwEA7WXSekcFwl6SPARUnpbeT0R62jK5iCKUAXhZ56JCUQRBSa0jI3179O8htWVtsL+1XqgEpKCSgRXlJOl56yc/ZNTa5/tkvpN2m7pSSRU6KEkQQSSH1JraQPS7pQ8F7BOwUTAQLEOhtJHBUu9Pvz+2YGc28Yt8ufEeqkNAMMhAwUxERKl/Tr3l+Dfsb2H4EiSRSzToAEzAFXAB9G8dlK1TtSVJ9TJBQZtyb1MySBoZlO3yXSh7LA0kySXOdqddKUSzqX1//0jz3ib5//rK9fHfTEv3/mxkPbF4dvWBs1KymlXcCCJLpwl2DPqacs/lUXPPuknbPvHcxkPnLhtfvO3L37nwSDEmWhTnWLfKWSXuWU3oUUpSsoJeo6j7YN0utXV7hBqnqo1CmlRnCwRLlgdjD3RydvO/kjc/252DbYxrbBNhYGC8wOZhl3E4JAEggQIDZsA24APhyOS/t1/y1V1b88pYoSpikdkLCFrZ6kStJHJH1K0vslvV3SiiQksaEpLXODWZISG2wzakZUKd3URrwB4kIprYGqlKgQXdgrKaXL7rV7/h/alH7Zwa8pYo9lesMBk+U1XAIQ62aBZeAjwIVC7wXeBRRzWIU0QLoQ6RPABfOx7RNKunya2jcM1L+GFINBv9rWdCX36mqcxMX06pdW/eq/ttPpZ2bqGXYsnIptol3F0ZGUmJSGQ6NDb84pX6yU5qpczVimK3EgZ/3rgx9w0s9b6ZdXV6ddcdQJZcsXC30M+DTirSmlPQvUDCfBZDSZmXTdas75A5Iusn0+8CEgWGfMQAN69MhUVFRUqi6pZnsfUtGDwuVkDhNgjk/YxpikBIKwT5c0p5TeCqaSRNMWCA7WKb1Y0u9VdbUL1Ld9M7DSlaArQUoJpPOB89nKbHUAeCF3zuXAj3H79gAv4A4IcVvG/5PbkCEjMLcw4nhsE+ElSa8FXptSmkmp3lncDFPFkkMrC3ODydJyQ2k6EluIrd4MvJk7YG5L2EGJrpH4m8B/k1I1L+I0l24RpYJ9s8SeKlfjEg23YxX4WbaykBNWIAt3wTEMkt6eory915uZ7VeD+X5vpqzedM1KJE8eePYJPORBJ/HZi/cymXZ0JQ4B/0vi94D7SNpdGq8IrljcPjx484ExbVeockKIrPxZqXtWnXrzuwa76n3TfeMm2rHEOlG6wgbbtF0ZS/XLJP9JVpnpD3qzLmWyOi2rVa7amd4MXXQcJURx4XY0wK+zlYSUOUziNt4PvJ87kFNGiNsyGzxBvN7m9TlrWNXVjraNWVIciuJD2+f6k+V2QheFzCab0nRs8RfAX3D7rgZ+jE0GUsnknLFdSuFVu0+YffVZ99m54x/fefFJD37gyStLS6s3rIQmOSew+SK8LqJ9w87F07YtTw5un5TV5QqWFrcP48DyFAxJ6bogfpKtxGG5KeQiVPynSH/KcdhGEpEaOjWYI0oppGnvgirnS5vCQ7J0teHjKI2AzLEsiKy0I+xHR8SslFAlYjw9z7BoWKrYZMCYdVNgD1uIe2wxAkask8BAVwJsxP81K8BnuA3b3GkyRxgkjsds0JrQmkhsELCy1jCadEymHSmJLcbARcBF4oiuC2yzVdjYZt1KInFbkjiWMe6AZWCZTbYpUShROEqI4sKdY/4vGQN72KIrgW1uS0m4cJdZxpgNtkmJrsppb5i9KXGEDTZ3QkmkJWCJTW1biDB3xEk4CcRxSdB1JkoQnbHNBhv6/fxDXTf9/S667VVV/3Wi+skS3V5zRJLoStA0heGgApnZeoaudI8/NF19Ta/q7bYNKc0BJwiWKu5xjzvBmLuDMfe4+9kQNgJs7jJj7g6jccsZpy7yleecyHjSclRd59Pe/YErXjZuutmZfg+h37FjryyqBAE0Tcf2hQEnn7iNS67YR5RgrCmLcye+o7UvGzWru3u5j/GaYYl1iXvc4x73+DJgm0G/pq567D0wZWm5Y2m5Y2m548Ch9gFGszkljJH0TKBiXU6JDLRtYXam5n5n7MRAKabY9bQ0/z0cD0lK2Ab0SSndLCUq7nGPe9zjy4AkQFx17RKXXLEPiVuZz/SHaanXy4sYutI9T6QHJvFPEfG5gP05p3Y6LemGvatDYHfO6ayI8oT9h65/TJUrhLDc1HX+va4FCSrucY973OPLhkmCQS9xG9cl9DMl4k8kEALivIDzIsSGfj9z4NCEff9+LVVOkMSGKtc4TFZ1wPAjwIfYlLjHPe5xjy8TlURdi7oWdS3qWtS1qGuRxMtTSt9cKb0jbMKsE7bBYIMwEBhzmAFpnyq/Ym6w7byU8t+ZW1Xc4x73uMeXCbPOHJcBibfh9K+Dqn5olfNXrU7XHpCUdwOzyD0plX6uRhGxRPKVcvpM4AtypavCBWy2+v8AU9ktvtF1ZvcAAAAASUVORK5CYII='
	$logoBytes = [Convert]::FromBase64String($logoBase64)
	# initialize a Memory stream holding the logo
	$logostream = [System.IO.MemoryStream]::new($logoBytes, 0, $logoBytes.Length)
	$imgUFR = [System.Drawing.Icon]::FromHandle(([System.Drawing.Bitmap]::new($logostream).GetHIcon()))
	# adding the icon to the main GUI
	$objForm.Icon = [System.Drawing.Icon]::FromHandle(([System.Drawing.Bitmap]::new($iconstream).GetHIcon()))

	$objpictureBoxUFR = New-Object Windows.Forms.PictureBox
	$objpictureBoxUFR.Location = New-Object System.Drawing.Size(30,35)
	$objpictureBoxUFR.Size = New-Object System.Drawing.Size(320,36)
	$objpictureBoxUFR.Autosize = $true
	$objpictureBoxUFR.Image = $imgUFR
	$objForm.controls.add($objpictureBoxUFR)

	# Menu Options - Help / About
	$objFormmenu = New-Object System.Windows.Forms.MenuStrip
	$objForm.Controls.Add($objFormmenu)
	$objFormHelp = New-Object System.Windows.Forms.ToolStripMenuItem
	$objFormHelp.Text = "&About"
	$objFormHelp.Alignment = [System.Windows.Forms.ToolStripItemAlignment]::Right
	$objFormHelp.Add_Click({About})
	[void] $objFormmenu.Items.Add($objFormHelp)
		
	#This creates a header 
	$objGroupShareLabel = New-Object System.Windows.Forms.Label
	$objGroupShareLabel.Location = New-Object System.Drawing.Size(30,80) 
	$objGroupShareLabel.Size = New-Object System.Drawing.Size(150,400)
	$objGroupShareLabel.Font = New-Object System.Drawing.Font("Arial",12,[System.Drawing.FontStyle]::Bold)			
	$objGroupShareLabel.Text = "$tool"
	$objGroupShareLabel.Autosize = $true
	$objForm.Controls.Add($objGroupShareLabel)	
			
	#This creates the drop-down list header
	$objListHeader = New-Object System.Windows.Forms.Label
	$objListHeader.Location = New-Object System.Drawing.Size(30,125) 
	$objListHeader.Size = New-Object System.Drawing.Size(200,30)
	$objListHeader.Autosize = $true 
	$objListHeader.Text = "Select your network share:"
	$objListHeader.Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Bold)
	$objForm.Controls.Add($objListHeader)
	
	#This creates the drop-down list for the group shares
	$global:objGroupDriveList = New-Object System.Windows.Forms.ComboBox
	$objGroupDriveList.Location = New-Object System.Drawing.Size(30,150) 
	$objGroupDriveList.Text = "Network shares"
	$objGroupDriveList.Size = New-Object System.Drawing.Size(220,40)
	$objGroupDriveList.Autosize = $true

	# Populate the drop-down list
	# $groupshares.group | ForEach-Object {$objGroupDriveList.Items.Add($_)}
	Foreach ($groupx in $groupshares.group)
	{
		$objGroupDriveList.Items.Add($groupx)
	}
	
	#This creates the group share path header label
	$objGroupShareHead = New-Object System.Windows.Forms.Label
	$objGroupShareHead.Location = New-Object System.Drawing.Size(30,200) 
	$objGroupShareHead.Autosize = $true 
	$objGroupShareHead.Text = "Group share path:"
	$objGroupShareHead.Autosize = $true
	$objGroupShareHead.Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Bold)
	$objForm.Controls.Add($objGroupShareHead) 	
		
	#This creates the group share path label
	$objGroupShare = New-Object System.Windows.Forms.Label
	$objGroupShare.Location = New-Object System.Drawing.Size(30,220) 
	$objGroupShare.Autosize = $true 
	
	# This adds the IndexChange Trigger to the drop-down list
	$objGroupDriveList.add_SelectedIndexChanged({
		$global:groupshare_sel = ($groupshares | where-object {$_.group -eq $objGroupDriveList.SelectedItem}).path
				
		$objGroupShare.Text = $groupshare_sel
		$global:gshare = Get-PSdrive | where-object {$_.DisplayRoot -eq $groupshare_sel}
		
		#This updates the Network Mapping Button
		$objMapShareButton.Enabled = $true
		
		# This updates the Disconnect Group Share Button
		if ($gshare)
		{
			$objGroupShareButton.Enabled = $true
		} else
		{
			$objGroupShareButton.Enabled = $false
		}
			$objForm.Refresh()
	})

    #This creates the persistance header label
	$objPersistanceHead = New-Object System.Windows.Forms.Label
	$objPersistanceHead.Location = New-Object System.Drawing.Size(30,260) 
	$objPersistanceHead.Autosize = $true 
	$objPersistanceHead.Text = "Select mapping option:"
	$objPersistanceHead.Autosize = $true
	$objPersistanceHead.Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Bold)
	$objForm.Controls.Add($objPersistanceHead) 	

    #This creates the persistence radio button selection
	$objPersistanceCheck = New-Object System.Windows.Forms.RadioButton
	$objPersistanceCheck.Location = New-Object System.Drawing.Size(30,285) 
	$objPersistanceCheck.Autosize = $true 
	$objPersistanceCheck.Text = "Persistent mapping"
    $objPersistanceCheck.Checked = $true
    $objForm.Controls.Add($objPersistanceCheck) 

    #This creates the temporary radio button selection
	$objTempCheck = New-Object System.Windows.Forms.RadioButton
	$objTempCheck.Location = New-Object System.Drawing.Size(30,315) 
	$objTempCheck.Autosize = $true 
	$objTempCheck.Text = "Temporary mapping"
	$objForm.Controls.Add($objTempCheck) 
    	
	#This creates the Network Mapping Button
	$global:objMapShareButton = New-Object System.Windows.Forms.Button 
	$objMapShareButton.Location = New-Object System.Drawing.Size(30,370) 
	$objMapShareButton.Size = New-Object System.Drawing.Size(220,30)
	$objMapShareButton.Text = "Connect / Open Share"
	$objMapShareButton.Autosize = $false
	$objMapShareButton.Add_Click({handler_click_MAPSHARE($groupshare_sel)}.GetNewClosure())
	$objMapShareButton.Enabled = $false
	$objForm.Controls.Add($objMapShareButton)
	
	# This creates the Disconnect Group Share Button
	$global:objGroupShareButton = New-Object System.Windows.Forms.Button 
	$objGroupShareButton.Location = New-Object System.Drawing.Size(30,410) 
	$objGroupShareButton.Size = New-Object System.Drawing.Size(220,30)
	$objGroupShareButton.Text = "Disconnect / Remove Share"
	$objGroupShareButton.Autosize = $false
	$objGroupShareButton.Add_Click({handler_click_REMOVESHARE($groupshare_sel)}.GetNewClosure())
	$objGroupShareButton.Enabled = $false
	$objForm.Controls.Add($objGroupShareButton)
	$objGroupShare.Text = $groupshare_sel
	$objForm.Controls.Add($objGroupDriveList)
	$objForm.Controls.Add($objGroupShare) 
	
	$objForm.Add_Shown({$objForm.Activate()})
	$objForm.DataBindings.DefaultDataSourceUpdateMode = 0
	SetDoubleBuffered $objForm
	[void] $objForm.ShowDialog()
}

# Calling main GUI Function
workstation_gui