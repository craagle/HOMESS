# Default: install into ALL supported Rhino versions found on this machine.
param([switch]$ValidateOnly,[switch]$Uninstall,[string]$RhinoVersions='7,8,9',[ValidateSet('auto','netfx','netcore')][string]$Runtime='auto',[string]$Destination=(Join-Path $env:APPDATA 'PIStudio\Plugin'),[string]$UserSid='')
$ErrorActionPreference='Stop'
if(-not [Environment]::Is64BitProcess){throw 'Hay chay Install.cmd bang Windows x64.'}
. "$PSScriptRoot/Installer.Core.ps1"
if(-not $UserSid){$UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
if($UserSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$'){throw 'Tai khoan Windows khong hop le.'}
$userRoot="HKEY_USERS\$UserSid"
$majors=@($RhinoVersions.Split(',') | ForEach-Object {if($_ -notmatch '^[789]$'){throw 'RhinoVersions chi nhan 7,8,9.'};[int]$_} | Select-Object -Unique)
$hosts=@(foreach($major in $majors){Find-Rhino $major $userRoot})
if(-not $hosts.Count){throw 'Khong tim thay Rhino 7, 8 hoac 9 tren may.'}
$manifest=Get-Content -LiteralPath "$PSScriptRoot/packages.json" -Raw | ConvertFrom-Json
$plans=@(Get-InstallPlan $hosts $manifest $PSScriptRoot ([IO.Path]::GetFullPath($Destination)) $userRoot $Runtime -Uninstall:$Uninstall)
if(-not $plans.Count){throw 'Khong co Rhino hop le. Can Rhino 7.38 tro len, Rhino 8 hoac Rhino 9.'}
if($ValidateOnly){$plans | Select-Object Rhino,RhinoVersion,Runtime,RuntimeNote,RuntimeFix,Source,Target,NeedsAdmin;return}
if(Get-Process Rhino -ErrorAction SilentlyContinue){throw 'Hay luu cong viec va dong TAT CA Rhino 7/8/9 truoc khi cai dat.'}
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(@($plans | Where-Object NeedsAdmin).Count -and -not $admin){
 Write-Host 'Dang ky PIStudio cu o cap toan may. Windows se hoi quyen de cap nhat dung cho tung Rhino.'
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-RhinoVersions',('"'+$RhinoVersions+'"'),'-Runtime',$Runtime,'-Destination',('"'+$Destination+'"'),'-UserSid',$UserSid)
 if($Uninstall){$arguments+='-Uninstall'}
 $child=Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -PassThru -Wait
 if($child.ExitCode -ne 0){throw 'Chua cap nhat duoc dang ky toan may. Chay Install.cmd voi quyen administrator de xem loi.'}
 Write-Host 'Da hoan tat cho tat ca phien ban Rhino duoc chon.';return
}
$backup=Invoke-InstallTransaction $plans (Join-Path $Destination 'Backups') -Uninstall:$Uninstall
foreach($plan in $plans){if($Uninstall){Write-Host "Da go dang ky PISTUDIO khoi Rhino $($plan.Rhino)."}else{Write-Host "Da cai PISTUDIO $($manifest.Version) cho Rhino $($plan.Rhino) ($($plan.Runtime)).";if($plan.RuntimeNote){Write-Host $plan.RuntimeNote}}}
Write-Host "Ban sao luu: $backup"
if(-not $Uninstall){Write-Host 'Mo lai Rhino. Toolbar PISTUDIO se tu hien; go PISTUDIO neu can.'}
