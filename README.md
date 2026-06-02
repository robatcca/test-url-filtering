# URL Filtering Test Harness

A PowerShell-based command-line test harness for validating URL web filtering on Windows environments. Tests a configurable set of URLs that SHOULD be blocked by security filters; if any are accessible, generates an informational HTML report.

**Status:** Active  
**Platforms:** Windows 10+, Windows Server 2016+  
**PowerShell Version:** 5.1+ or 7.0+

---

## Features

- ✅ **Automated URL Testing** — Tests multiple URLs for web filtering compliance
- ✅ **HTTP Status Detection** — Distinguishes between 403 Forbidden, timeouts, and connection errors
- ✅ **HTML Reporting** — Beautiful, responsive report with summary statistics
- ✅ **Logging** — Detailed log file (`test-results.log`) for audit trails
- ✅ **Configuration-Driven** — Easy-to-update URL list in `urls.json`
- ✅ **Exit Codes** — Returns 0 on success, 1 on failures (automation-friendly)
- ✅ **Timeout Handling** — Configurable request timeout for slow networks

---

## Installation

### Prerequisites

- Windows 10 or Windows Server 2016+
- PowerShell 5.1 (built-in) or PowerShell 7+ (recommended)
- Internet connectivity
- Administrator privileges (not required, but recommended for full logging)

### Clone the Repository

```bash
git clone https://github.com/robatcca/test-url-filtering.git
cd test-url-filtering
```

---

## Quick Start

### Run All Tests

```powershell
.\Test-URLFiltering.ps1
```

This will:
1. Load the test URLs from `urls.json`
2. Test each URL (10-second timeout by default)
3. Log results to `test-results.log`
4. Generate an HTML report: `filter-report.html`
5. Open the report in your default browser

### Customize Timeout

```powershell
.\Test-URLFiltering.ps1 -TimeoutSeconds 15
```

### Run with Verbose Output

```powershell
.\Test-URLFiltering.ps1 -Verbose
```

### Use Custom Configuration

```powershell
.\Test-URLFiltering.ps1 -ConfigPath "C:\config\custom-urls.json"
```

---

## Configuration

### Edit `urls.json`

Add or modify test URLs in `urls.json`:

```json
{
  "urls": [
    {
      "url": "https://example.com/blocked-content",
      "category": "Malware",
      "shouldBeBlocked": true
    },
    {
      "url": "https://another-test.com",
      "category": "Phishing",
      "shouldBeBlocked": true
    }
  ]
}
```

**Fields:**
- `url` — The URL to test (required)
- `category` — Human-readable category (required)
- `shouldBeBlocked` — Whether this URL should be blocked (documentation only)

---

## Report Output

The script generates two outputs:

### 1. Log File (`test-results.log`)

Plain-text log with timestamps:

```
[2026-06-02 14:30:15] [INFO] URL Filtering Test Harness
[2026-06-02 14:30:15] [INFO] Loaded configuration with 6 URL(s)
[2026-06-02 14:30:16] [PASS] https://urlfiltering.paloaltonetworks.com/test-adult blocked (connection error)
[2026-06-02 14:30:17] [FAIL] https://urlfiltering.paloaltonetworks.com/test-grayware returned HTTP 200 — NOT blocked!
```

### 2. HTML Report (`filter-report.html`)

Visual report with:
- Summary cards (Blocked, Not Blocked, Total, Pass Rate)
- Detailed results table
- Warning section if any URLs were not blocked
- Dark mode support
- Responsive design for mobile/tablet viewing

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All URLs passed (were blocked or handled as expected) |
| `1` | One or more URLs failed (were NOT blocked) or error occurred |

Use this for automation:

```powershell
.\Test-URLFiltering.ps1
if ($LASTEXITCODE -eq 0) {
    Write-Host "All filters working correctly"
} else {
    Write-Host "Filter issues detected!" -ForegroundColor Red
}
```

---

## Interpreting Results

### ✅ BLOCKED Status

The URL was successfully blocked by the web filter. This is expected behavior.

**Indications:**
- HTTP 403 Forbidden
- Connection timeout
- Connection refused (ERR_CONNECTION_RESET)
- DNS failure

### ❌ ACCESSIBLE Status

The URL was **NOT blocked** and returned an HTTP 2xx status code (200, 204, etc.). This indicates the filter may not be working for this URL category.

**Action Required:**
1. Check web filter configuration
2. Verify the filter rule applies to your network segment
3. Test manually to confirm accessibility
4. Review filter logs on the security appliance

