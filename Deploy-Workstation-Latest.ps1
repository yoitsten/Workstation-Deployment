$Config = @{
	ComputerName = "LI-PC02"
	DomainName = "leeindustries.test"
	IPAddress = "10.77.10.102"
	PrefixLength = 24
	Gateway = "10.77.10.1"
	DnsServer = "10.77.10.10"
	InterfaceAlias = "Ethernet"
}

$RestartRequired = $false

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

$IsAdmin = $Principal.IsInRole(
	[Security.Principal.WindowsBuiltInRole]::Administrator
)

if ($IsAdmin -eq $true) {
	Write-Host "Administrator Privileges confirmed"
}
else {
	Write-Host "ERROR: Run this script as Administrator"
	exit 1
}

$LogDirectory = Join-Path $PSScriptRoot "Logs"
New-Item -ItemType Directory -Path $LogDirectory -Force -ErrorAction Stop | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$FileName = "Deploy-Workstation_$Timestamp.log"
$LogPath = Join-Path -Path $LogDirectory -ChildPath $FileName

Start-Transcript -Path $LogPath -ErrorAction Stop

try {

if ([string]::IsNullOrWhiteSpace($Config.ComputerName)) {
	Write-Host "ERROR: Computer name cannot be empty"
	exit 1
}

if ($Config.ComputerName.Length -gt 15){
	Write-Host "ERROR: Desired computer name length is too long"
	exit 1
}

if ($Config.ComputerName -match '[^a-zA-Z0-9-]' -or $Config.ComputerName -match '^[-]|[-]$'){
	Write-Host "ERROR: Computer name contains invalid characters"
	exit 1
}

if ($Config.ComputerName -match '^[0-9]+$'){
	Write-Host "ERROR: Computer name cannot be all numbers"
	exit 1
}

if ([string]::IsNullOrWhiteSpace($Config.DomainName)){
	Write-Host "ERROR: Domain name cannot be empty"
	exit 1
}

if ($Config.DomainName -match '[^a-zA-Z0-9.-]' -or $Config.DomainName -match '^[-]|[-]$'){
	Write-Host "ERROR: Domain name contains invalid characters"
	exit 1
}

if ($Config.DomainName -match '^[.]|[.]$|[.]{2}' -or $Config.DomainName -match '-\.|\.-' -or $Config.DomainName -notmatch '\.') {
	Write-Host "ERROR: Domain name has invalid formatting"
	exit 1
}

foreach ($Label in $Config.DomainName.Split(".")){
	if ($Label.Length -gt 63){
		Write-Host "ERROR: Domain label exceeds maximum character length"
		exit 1
	}
}

if ($Config.DomainName.Length -gt 253){
	Write-Host "ERROR: Domain name exceeds maximum character length"
	exit 1
}

$ParsedIP = $null

if (-not [System.Net.IPAddress]::TryParse(
	$Config.IPAddress,
	[ref]$ParsedIP
)) {
	Write-Host "ERROR: Invalid IP Address"
	exit 1
}

if ($ParsedIP.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
	Write-Host "ERROR: Only IPv4 addresses are supported."
	exit 1
}

if ($ParsedIP.ToString() -ne $Config.IPAddress) {
    Write-Host "ERROR: IP address must use standard IPv4 notation"
    exit 1
}

if ($Config.PrefixLength -isnot [int] -or $Config.PrefixLength -lt 1 -or $Config.PrefixLength -gt 30) {
	Write-Host "ERROR: Invalid IPv4 prefix length"
	exit 1
}

foreach ($Setting in @("Gateway", "DnsServer")) {
	$Address = $Config[$Setting]
	$ParsedAddress = $null
	
	if (-not [System.Net.IPAddress]::TryParse(
		$Address,[ref]$ParsedAddress
	)){
		Write-Host "ERROR: Invalid $Setting"
		exit 1
	}

	if ($ParsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
		Write-Host "ERROR: Only IPv4 addresses are supported for $Setting"
		exit 1
	}

	if ($ParsedAddress.ToString() -ne $Address){
		Write-Host "ERROR: $Setting must use standard IPv4 notation"
		exit 1
	}

	if ($Setting -eq "DnsServer"){
		if ($Address -eq "0.0.0.0" -or $Address -eq "255.255.255.255"){
			Write-Host "ERROR: Invalid DnsServer Address"
			exit 1
		}
	}
}

$IPBytes = $ParsedIP.GetAddressBytes()

$GatewayBytes = [System.Net.IPAddress]::Parse($Config.Gateway).GetAddressBytes()

$SubnetMask = @()
$RemainingBits = $Config.PrefixLength

for ($Octet = 0; $Octet -lt 4; $Octet++) {
    $BitsToKeep = [Math]::Min(8, [Math]::Max(0, $RemainingBits))
    $MaskByte = (255 -shl (8 - $BitsToKeep)) -band 255

    $SubnetMask += $MaskByte
    $RemainingBits -= 8
}

for ($Octet= 0; $Octet -lt 4; $Octet++) {
	$IPMask = $IPBytes[$Octet] -band $SubnetMask[$Octet] 
	$GatewayMask = $GatewayBytes[$Octet] -band $SubnetMask[$Octet]

	if ($IPMask -ne $GatewayMask) {
		Write-Host "ERROR: Gateway is outside the workstation subnet"
		exit 1
	}
}

$NetworkBytes = @()
$BroadcastBytes = @()

for ($Octet = 0; $Octet -lt 4; $Octet++){
	$NetworkBytes += $IPBytes[$Octet] -band $SubnetMask[$Octet]
	$BroadcastBytes += $NetworkBytes[$Octet] + (255 - $SubnetMask[$Octet])
}

$NetworkAddress = $NetworkBytes -join "."
$BroadcastAddress = $BroadcastBytes -join "."

if ($NetworkAddress -eq $Config.Gateway -or $BroadcastAddress -eq $Config.Gateway){
	Write-Host "ERROR: Gateway cannot be the Network Address or Broadcast Address of the desired subnet"
	exit 1
}

if ($Config.IPAddress -eq $Config.Gateway){
	Write-Host "ERROR: IP Address cannot match the Default Gateway"
	exit 1
}

if ($NetworkAddress -eq $Config.IPAddress -or $BroadcastAddress -eq $Config.IPAddress){
	Write-Host "ERROR: IP Address cannot be the Network Address or Broadcast Address of the desired subnet"
	exit 1
}

$CurrentName = hostname

if ($CurrentName -ne $Config.ComputerName) {
	Write-Host "Computer name needs to be changed"
}
else {
	Write-Host "Computer name is correct"
}

$IPInterface = Get-NetIPInterface `
	-InterfaceAlias $Config.InterfaceAlias `
	-AddressFamily IPv4 `
	-ErrorAction Stop

$CurrentIP = @(
		Get-NetIPAddress `
		-AddressFamily IPv4 `
		-ErrorAction Stop | 
		Where-Object {$_.InterfaceIndex -eq $IPInterface.InterfaceIndex}
)

$ComputerSystem = Get-CimInstance `
	-ClassName Win32_ComputerSystem `
	-ErrorAction Stop

if ($ComputerSystem.PartOfDomain -and $ComputerSystem.Domain -ne $Config.DomainName) {
	Write-Host "ERROR: Computer belongs to a different domain. Manual review required."
	exit 1
}

if ( $IPInterface.Dhcp -eq "enabled" ) {
	Write-Host "DHCP is enabled"
	Write-Host "Interface is eligible for automatic DHCP-to-Static conversion"
}
else {
	Write-Host "DHCP is disabled"
}


$MatchingIP = $CurrentIP | Where-Object { $_.IPAddress -eq $Config.IPAddress } 

$CandidateIPsToRemove = $CurrentIP | Where-Object {
	$_.IPAddress -ne $Config.IPAddress
}

if ( @($CandidateIPsToRemove).count -gt 0 ) {
	Write-Host "IP Addresses require review"
}
else {
	Write-Host "No additional IP Addresses found"
}

$ManualIPFound = $False

foreach ( $IP in $CandidateIPsToRemove ) {
	Write-Host "Found candidate IP:" $IP.IPAddress
	Write-Host "Prefix Length:" $IP.PrefixLength
	Write-Host "Prefix Origin:" $IP.PrefixOrigin

	if ( $IP.PrefixOrigin -eq "Manual" ) {
		$ManualIPFound = $True
	}
}

if ($ManualIPFound) {
	Write-Host "ERROR: Existing manual IP detected. Replacement is not supported in Version 1."
	exit 1
}

if ($null -ne $MatchingIP -and $MatchingIP.PrefixLength -ne $Config.PrefixLength) {
	Write-Host "ERROR: Existing IP has an incorrect prefix length. Modification is not supported in Version 1."
	exit 1
}

if ($IPInterface.Dhcp -eq "Disabled" -and $null -eq $MatchingIP -and @($CandidateIPsToRemove).count -gt 0 ) {
	Write-Host "ERROR: Existing IPv4 addresses require review."
	exit 1
}

if ($null -ne $MatchingIP -and $MatchingIP.PrefixLength -eq $Config.PrefixLength) {
	if ($IPInterface.Dhcp -eq "Enabled" -and $MatchingIP.PrefixOrigin -eq "Dhcp") {
		Write-Host "Desired IP exists, but DHCP-To-Static conversion is required"

		Set-NetIPInterface `
		-InterfaceAlias $Config.InterfaceAlias `
		-AddressFamily IPv4 `
		-Dhcp Disabled `
		-ErrorAction Stop

		Write-Host "DHCP disabled. Rechecking desired IP address configuration"
		
		$IPAfterDHCP = @(
			Get-NetIPAddress `
			-AddressFamily IPv4 `
			-ErrorAction Stop |
			Where-Object { $_.InterfaceIndex -eq $IPInterface.InterfaceIndex -and 
				$_.IPAddress -eq $Config.IPAddress }
		)

		if ($IPAfterDHCP.Count -eq 0) {
			Write-Host "DHCP address removed. Assigning static IP."
		}
		elseif ($IPAfterDHCP.Count -eq 1 -and $IPAfterDHCP[0].PrefixOrigin -eq "Dhcp") {
			Write-Host "DHCP address remains. Removing existing lease address."

			$IPAfterDHCP[0] | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
		}
		else {
			Write-Host "ERROR: Unexpected IP configuration after disabling DHCP"
			exit 1
		}

		New-NetIPAddress `
		-InterfaceAlias $Config.InterfaceAlias `
		-IPAddress $Config.IPAddress `
		-PrefixLength $Config.PrefixLength `
		-ErrorAction Stop
	}
	elseif ($IPInterface.Dhcp -eq "Disabled" -and $MatchingIP.PrefixOrigin -eq "Manual") {
		Write-Host "IP Address and Prefix Length are correct; DHCP is disabled"
	}
	else {
		Write-Host "ERROR: Configuration is not supported"
		exit 1
	}
}
else {
	Write-Host "Assigning desired static IP address"

	New-NetIPAddress `
	-InterfaceAlias $Config.InterfaceAlias `
	-IPAddress $Config.IPAddress `
	-PrefixLength $Config.PrefixLength `
	-ErrorAction Stop
}

$VerifiedIP = @(
	Get-NetIPAddress `
	-InterfaceAlias $Config.InterfaceAlias `
	-AddressFamily IPv4 `
	-ErrorAction Stop |
	Where-Object { $_.IPAddress -eq $Config.IPAddress }
)

