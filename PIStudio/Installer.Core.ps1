# Functions are separated so discovery/rollback tests never touch real Rhino registrations.
$script:PluginId='50ad9566-442f-426e-a90b-1af6fded4186'
$script:LegacyIds=@('b5264d75-8cc0-47b1-9dc8-dda3d7874cb0','1b57479f-71d8-4293-9412-ed3e6a1c73c1','aba041bf-fd93-4bd0-96c7-98388804b720','c8e2f338-d705-46f0-b833-85a8dd71e142','3da55dba-1ef9-49c4-9d9f-91f006ccbd84','51e24895-a67d-4932-b66b-d2c33562f947','07840fd6-a825-45ec-bbe3-09415da81f90')
function Reg-Exists([string]$Key){Test-Path -LiteralPath "Registry::$Key"}
function Reg-Value([string]$Key,[string]$Name){if(Reg-Exists $Key){(Get-ItemProperty -LiteralPath "Registry::$Key" -Name $Name -ErrorAction SilentlyContinue).$Name}}
function Reg-WriteString([string]$Key,[string]$Name,[string]$Value){[Microsoft.Win32.Registry]::SetValue($Key,$Name,$Value,[Microsoft.Win32.RegistryValueKind]::String)}
function Reg-RemoveValue([string]$Key,[string]$Name){Remove-ItemProperty -LiteralPath "Registry::$Key" -Name $Name -ErrorAction SilentlyContinue}
function Has-Net8Desktop {return @(Get-ChildItem -LiteralPath (Join-Path $env:ProgramFiles 'dotnet/shared/Microsoft.WindowsDesktop.App') -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^8\.0\.' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'System.Windows.Forms.dll')) }).Count -gt 0}
function Reg-Delete([string]$Key){if(Reg-Exists $Key){Remove-Item -LiteralPath "Registry::$Key" -Recurse -Force}}
function Reg-Export([string]$Key,[string]$File){& reg.exe export $Key $File /y | Out-Null;if($LASTEXITCODE -ne 0){throw "Khong sao luu duoc $Key"}}
function Reg-Import([string]$File){& reg.exe import $File | Out-Null;if($LASTEXITCODE -ne 0){throw "Khong khoi phuc duoc $File"}}
function Reg-Register([string]$Key,[string]$File){
 New-Item -Path "Registry::$Key\PlugIn" -Force | Out-Null
 foreach($e in @(@($Key,'Name','PISTUDIO','String'),@($Key,'FileName',$File,'String'),@($Key,'LoadMode',1,'DWord'),@("$Key\PlugIn",'FileName',$File,'String'))){New-ItemProperty -LiteralPath ("Registry::"+$e[0]) -Name $e[1] -Value $e[2] -PropertyType $e[3] -Force | Out-Null}
}
function Find-Rhino([int]$Major,[string]$UserRoot){
 $paths=@()
 foreach($root in @('HKEY_LOCAL_MACHINE',$UserRoot)){foreach($name in @('InstallPath','Path')){$value=Reg-Value "$root\Software\McNeel\Rhinoceros\$Major.0\Install" $name;if($value){$paths+=[string]$value}}}
 $paths+=Join-Path $env:ProgramFiles "Rhino $Major"
 if($Major -eq 9){$paths+=Join-Path $env:ProgramFiles 'Rhino WIP'}
 foreach($path in ($paths | Select-Object -Unique)){foreach($exe in @((Join-Path $path 'System\Rhino.exe'),(Join-Path $path 'Rhino.exe'))){
  if(Test-Path -LiteralPath $exe){$v=(Get-Item -LiteralPath $exe).VersionInfo;$version=[version]::new($v.FileMajorPart,$v.FileMinorPart,$v.FileBuildPart,$v.FilePrivatePart);if($version.Major -eq $Major){return [pscustomobject]@{Major=$Major;Version=$version;Exe=$exe;Runtime=[string](Reg-Value "$UserRoot\Software\McNeel\Rhinoceros\$Major.0\Global Options" 'DotNetRuntime')}}}
 }}
}
function Get-InstallPlan($Hosts,$Manifest,[string]$PackageRoot,[string]$Destination,[string]$UserRoot,[string]$Runtime='auto',[switch]$Uninstall){
 $plans=@()
 foreach($hostInfo in $Hosts){
  $major=[int]$hostInfo.Major;if($major -notin @(7,8,9)){continue}
  $flavor=if($major -eq 7 -or $Runtime -eq 'netfx' -or ($Runtime -eq 'auto' -and $hostInfo.Runtime -eq 'netfx')){'netfx'}elseif($major -eq 8){'net7'}else{'net10'}
  $runtimeFix=@();$runtimeNote=''
  # RH-99401: this exact Rhino Windows release ships an IronPython that fails on .NET 10.
  # The legacy-host native UI run also failed on this build. Use the tested
  # .NET 8 path; never silently fall back to an unverified runtime.
  $repair8=-not $Uninstall -and $major -eq 8 -and [version]$hostInfo.Version -eq [version]'8.36.26279.7001'
  if($repair8){
   if($Runtime -eq 'netfx'){throw 'Rhino 8.36.26279.7001: .NET Framework chua dat kiem tra UI. Dung Runtime auto voi .NET 8 Desktop x64, hoac cap nhat Rhino ban sua loi.'}
   if(-not(Has-Net8Desktop)){throw 'Rhino 8.36.26279.7001 can .NET 8 Desktop Runtime x64 de chay PIStudio. Cai runtime tu Microsoft hoac cap nhat Rhino ban sua loi, roi chay lai Install.cmd. Chua thay doi cai dat.'}
   $flavor='net7';$globalKey="$UserRoot\Software\McNeel\Rhinoceros\8.0\Global Options"
   $runtimeFix+=[pscustomobject]@{Key=$globalKey;Name='DotNetCoreVersion';Value='8'}
   $runtimeFix+=[pscustomobject]@{Key=$globalKey;Name='DotNetRuntime';Value='netcore'}
   $runtimeNote='Rhino 8.36 RH-99401: su dung .NET 8 da kiem tra UI thuc te. Can mo lai Rhino.'
  }
  if($major -ge 8 -and $Runtime -ne 'auto' -and -not $repair8){$runtimeFix+=[pscustomobject]@{Key="$UserRoot\Software\McNeel\Rhinoceros\$major.0\Global Options";Name='DotNetRuntime';Value=$(if($flavor -eq 'netfx'){'netfx'}else{'netcore'})}}
  $entry=@($Manifest.Packages | Where-Object {$_.Rhino -eq $major -and $_.Runtime -eq $flavor});if($entry.Count -ne 1){throw "Thieu goi Rhino $major / $flavor"};$entry=$entry[0]
  if([version]$hostInfo.Version -lt [version]$entry.MinimumRhino){Write-Warning "Bo qua Rhino $($hostInfo.Version): can $($entry.MinimumRhino) tro len.";continue}
  $source=[IO.Path]::GetFullPath((Join-Path $PackageRoot $entry.File));$prefix=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
  if(-not $source.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Duong dan goi khong hop le.'}
  if(-not(Test-Path -LiteralPath $source)){throw "Thieu $source. Hay giai nen toan bo ZIP."}
  $identity=[Reflection.AssemblyName]::GetAssemblyName($source)
  if($identity.Name -ne 'PISTUDIO' -or $identity.Version -ne [version]$Manifest.Version -or $identity.ProcessorArchitecture -notin @('Amd64','MSIL')){throw "Plugin sai danh tinh: $source"}
  if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.Sha256){throw "Plugin sai SHA256: $source"}
  $userBase="$UserRoot\Software\McNeel\Rhinoceros\$major.0\Plug-ins";$machineBase="HKEY_LOCAL_MACHINE\Software\McNeel\Rhinoceros\$major.0\Plug-ins"
  $machine=Reg-Exists "$machineBase\$script:PluginId";$base=if($machine){$machineBase}else{$userBase}
  $folder=if($machine){Join-Path $env:ProgramData 'PIStudio\Plugin'}else{$Destination}
  $target=Join-Path $folder "Rhino$major\$flavor\PISTUDIO.rhp"
  $keys=@("$userBase\$script:PluginId","$machineBase\$script:PluginId")
  foreach($id in $script:LegacyIds){foreach($root in @($userBase,$machineBase)){$key="$root\$id";if(Reg-Exists $key){$keys+=$key}}}
  $admin=$machine -or @($keys | Where-Object {$_ -like 'HKEY_LOCAL_MACHINE*' -and (Reg-Exists $_)}).Count -gt 0
  $plans+=[pscustomobject]@{Rhino=$major;RhinoVersion=[string]$hostInfo.Version;Exe=$hostInfo.Exe;Runtime=$flavor;RuntimeFix=$runtimeFix;RuntimeNote=$runtimeNote;Source=$source;Target=$target;Sha256=$entry.Sha256;Keys=$keys;RegisterKey="$base\$script:PluginId";NeedsAdmin=$admin}
 }
 return $plans
}
function Copy-PluginAtomic([string]$Source,[string]$Target,[string]$Hash){
 New-Item -ItemType Directory -Path (Split-Path $Target) -Force | Out-Null
 $temp=$Target+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{Copy-Item -LiteralPath $Source -Destination $temp;Unblock-File -LiteralPath $temp -ErrorAction SilentlyContinue
  if((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash -ne $Hash){throw 'Ban sao plugin khong dung SHA256.'}
  # Windows PowerShell 5.1 converts $null string parameters to "". Use an explicit
  # temporary backup path so replacing an existing installation remains atomic.
  if(Test-Path -LiteralPath $Target){[IO.File]::Replace($temp,$Target,($temp+'.old'))}else{[IO.File]::Move($temp,$Target)}
 }finally{foreach($file in @($temp,($temp+'.old'))){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force}}}
}
function Invoke-InstallTransaction($Plans,[string]$BackupRoot,[switch]$Uninstall){
 $backup=Join-Path $BackupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $backup -Force | Out-Null
 $registry=@();$binaries=@();$runtimeSettings=@();$changed=$false
 # Back up every selected version before modifying any of them.
 foreach($plan in $Plans){
  if(-not $Uninstall){foreach($fix in $plan.RuntimeFix){$previous=Reg-Value $fix.Key $fix.Name;if(-not @($runtimeSettings | Where-Object {$_.Key -eq $fix.Key -and $_.Name -eq $fix.Name}).Count){$runtimeSettings+=[pscustomobject]@{Key=$fix.Key;Name=$fix.Name;Existed=($null -ne $previous);Value=$previous}}}}
  foreach($key in $plan.Keys){if($Uninstall -and -not $key.EndsWith($script:PluginId)){continue};$existed=Reg-Exists $key;$file=Join-Path $backup ("reg-$($registry.Count).reg");if($existed){Reg-Export $key $file};$registry+=[pscustomobject]@{Key=$key;Existed=$existed;File=$file}}
  if(-not $Uninstall){$existed=Test-Path -LiteralPath $plan.Target;$file=Join-Path $backup ("Rhino$($plan.Rhino)-PISTUDIO.rhp");if($existed){Copy-Item -LiteralPath $plan.Target -Destination $file};$binaries+=[pscustomobject]@{Target=$plan.Target;Existed=$existed;File=$file}}
 }
 $runtimeSettings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backup 'runtime-before.json') -Encoding UTF8
 try{
  $changed=$true
  foreach($plan in $Plans){
   if(-not $Uninstall){Copy-PluginAtomic $plan.Source $plan.Target $plan.Sha256}
   foreach($key in $plan.Keys){if((-not $Uninstall -or $key.EndsWith($script:PluginId)) -and (Reg-Exists $key)){Reg-Delete $key}}
   if(-not $Uninstall){Reg-Register $plan.RegisterKey $plan.Target}
   if(-not $Uninstall){foreach($fix in $plan.RuntimeFix){Reg-WriteString $fix.Key $fix.Name $fix.Value;if((Reg-Value $fix.Key $fix.Name) -ne $fix.Value){throw 'Khong luu duoc cau hinh runtime Rhino.'}}}
  }
  [pscustomobject]@{Version='1.2.81';Uninstall=[bool]$Uninstall;Plans=$Plans;Registry=$registry;Binaries=$binaries;RuntimeSettings=$runtimeSettings;Completed=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backup 'installation.json') -Encoding UTF8
  return $backup
 }catch{
  $failure=$_;$rollback=@()
  if($changed){
   foreach($setting in $runtimeSettings){try{if($setting.Existed){Reg-WriteString $setting.Key $setting.Name $setting.Value}else{Reg-RemoveValue $setting.Key $setting.Name}}catch{$rollback+=$_.Exception.Message}}
   foreach($node in $registry){try{Reg-Delete $node.Key;if($node.Existed){Reg-Import $node.File}}catch{$rollback+=$_.Exception.Message}}
   foreach($binary in $binaries){try{if($binary.Existed){Copy-PluginAtomic $binary.File $binary.Target (Get-FileHash -LiteralPath $binary.File -Algorithm SHA256).Hash}elseif(Test-Path -LiteralPath $binary.Target){Remove-Item -LiteralPath $binary.Target -Force}}catch{$rollback+=$_.Exception.Message}}
  }
  if($rollback.Count){throw "Cai dat loi: $failure. KHOI PHUC CHUA XONG: $($rollback -join '; '). Ban sao luu: $backup"}
  throw "Cai dat loi; da khoi phuc tat ca Rhino: $failure. Ban sao luu: $backup"
 }
}
