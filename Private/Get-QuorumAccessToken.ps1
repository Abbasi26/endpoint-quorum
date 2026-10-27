Set-StrictMode -Version 1.0

function Get-QuorumAccessToken {
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [string]$CertificateThumbprint,
        [string]$CertificatePath,
        [securestring]$CertificatePassword,
        [string]$AuthorityHost = 'https://login.microsoftonline.com'
    )

    $permissions = Get-QuorumPermission
    $authority = $AuthorityHost.TrimEnd('/')
    $useCertificate = [bool]($CertificateThumbprint -or $CertificatePath)
    if ($useCertificate) {
        $certificate = Get-QuorumCertificate -Thumbprint $CertificateThumbprint -Path $CertificatePath -Password $CertificatePassword
        $assertion = New-QuorumClientAssertion -TenantId $TenantId -ClientId $ClientId -Certificate $certificate -AuthorityHost $authority
        $graph = Request-QuorumClientToken -Authority $authority -TenantId $TenantId -ClientId $ClientId -Assertion $assertion -Scope $permissions.GraphApplicationScope
        $defender = Request-QuorumClientToken -Authority $authority -TenantId $TenantId -ClientId $ClientId -Assertion $assertion -Scope $permissions.DefenderApplicationScope
        return @{ Graph = $graph; Defender = $defender }
    }

    Write-Host ''
    Write-Host 'Quorum will sign in twice: once for Microsoft Graph, then once for Defender for Endpoint.'
    Write-Host 'Both prompts are read-only. No write permission is requested.'
    Write-Host ''
    $graph = Request-QuorumDeviceCode -Authority $authority -TenantId $TenantId -ClientId $ClientId -Scope ($permissions.GraphDelegatedScopes -join ' ') -Title 'Microsoft Graph'
    $defender = Request-QuorumDeviceCode -Authority $authority -TenantId $TenantId -ClientId $ClientId -Scope ($permissions.DefenderDelegatedScopes -join ' ') -Title 'Defender for Endpoint'
    return @{ Graph = $graph; Defender = $defender }
}

function Request-QuorumClientToken {
    param($Authority, $TenantId, $ClientId, $Assertion, $Scope)
    $uri = "$Authority/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id             = $ClientId
        scope                 = $Scope
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        client_assertion      = $Assertion
        grant_type            = 'client_credentials'
    }
    $response = Invoke-RestMethod -Method POST -Uri $uri -Body $body -ContentType 'application/x-www-form-urlencoded'
    if (-not $response.access_token) { throw "Token endpoint did not return an access token for $Scope." }
    return [string]$response.access_token
}

function Request-QuorumDeviceCode {
    param($Authority, $TenantId, $ClientId, $Scope, $Title)
    $codeUri = "$Authority/$TenantId/oauth2/v2.0/devicecode"
    $tokenUri = "$Authority/$TenantId/oauth2/v2.0/token"
    $codeBody = @{ client_id = $ClientId; scope = $Scope }
    $code = Invoke-RestMethod -Method POST -Uri $codeUri -Body $codeBody -ContentType 'application/x-www-form-urlencoded'
    Write-Host ("Sign in for {0}" -f $Title)
    if ($code.message) { Write-Host $code.message }
    else { Write-Host ("Open {0} and enter {1}" -f $code.verification_uri, $code.user_code) }
    Write-Host ''

    $interval = 5
    if ($code.interval) { $interval = [int]$code.interval }
    if ($interval -lt 5) { $interval = 5 }
    $expires = 900
    if ($code.expires_in) { $expires = [int]$code.expires_in }
    $deadline = [datetime]::UtcNow.AddSeconds($expires)
    while ([datetime]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            $tokenBody = @{
                grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                client_id   = $ClientId
                device_code = [string]$code.device_code
            }
            $token = Invoke-RestMethod -Method POST -Uri $tokenUri -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'
            if ($token.access_token) { return [string]$token.access_token }
        }
        catch {
            $detail = ''
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = [string]$_.ErrorDetails.Message }
            else { $detail = [string]$_.Exception.Message }
            if ($detail -match 'authorization_pending') { continue }
            if ($detail -match 'slow_down') { $interval += 5; continue }
            throw
        }
    }
    throw "Sign-in for $Title timed out before the device code was approved."
}