$VerifiedInterface = Get-NetIPInterface `
	-InterfaceAlias $Config.InterfaceAlias `
	-AddressFamily IPv4 `
	-ErrorAction Stop

if ($VerifiedIP.Count -eq 1 -and $VerifiedIP[0].PrefixLength -eq $Config.PrefixLength -and $VerifiedIP[0].PrefixOrigin -eq "Manual" -and $VerifiedInterface.Dhcp -eq "Disabled") {
	Write-Host "Static IP configuration verified successfully"
}
else {
	Write-Host "ERROR: Static IP configuration verification failed"
	exit 1
}
		
$DefaultRoutes = @( 
	Get-NetRoute `
	-InterfaceAlias $Config.InterfaceAlias `
	-AddressFamily IPv4 `
	-ErrorAction Stop |
	Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0"}
)

$LowestMetric = $null

$LowestMetricGateway = @()

foreach ( $Route in $DefaultRoutes ) {
	if ( $Route.NextHop -eq $Config.Gateway ) {
		Write-Host "Desired Gateway Detected:" $Route.NextHop
	}
	else {
		Write-Host "Unexpected gateway detected:" $Route.NextHop
	}

	Write-Host "Route Metric:" $Route.RouteMetric
	Write-Host "Interface Index:" $Route.InterfaceIndex

	$Interface = Get-NetIPInterface -InterfaceIndex $Route.InterfaceIndex -AddressFamily IPv4

	$EffectiveMetric = $Route.RouteMetric + $Interface.InterfaceMetric
	Write-Host "Effective Route Metric:" $EffectiveMetric
	
	if ($null -eq $LowestMetric -or $EffectiveMetric -lt $LowestMetric) {
		$LowestMetric = $EffectiveMetric
		$LowestMetricGateway = @($Route.NextHop)
	}
	elseif ( $LowestMetric -eq $EffectiveMetric ) {
		$LowestMetricGateway += $Route.NextHop
	}
	Write-Host ""
}

