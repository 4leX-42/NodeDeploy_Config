$ErrorActionPreference = 'Continue'
$logFile = 'C:\Users\user\Desktop\nodedeploy\NodeDeploy_Run\state\workdesktop_post_reboot.log'
Add-Content -Path $logFile -Value "=== Retest start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

$env:NODEDEPLOY_FORCE_IMANAGE = '1'
$skip = @(
    'AnyDesk','AqNet','Nebula CertAgent','ESET Management Agent',
    'Google Chrome','Autofirma','Bit4id Middleware',
    'PDFelement Business','MitelConnect',
    'Microsoft 365 Apps','MDR Cortex XDR',
    'iManage Agent Services','iManage Drive','iManage Drive Native'
)

try {
    & 'C:\Users\user\Desktop\nodedeploy\NodeDeploy_Run\PRO\Deploy.ps1' -Phase install -SkipApps $skip 2>&1 |
        Tee-Object -FilePath $logFile -Append
} catch {
    Add-Content -Path $logFile -Value "EXCEPTION: $_"
}

Add-Content -Path $logFile -Value "=== Retest end: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

# Delete the scheduled task self
schtasks.exe /Delete /TN 'NodeDeploy_WorkDesktop_PostReboot' /F 2>&1 | Add-Content -Path $logFile