function Get-QuorumCertificate {
    param([string]$Thumbprint, [string]$Path, [securestring]$Password)
    if ($Thumbprint -and $Path) { throw 'Use either -CertificateThumbprint or -CertificatePath, not both.' }
    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path)) { throw "Certificate file not found: $Path" }
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        }
        if ($Password) {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $plain = $null
            try {
                $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($resolved, $plain, $flags)
            }
            finally {
                $plain = $null
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
        else {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($resolved)
        }
    }
    else {
        $clean = ($Thumbprint -replace '\s', '').ToUpperInvariant()
        $stores = @('Cert:\CurrentUser\My', 'Cert:\LocalMachine\My')
        $found = $null
        foreach ($store in $stores) {
            if (-not (Test-Path -LiteralPath $store)) { continue }
            $found = Get-ChildItem -LiteralPath $store | Where-Object { $_.Thumbprint -and $_.Thumbprint.ToUpperInvariant() -eq $clean } | Select-Object -First 1
            if ($found) { break }
        }
        if (-not $found) {
            throw "No certificate with thumbprint $clean was found in the Windows certificate store. On macOS and Linux, use -CertificatePath."
        }
        $cert = $found
    }
    $key = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    if ($null -eq $key) { throw 'The certificate does not include a private key Quorum can use.' }
    return $cert
}

function New-QuorumClientAssertion {
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)]$Certificate,
        [Parameter(Mandatory = $true)][string]$AuthorityHost
    )
    $thumbBytes = ConvertFrom-QuorumHex $Certificate.Thumbprint
    $headerJson = '{"alg":"RS256","typ":"JWT","x5t":' + (ConvertTo-QuorumJsonString (ConvertTo-QuorumBase64Url $thumbBytes)) + '}'
    $epoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
    $now = [int64]([datetime]::UtcNow - $epoch).TotalSeconds
    $exp = $now + 600
    $aud = ConvertTo-QuorumJsonString ("$AuthorityHost/$TenantId/oauth2/v2.0/token")
    $iss = ConvertTo-QuorumJsonString $ClientId
    $jti = ConvertTo-QuorumJsonString ([guid]::NewGuid().ToString())
    $payloadJson = '{"aud":' + $aud + ',"iss":' + $iss + ',"sub":' + $iss + ',"jti":' + $jti + ',"nbf":' + $now + ',"exp":' + $exp + '}'
    $header = ConvertTo-QuorumBase64Url ([System.Text.Encoding]::UTF8.GetBytes($headerJson))
    $payload = ConvertTo-QuorumBase64Url ([System.Text.Encoding]::UTF8.GetBytes($payloadJson))
    $signingInput = [System.Text.Encoding]::ASCII.GetBytes("$header.$payload")
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    $signature = $rsa.SignData($signingInput, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    return "$header.$payload.$(ConvertTo-QuorumBase64Url $signature)"
}

function ConvertTo-QuorumBase64Url {
    param([byte[]]$Bytes)
    $text = [Convert]::ToBase64String($Bytes)
    return $text.TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-QuorumBase64Url {
    param([string]$Text)
    $padded = $Text.Replace('-', '+').Replace('_', '/')
    switch ($padded.Length % 4) {
        2 { $padded += '==' }
        3 { $padded += '=' }
        0 { }
        default { throw 'Invalid base64url value.' }
    }
    return [Convert]::FromBase64String($padded)
}

function ConvertFrom-QuorumHex {
    param([string]$Hex)
    $clean = ($Hex -replace '\s', '')
    if ($clean.Length % 2 -ne 0) { throw "Thumbprint is not valid hex: $Hex" }
    $bytes = New-Object byte[] ([int]($clean.Length / 2))
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($clean.Substring($i * 2, 2), 16)
    }
    return ,$bytes
}