---

## Usage Examples

### Scheduled Task (Windows Task Scheduler)

Create a scheduled task to run tests daily:

```powershell
# Create a trigger for 6 AM daily
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File 'C:\tools\test-url-filtering\Test-URLFiltering.ps1'"

$trigger = New-ScheduledTaskTrigger -Daily -At 6am

$task = Register-ScheduledTask -TaskName "URLFilterTest" `
  -Action $action -Trigger $trigger -RunLevel Highest

# Run the task manually
Start-ScheduledTask -TaskName "URLFilterTest"
```

### Group Policy / SCCM Deployment

Save the script and configuration to a shared drive, then deploy via SCCM package:

```batch
REM Run from SCCM
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "\\server\share\Test-URLFiltering.ps1"
```

### CI/CD Integration (GitHub Actions)

If running from GitHub Actions on a Windows runner:

```yaml
- name: Run URL Filter Tests
  run: |
    .\Test-URLFiltering.ps1
    exit $LASTEXITCODE
```

---

## Troubleshooting

### Script Execution Blocked

**Error:** `cannot be loaded because running scripts is disabled on this system`

**Solution:**

```powershell
# Run once (current session only)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Or permanently for current user
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### All URLs Show as Accessible

**Likely Cause:** Web filter is not active or not applied to your network segment.

**Diagnostic Steps:**

```powershell
# Check internet connectivity
Test-NetConnection -ComputerName 8.8.8.8 -Port 443

# Try accessing a normal URL
Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing

# Check proxy settings
netsh winhttp show proxy
```

### Timeouts on All URLs

**Likely Cause:** Network timeout or DNS issues.

**Solution:**

```powershell
# Increase timeout
.\Test-URLFiltering.ps1 -TimeoutSeconds 30

# Test DNS
nslookup urlfiltering.paloaltonetworks.com
```

### Report Not Opening

**Likely Cause:** HTML file association issue.

**Solution:**

```powershell
# Open report manually
Start-Process "C:\path\to\filter-report.html"

# Or specify browser
Start-Process -FilePath "C:\Program Files\Google\Chrome\Application\chrome.exe" `
  -ArgumentList "C:\path\to\filter-report.html"
```

---

## Testing

### Unit Testing (Manual)

Test specific URL locally:

```powershell
# Load helper functions
. .\Test-URLFiltering.ps1

# Test a single URL
$result = Test-URLAccess -Url "https://example.com" -Category "Test" -TimeoutSec 10
$result | ConvertTo-Json
```

### Automation Testing

```powershell
# Verify script completes without errors
$output = & .\Test-URLFiltering.ps1 -ErrorVariable errs
if ($errs.Count -eq 0) {
    Write-Host "Script executed successfully"
}

# Verify report was created
if (Test-Path "filter-report.html") {
    Write-Host "Report generated successfully"
}
```

---

## Security Considerations

### Input Validation

- URLs are validated before being tested
- JSON configuration is parsed safely
- No eval() or dynamic code execution

### Logging

- All test results are logged to local file
- Log file contains timestamps for audit trails
- Reports are generated locally (no external transmission)

### Privacy

- Script does not send data to external services
- URLs are logged locally only
- Report generation is local-only

---

## Contributing

Contributions are welcome! Please follow these guidelines:

### Coding Standards

- Use PowerShell 5.1-compatible syntax
- Add comments explaining complex logic
- Use proper error handling (try/catch blocks)
- Follow verb-noun naming convention for functions

### Testing New Features

Before submitting a PR:

1. Test on Windows 10 and Windows Server 2016+
2. Verify exit codes work correctly
3. Check HTML report renders properly
4. Test timeout and error scenarios

### Submitting a PR

1. Create a feature branch: `git checkout -b feature/my-feature`
2. Commit with descriptive messages
3. Push and open a pull request

---

## Support

For issues, questions, or feedback:

1. Open an issue on the [GitHub issue tracker](https://github.com/robatcca/test-url-filtering/issues)
2. Email: [robert.cowan@covered.ca.gov](mailto:robert.cowan@covered.ca.gov)

---

## Changelog

### v1.0.0 (Initial Release)

- ✅ PowerShell URL filtering test harness
- ✅ HTML reporting with dark mode support
- ✅ Configuration-driven URL testing
- ✅ Comprehensive logging
- ✅ Cross-platform PowerShell support (5.1 and 7+)
- ✅ Timeout handling and exit code automation
