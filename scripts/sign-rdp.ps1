<#
    sign-rdp.ps1 -- remove the "Unknown publisher / unknown remote connection"
    warning from the loopback .rdp by signing it with your own trusted cert.

    Creates a code-signing certificate in YOUR user store, trusts it (CurrentUser
    Root + TrustedPublisher), and saves its thumbprint to
    C:\Users\Public\apollo-s2\rdp-sign.thumb. session-up.ps1 then signs each .rdp
    it generates with rdpsign, so mstsc sees a trusted publisher and skips the
    warning.

    Runs as your normal user (no elevation) -- it only touches YOUR certificate
    stores. Reversible: delete the cert from certmgr.msc and the .thumb file.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$subject = 'CN=sunshine-dual RDP loopback'
$cert = Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $subject } | Select-Object -First 1
if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $subject `
        -CertStoreLocation Cert:\CurrentUser\My -KeyUsage DigitalSignature `
        -NotAfter (Get-Date).AddYears(10)
    Write-Host "[sign] created code-signing cert ($($cert.Thumbprint))."
} else {
    Write-Host "[sign] reusing existing cert ($($cert.Thumbprint))."
}

# Trust it for the current user so signed .rdp files are recognized.
$tmp = Join-Path $env:TEMP 'sd-rdp-signcert.cer'
Export-Certificate -Cert $cert -FilePath $tmp -Force | Out-Null
Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\CurrentUser\TrustedPublisher | Out-Null
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
Write-Host "[sign] trusted the cert (CurrentUser Root + TrustedPublisher)."

$thumbFile = Join-Path $SD_InstanceDir 'rdp-sign.thumb'
New-Item -ItemType Directory -Force -Path $SD_InstanceDir | Out-Null
$cert.Thumbprint | Set-Content $thumbFile -NoNewline
Write-Host "[sign] saved thumbprint to $thumbFile"
Write-Host "       session-up.ps1 will sign its .rdp with it from now on."
Write-Host "`nPress Enter to close..."
[void][System.Console]::ReadLine()