if ($LowestMetricGateway.Count -eq 0) {
    Write-Host "No default routes found on configured interface"
}
else {
    if ($LowestMetricGateway.Count -gt 1) {
        Write-Host "Multiple routes share the lowest metric"
    }

    if ($LowestMetricGateway -contains $Config.Gateway) {
        Write-Host "Desired gateway is among the lowest-metric routes"
    }
    else {
        Write-Host "Desired gateway is not among the lowest-metric routes"
    }
}

$CurrentGateway = $DefaultRoutes | Where-Object { $_.NextHop -eq $Config.Gateway }

if ($DefaultRoutes.Count -ge 1 -and $null -eq $CurrentGateway) {
	Write-Host "ERROR: Exisiting default routes do not match the desired gateway"
	exit 1
}
elseif ($DefaultRoutes.Count -eq 0 -and $null -eq $CurrentGateway) {
	Write-Host "Gateway is not configured. Assigning desired gateway."

	New-NetRoute `
	-InterfaceAlias $Config.InterfaceAlias `
	-DestinationPrefix "0.0.0.0/0" `
	-NextHop $Config.Gateway `
	-ErrorAction Stop

	Write-Host "Desired gateway assginment is successful"
}
elseif ($DefaultRoutes.Count -eq 1 -and $null -ne $CurrentGateway) {
	Write-Host "Desired gateway already configured"
}
else {
	Write-Host "ERROR: Gateway configuration is not supported in Version 1"
	exit 1
}

