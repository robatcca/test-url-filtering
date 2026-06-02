#!/usr/bin/env pwsh
<#
.SYNOPSIS
    URL Filtering Test Harness for Windows environments.
    Tests if web filtering is in place by attempting to access URLs that SHOULD be blocked.

.DESCRIPTION
    This script tests a list of URLs (managed in urls.json) to verify web filtering is active.
    If a URL is NOT blocked (returns 2xx status), it displays an informational webpage.

.PARAMETER ConfigPath
    Path to the configuration file (urls.json). Defaults to script directory.

.PARAMETER TimeoutSeconds
    HTTP request timeout in seconds. Defaults to 10.

.PARAMETER Verbose
    Enable verbose output.

.EXAMPLE
    .\Test-URLFiltering.ps1
    .\Test-URLFiltering.ps1 -ConfigPath "C:\config\urls.json" -TimeoutSeconds 15 -Verbose

.NOTES
    Requires PowerShell 5.1+ or PowerShell 7+
    Tests are designed for security/compliance validation
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "urls.json"),
    
    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 10,
    
    [switch]$Verbose
)

$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }

# ── Configuration ────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path -Path $scriptDir -ChildPath "test-results.log"
$reportFile = Join-Path -Path $scriptDir -ChildPath "filter-report.html"

# ── Helper Functions ─────────────────────────────────────────────────────────

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "PASS", "FAIL")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
}

function Test-URLAccess {
    param(
        [string]$Url,
        [string]$Category,
        [int]$TimeoutSec
    )
    
    Write-Verbose "Testing URL: $Url (Category: $Category)"
    
    $result = @{
        Url        = $Url
        Category   = $Category
        Status     = "UNKNOWN"
        StatusCode = $null
        Blocked    = $false
        Timestamp  = Get-Date -Format "o"
        Exception  = $null
    }
    
    try {
        $response = Invoke-WebRequest -Uri $Url `
            -Method GET `
            -UseBasicParsing `
            -TimeoutSec $TimeoutSec `
            -ErrorAction Stop
        
        $result.StatusCode = $response.StatusCode
        $result.Status = "ACCESSIBLE"
        $result.Blocked = $false
        
        Write-Log "FAIL: $Url returned HTTP $($response.StatusCode) — NOT blocked!" "FAIL"
        
    }
    catch [System.Net.WebException] {
        # Check if it's a blocked response (403) or connection refused/timeout
        $webEx = $_.Exception
        
        if ($webEx.Response) {
            $statusCode = [int]$webEx.Response.StatusCode
            $result.StatusCode = $statusCode
            
            # 403 Forbidden typically indicates web filtering
            if ($statusCode -eq 403) {
                $result.Status = "BLOCKED (403 Forbidden)"
                $result.Blocked = $true
                Write-Log "PASS: $Url blocked with HTTP 403" "PASS"
            }
            else {
                $result.Status = "ACCESSIBLE (HTTP $statusCode)"
                $result.Blocked = $false
                Write-Log "FAIL: $Url returned HTTP $statusCode — NOT blocked!" "FAIL"
            }
        }
        else {
            # Connection error, timeout, or DNS failure — likely blocked
            $result.Status = "BLOCKED (Connection error)"
            $result.Blocked = $true
            $result.Exception = $webEx.Message
            Write-Log "PASS: $Url blocked (connection error: $($webEx.Message))" "PASS"
        }
    }
    catch [System.TimeoutException] {
        # Timeout may indicate blocking
        $result.Status = "BLOCKED (Timeout)"
        $result.Blocked = $true
        $result.Exception = "Request timeout after $TimeoutSec seconds"
        Write-Log "PASS: $Url blocked (timeout)" "PASS"
    }
    catch {
        # Other exceptions
        $result.Status = "ERROR"
        $result.Exception = $_.Exception.Message
        Write-Log "WARN: $Url error: $($_.Exception.Message)" "WARN"
    }
    
    return $result
}

