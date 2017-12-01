#-------------------------------------------------------------------------------------------------------------------
# Set Variables & Credential

$cred = Get-Credential -UserName 'contoso\SP_Farm' -Message 'Enter Password'
$servers = 'SP-app01','SP-app02','SP-srch01','SP-srch02','SP-wfe01','SP-wfe02','SP-wfe03'
$RPath="\\NetShare\Sharepoint Updates\April 2017 CU\SharePoint Server 2013"

$MailFrom = "Some SP Farm <SomeSPFarm@contoso.com>"
$MailSubject = "Installing CU"
$MailTo = "Admin1 <Admin1@contoso.com>", "Admin2 <Admin2@contoso.com>"
$MailServer = "mail.contoso.com"
$MailBody = New-Object System.Text.StringBuilder

#-------------------------------------------------------------------------------------------------------------------

$RemoteScript = {
param($RPath)
$RAMDisk = $(ls function:[g-z]: -n | ?{ !(test-path $_) })[0]
$TMPDIR = "$RAMDisk\TMP"
$Date = $(get-date -uformat %Y%m%d%H%M)
$LogPath = 'C:\scripts\log'
if (!(Test-path -Path $LogPath)) {New-Item $LogPath -ItemType directory}

Write-output "$(get-date -uformat %H:%M:%S-%m.%d.%Y) Create RAM disk $RAMDisk"
imdisk -a -s 10G -m $RAMDisk -p "/fs:ntfs /q /y"
sleep -s 30
New-Item $TMPDIR -type directory

$env:tmp = $TMPDIR
$env:temp = $TMPDIR

Write-output "$(get-date -uformat %H:%M:%S-%m.%d.%Y) Copy CU files $RPath"
Copy-Item -Recurse -Path $RPath -Destination "$RAMDisk\Updates\"
#robocopy $RPath "$RAMDisk\Updates\" /J

set-alias app2run (Get-ChildItem -Path "$RAMDisk\Updates\*.exe").FullName
#app2run /passive /norestart PACKAGE.BYPASS.DETECTION.CHECK=1
write-output $(Get-Alias app2run).Definition

app2run /log:"$LogPath\opatchinstall($date).log" /quiet /norestart PACKAGE.BYPASS.DETECTION.CHECK=1

Write-output "$(get-date -uformat %H:%M:%S-%m.%d.%Y) Waitin for temp folder"
$dyntmp = ""
while (!$dyntmp) {
    sleep -s 15
    $dyntmp = (Get-ChildItem -Path "$RAMDisk\TMP\*.tmp" -Directory).FullName
}
Write-Output "$(get-date -uformat %H:%M:%S-%m.%d.%Y) Temp folder - $dyntmp"

# Waiting while exist temp folder
while (Test-path $dyntmp) {sleep -s 60}

Write-Output "$(get-date -uformat %H:%M:%S-%m.%d.%Y) CU is Installed. Need to reboot"

}

# Start here

$Date = $(get-date -uformat %Y%m%d%H%M)
Start-Transcript "c:\scripts\log\CUinstall($date).log"
Import-Module VMware.VimAutomation.Core
Connect-VIServer -Server stal-vc -Protocol https

foreach ($server in $servers) {
Write-host -f Green "$(get-date -uformat %H:%M:%S-%m.%d.%Y) $server"
Send-MailMessage -Encoding UTF8 -From $MailFrom -To $MailTo -Subject "$MailSubject" -Body "$(get-date -uformat %H:%M:%S-%m.%d.%Y) $server - Begin Install!" -Priority High -SmtpServer $MailServer
Invoke-Command -Credential $cred -ComputerName $Server -ScriptBlock $RemoteScript -ArgumentList $RPath

# Make reboot
Restart-Computer -Credential $cred -ComputerName $Server -Force
While (Test-Connection -ComputerName $server -Count 1 -Quiet) { Write-Output "$(get-date -uformat %H:%M:%S-%m.%d.%Y) Not rebooted yet"; sleep -s 5 }

# Waiting while reboot
$count = 0; while (!(Test-Connection -ComputerName $server -Count 1 -Quiet)) { if ($count -gt '20') {Restart-VM -VM $server -RunAsync -Confirm:$false ; $count=0}; $count+=1; Write-Output "$(get-date -uformat %H:%M:%S-%m.%d.%Y) Reboot VM $count"; sleep -s 10 }

Write-host -f Green "$(get-date -uformat %H:%M:%S-%m.%d.%Y) $server - CU install complete!"
Send-MailMessage -Encoding UTF8 -From $MailFrom -To $MailTo -Subject "$MailSubject" -Body "$(get-date -uformat %H:%M:%S-%m.%d.%Y) $server - CU install complete!" -Priority High -SmtpServer $MailServer
}

Disconnect-VIServer -Server stal-vc -Confirm:$false

Stop-Transcript