$VerifiedRoutes = @( 
	Get-NetRoute `
	-InterfaceAlias $Config.InterfaceAlias `
	-AddressFamily IPv4 `
	-ErrorAction Stop |
	Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0"}
)

if ($VerifiedRoutes.Count -eq 1 -and $VerifiedRoutes[0].NextHop -eq $Config.Gateway) {
	Write-Host "Default gateway configuration verified successfully"
}
else {
	Write-Host "Default gateway verification failed"
	exit 1
}

$CurrentDNS = Get-DnsClientServerAddress `
	-InterfaceAlias $Config.InterfaceAlias `
	-AddressFamily IPv4 `
	-ErrorAction Stop	

if (@($CurrentDNS.ServerAddresses).Count -eq 1 -and $CurrentDNS.ServerAddresses -contains $Config.DnsServer) {
	Write-Host "DNS configuration is correct"
}
else {
	Write-Host "DNS configuration requires modification. Assigning desired DNS server"

	Set-DnsClientServerAddress `
	-InterfaceAlias $Config.InterfaceAlias `
	-ServerAddresses $Config.DnsServer `
	-ErrorAction Stop

	Write-Host "DNS configuration command completed"
}

$VerifiedDNS = Get-DnsClientServerAddress `
	-InterfaceAlias $Config.InterfaceAlias `
	-AddressFamily IPv4 `
	-ErrorAction Stop

if (@($VerifiedDNS.ServerAddresses).Count -eq 1 -and $VerifiedDNS.ServerAddresses -contains $Config.DnsServer) {
	Write-Host "DNS server verified successfully"
}
else {
	Write-Host "ERROR: DNS server verification failed"
	exit 1
}

$DNSReachable = $false
$MaxAttempts = 3

for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
	Write-Host "Testing DNS TCP Connectivity. Attempt $Attempt of $MaxAttempts"

	$DNSReachable = Test-NetConnection `
	-ComputerName $Config.DnsServer `
	-Port 53 `
	-InformationLevel Quiet `
	-WarningAction SilentlyContinue

	if ($DNSReachable) {
		Write-Host "DNS server TCP connectivity verified successfully"
		break
	}
	
	if ($Attempt -lt $MaxAttempts) {
		Write-Host "Connection failed. Retrying..."
		Start-Sleep -Seconds 3
	}
}

if (-not $DNSReachable) {
	Write-Host "ERROR: DNS Server unreachable after $MaxAttempts attempts"
	exit 1
}

$VerifiedDNSQuery = [bool](
	Resolve-DnsName `
	-Name "LI-DC01.$($Config.DomainName)" `
	-Type A `
	-Server $Config.DnsServer `
	-DnsOnly `
	-ErrorAction SilentlyContinue |
	Where-Object {$_.Section -eq 'Answer' -and $_.IPAddress -eq $Config.DnsServer}
)

$VerifiedADQuery = [bool](
	Resolve-DnsName `
	-Name "_ldap._tcp.dc._msdcs.$($Config.DomainName)" `
	-Type SRV `
	-Server $Config.DnsServer `
	-DnsOnly `
	-ErrorAction SilentlyContinue |
	Where-Object {$_.Section -eq 'Answer' -and $_.Type -eq "SRV"}
)

if ($VerifiedDNSQuery) {
	Write-Host "DNS query verification is successful"
}
else {
	Write-Host "ERROR: DNS query verification failed"
	exit 1
}

if ($VerifiedADQuery) {
	Write-Host "AD Query verification is successful"
}
else {
	Write-Host "ERROR: AD Query verification failed"
	exit 1
}

$CredentialsRequired = (
	-not $ComputerSystem.PartOfDomain -or 
	(
		$ComputerSystem.Domain -eq $Config.DomainName -and $CurrentName -ne $Config.ComputerName
	)
)

if ($CredentialsRequired) {
	$DomainCredential = Get-Credential -ErrorAction Stop
	
	if ($null -eq $DomainCredential) {
		Write-Host "ERROR: Domain Credentials could not be retrieved"
		exit 1
	}
}

if ($ComputerSystem.PartOfDomain) {
	Write-Host "Computer is already domain joined"

	if ($ComputerSystem.Domain -eq $Config.DomainName) {
		Write-Host "Computer is already joined to the correct domain"
		
		if ($CurrentName -ne $Config.ComputerName) {
			Write-Host "Computer is domain joined but requires renaming"

			Rename-Computer `
			-NewName $Config.ComputerName `
			-DomainCredential $DomainCredential `
			-ErrorAction Stop

			$RestartRequired = $True
		}
		else {
			Write-Host "Computer name and domain membership are correct"
			
			$SecureChannelOK = Test-ComputerSecureChannel -ErrorAction Stop
			if ($SecureChannelOK) {
				Write-Host "Active Directory secure channel verified successfully"
			}
			else {
				Write-Host "ERROR: Active Directory secure channel verification failed"
				exit 1
			}
		}
	}
	else {
		Write-Host "ERROR: Computer belongs to a different domain. Manual review required."
		exit 1
	}
}
else {
	Write-Host "Computer is currently in a workgroup"
	
	if ($CurrentName -ne $Config.ComputerName) {
		Add-Computer `
		-DomainName $Config.DomainName `
		-Credential $DomainCredential `
		-NewName $Config.ComputerName `
		-ErrorAction Stop

	}
	else {
		Add-Computer `
		-DomainName $Config.DomainName `
		-Credential $DomainCredential `
		-ErrorAction Stop
	}
	
	$RestartRequired = $True
}

if ($RestartRequired) {
	Write-Host "Domain or hostname changes require a restart."
	Write-Host "Restart the workstation, then rerun the script to verify deployment."
}
else {
	Write-Host "No restart required."
}
}
catch {
	Write-Host "ERROR: Unexpected deployment failure:" $_.Exception.Message
	exit 1
}
finally {
	Stop-Transcript -ErrorAction Stop
}