function Load-Configuration {
    param([string]$Path)
    
    Write-Verbose "Loading configuration from: $Path"
    
    if (-not (Test-Path -Path $Path)) {
        Write-Log "Configuration file not found: $Path" "ERROR"
        throw "Configuration file not found: $Path"
    }
    
    try {
        $config = Get-Content -Path $Path -Encoding UTF8 -Raw | ConvertFrom-Json
        Write-Log "Loaded configuration with $($config.urls.Count) URL(s)" "INFO"
        return $config
    }
    catch {
        Write-Log "Failed to parse configuration: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Generate-HTMLReport {
    param(
        [array]$Results,
        [string]$OutputPath
    )
    
    $passCount = ($Results | Where-Object { $_.Blocked -eq $true } | Measure-Object).Count
    $failCount = ($Results | Where-Object { $_.Blocked -eq $false } | Measure-Object).Count
    $totalCount = $Results.Count
    $passPercentage = if ($totalCount -gt 0) { [math]::Round(($passCount / $totalCount) * 100, 1) } else { 0 }
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>URL Filtering Test Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 2rem;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem;
            text-align: center;
        }
        .header h1 {
            font-size: 2rem;
            margin-bottom: 0.5rem;
        }
        .header p {
            opacity: 0.9;
            font-size: 0.95rem;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 1rem;
            padding: 2rem;
            background: #f8f9fa;
            border-bottom: 1px solid #e9ecef;
        }
        .summary-card {
            text-align: center;
            padding: 1rem;
            background: white;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }
        .summary-card.pass {
            border-left-color: #28a745;
        }
        .summary-card.fail {
            border-left-color: #dc3545;
        }
        .summary-card.total {
            border-left-color: #667eea;
        }
        .summary-card .value {
            font-size: 1.8rem;
            font-weight: bold;
            color: #333;
        }
        .summary-card .label {
            font-size: 0.85rem;
            color: #6c757d;
            margin-top: 0.5rem;
        }
        .content {
            padding: 2rem;
        }
        .results-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 1rem;
        }
        .results-table thead {
            background: #f8f9fa;
            border-bottom: 2px solid #dee2e6;
        }
        .results-table th {
            padding: 1rem;
            text-align: left;
            font-weight: 600;
            color: #495057;
            font-size: 0.9rem;
        }
        .results-table td {
            padding: 1rem;
            border-bottom: 1px solid #dee2e6;
        }
        .results-table tbody tr:hover {
            background: #f8f9fa;
        }
        .status-badge {
            display: inline-block;
            padding: 0.4rem 0.8rem;
            border-radius: 4px;
            font-size: 0.85rem;
            font-weight: 600;
        }
        .status-badge.blocked {
            background: #d4edda;
            color: #155724;
        }
        .status-badge.accessible {
            background: #f8d7da;
            color: #721c24;
        }
        .status-badge.error {
            background: #fff3cd;
            color: #856404;
        }
        .url-cell {
            word-break: break-all;
            font-family: 'Courier New', monospace;
            font-size: 0.9rem;
        }
        .category-badge {
            display: inline-block;
            background: #e7f3ff;
            color: #004085;
            padding: 0.3rem 0.6rem;
            border-radius: 3px;
            font-size: 0.8rem;
        }
        .warning {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 1rem;
            margin: 1rem 0;
            border-radius: 4px;
            color: #856404;
        }
        .footer {
            background: #f8f9fa;
            padding: 1rem 2rem;
            border-top: 1px solid #dee2e6;
            color: #6c757d;
            font-size: 0.85rem;
            text-align: center;
        }
        @media (prefers-color-scheme: dark) {
            body {
                background: #1a1a1a;
            }
            .container {
                background: #2d2d2d;
                color: #e0e0e0;
            }
            .header p {
                color: #b0b0b0;
            }
            .summary {
                background: #1a1a1a;
                border-bottom-color: #444;
            }
            .summary-card {
                background: #3d3d3d;
                color: #e0e0e0;
            }
            .summary-card .label {
                color: #999;
            }
            .content {
                color: #e0e0e0;
            }
            .results-table thead {
                background: #3d3d3d;
                border-bottom-color: #555;
            }
            .results-table th {
                color: #b0b0b0;
            }
            .results-table td {
                border-bottom-color: #444;
            }
            .results-table tbody tr:hover {
                background: #3d3d3d;
            }
            .footer {
                background: #3d3d3d;
                border-top-color: #555;
                color: #999;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔒 URL Filtering Test Report</h1>
            <p>Web filtering compliance validation</p>
        </div>
        
        <div class="summary">
            <div class="summary-card pass">
                <div class="value">$passCount</div>
                <div class="label">URLs Blocked</div>
            </div>
            <div class="summary-card fail">
                <div class="value">$failCount</div>
                <div class="label">URLs NOT Blocked</div>
            </div>
            <div class="summary-card total">
                <div class="value">$totalCount</div>
                <div class="label">Total URLs Tested</div>
            </div>
            <div class="summary-card total">
                <div class="value">$passPercentage%</div>
                <div class="label">Pass Rate</div>
            </div>
        </div>
        
        <div class="content">
"@
    
    if ($failCount -gt 0) {
        $html += @"
            <div class="warning">
                <strong>⚠️  Warning:</strong> $failCount URL(s) were NOT blocked by the filter. These should be investigated.
            </div>
"@
    }
    
    $html += @"
            <h2 style="font-size: 1.25rem; margin-bottom: 1rem; color: #333;">Test Results</h2>
            <table class="results-table">
                <thead>
                    <tr>
                        <th>URL</th>
                        <th>Category</th>
                        <th>Status</th>
                        <th>HTTP Code</th>
                        <th>Timestamp</th>
                    </tr>
                </thead>
                <tbody>
"@
    
    foreach ($result in $Results) {
        $statusClass = if ($result.Blocked) { "blocked" } elseif ($result.Status -eq "ERROR") { "error" } else { "accessible" }
        $statusText = if ($result.Blocked) { "✓ Blocked" } elseif ($result.Status -eq "ERROR") { "⚠ Error" } else { "✗ Accessible" }
        $httpCode = if ($result.StatusCode) { $result.StatusCode } else { "N/A" }
        
        $html += @"
                    <tr>
                        <td class="url-cell">$([System.Net.WebUtility]::HtmlEncode($result.Url))</td>
                        <td><span class="category-badge">$([System.Net.WebUtility]::HtmlEncode($result.Category))</span></td>
                        <td><span class="status-badge $statusClass">$statusText</span></td>
                        <td>$httpCode</td>
                        <td>$($result.Timestamp.Substring(0, 19))</td>
                    </tr>
"@
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <p>Report generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | URL Filtering Test Harness</p>
        </div>
    </div>
</body>
</html>
"@
    
    Set-Content -Path $OutputPath -Value $html -Encoding UTF8
    Write-Log "HTML report generated: $OutputPath" "INFO"
}

# ── Main ─────────────────────────────────────────────────────────────────────

function Main {
    Write-Log "========================================" "INFO"
    Write-Log "URL Filtering Test Harness" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "Configuration: $ConfigPath" "INFO"
    Write-Log "Timeout: $TimeoutSeconds seconds" "INFO"
    Write-Log "" "INFO"
    
    try {
        # Load configuration
        $config = Load-Configuration -Path $ConfigPath
        
        # Test all URLs
        $results = @()
        foreach ($urlEntry in $config.urls) {
            $result = Test-URLAccess -Url $urlEntry.url -Category $urlEntry.category -TimeoutSec $TimeoutSeconds
            $results += $result
        }
        
        Write-Log "" "INFO"
        
        # Generate report
        $passCount = ($results | Where-Object { $_.Blocked -eq $true } | Measure-Object).Count
        $failCount = ($results | Where-Object { $_.Blocked -eq $false } | Measure-Object).Count
        
        Write-Log "========================================" "INFO"
        Write-Log "Summary: $passCount passed, $failCount failed" "INFO"
        Write-Log "========================================" "INFO"
        
        # Generate HTML report
        Generate-HTMLReport -Results $results -OutputPath $reportFile
        
        # Return exit code based on results
        if ($failCount -eq 0) {
            Write-Log "All tests passed! Opening report..." "PASS"
            Start-Process $reportFile
            return 0
        }
        else {
            Write-Log "Some tests failed! Opening report..." "FAIL"
            Start-Process $reportFile
            return 1
        }
    }
    catch {
        Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
        return 1
    }
}

# Run main
$exitCode = Main
exit $exitCode
