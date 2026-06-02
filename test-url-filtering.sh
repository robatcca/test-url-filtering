#!/bin/bash
#
# URL Filtering Test Harness for Linux/macOS environments
# Tests if web filtering is in place by attempting to access URLs that SHOULD be blocked
#
# Usage:
#   ./test-url-filtering.sh
#   ./test-url-filtering.sh -c /path/to/urls.json -t 15 -v
#
# Options:
#   -c, --config PATH      Path to configuration file (default: ./urls.json)
#   -t, --timeout SECONDS  HTTP request timeout (default: 10)
#   -v, --verbose          Enable verbose output
#   -h, --help             Show this help message
#

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/urls.json"
TIMEOUT_SECONDS=10
VERBOSE=false
LOG_FILE="${SCRIPT_DIR}/test-results.log"
REPORT_FILE="${SCRIPT_DIR}/filter-report.html"

# ── Parse Arguments ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            cat << EOF
URL Filtering Test Harness - Linux/macOS Version

Usage: $(basename "$0") [OPTIONS]

Options:
  -c, --config PATH      Path to configuration file (default: ./urls.json)
  -t, --timeout SECONDS  HTTP request timeout in seconds (default: 10)
  -v, --verbose          Enable verbose output
  -h, --help             Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") -c /etc/url-tests/urls.json -t 15
  $(basename "$0") --timeout 30 --verbose

EOF
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ── Helper Functions ─────────────────────────────────────────────────────────

write_log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"
    
    echo "$log_entry"
    echo "$log_entry" >> "$LOG_FILE"
}

test_url_access() {
    local url="$1"
    local category="$2"
    local timeout_sec="$3"
    
    [[ "$VERBOSE" == true ]] && write_log "DEBUG" "Testing URL: $url (Category: $category)"
    
    local status="UNKNOWN"
    local status_code=""
    local blocked=false
    local exception=""
    
    # Use curl for HTTP testing with timeout
    local http_code
    
    # Capture both HTTP code and response
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$timeout_sec" \
        --user-agent "Mozilla/5.0" \
        --connect-timeout "$timeout_sec" \
        "$url" 2>&1 || echo "000")
    
    case "$http_code" in
        200|201|202|204)
            status="ACCESSIBLE"
            status_code="$http_code"
            blocked=false
            write_log "FAIL" "$url returned HTTP $http_code — NOT blocked!"
            ;;
        403)
            status="BLOCKED (403 Forbidden)"
            status_code="403"
            blocked=true
            write_log "PASS" "$url blocked with HTTP 403"
            ;;
        000)
            status="BLOCKED (Connection error)"
            status_code=""
            blocked=true
            exception="Connection timeout or DNS failure"
            write_log "PASS" "$url blocked (connection error)"
            ;;
        *)
            status="ACCESSIBLE (HTTP $http_code)"
            status_code="$http_code"
            blocked=false
            write_log "FAIL" "$url returned HTTP $http_code — NOT blocked!"
            ;;
    esac
    
    # Output result as JSON for processing
    cat << EOF
{
    "url": "$(echo "$url" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')",
    "category": "$(echo "$category" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')",
    "status": "$status",
    "statusCode": "$status_code",
    "blocked": $([ "$blocked" = true ] && echo true || echo false),
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "exception": "$(echo "$exception" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')"
}
EOF
}

load_configuration() {
    local config_file="$1"
    
    [[ "$VERBOSE" == true ]] && write_log "DEBUG" "Loading configuration from: $config_file"
    
    if [[ ! -f "$config_file" ]]; then
        write_log "ERROR" "Configuration file not found: $config_file"
        exit 1
    fi
    
    # Validate JSON
    if ! command -v jq &> /dev/null; then
        write_log "ERROR" "jq is required to parse JSON. Install it with: apt-get install jq (Debian/Ubuntu) or brew install jq (macOS)"
        exit 1
    fi
    
    if ! jq empty "$config_file" 2>/dev/null; then
        write_log "ERROR" "Invalid JSON in configuration file: $config_file"
        exit 1
    fi
    
    local url_count=$(jq '.urls | length' "$config_file")
    write_log "INFO" "Loaded configuration with $url_count URL(s)"
}

html_escape() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

generate_html_report() {
    local results_json="$1"
    local output_path="$2"
    
    # Parse results to calculate statistics
    local pass_count=$(echo "$results_json" | jq '[.[] | select(.blocked == true)] | length')
    local fail_count=$(echo "$results_json" | jq '[.[] | select(.blocked == false)] | length')
    local total_count=$(echo "$results_json" | jq 'length')
    
    local pass_percentage=0
    if [[ $total_count -gt 0 ]]; then
        pass_percentage=$((pass_count * 100 / total_count))
    fi
    
    # Generate warning section
    local warning_html=""
    if [[ $fail_count -gt 0 ]]; then
        warning_html="<div class=\"warning\">
                <strong>⚠️  Warning:</strong> $fail_count URL(s) were NOT blocked by the filter. These should be investigated.
            </div>"
    fi
    
    # Generate results table rows
    local table_rows=""
    while IFS= read -r line; do
        local url=$(echo "$line" | jq -r '.url')
        local category=$(echo "$line" | jq -r '.category')
        local blocked=$(echo "$line" | jq -r '.blocked')
        local status_code=$(echo "$line" | jq -r '.statusCode')
        local timestamp=$(echo "$line" | jq -r '.timestamp')
        
        local status_class="accessible"
        local status_text="✗ Accessible"
        
        if [[ "$blocked" == "true" ]]; then
            status_class="blocked"
            status_text="✓ Blocked"
        fi
        
        local http_code="${status_code:-N/A}"
        local display_timestamp="${timestamp:0:19}"
        
        local escaped_url=$(html_escape "$url")
        local escaped_category=$(html_escape "$category")
        
        table_rows+="<tr>
                        <td class=\"url-cell\">$escaped_url</td>
                        <td><span class=\"category-badge\">$escaped_category</span></td>
                        <td><span class=\"status-badge $status_class\">$status_text</span></td>
                        <td>$http_code</td>
                        <td>$display_timestamp</td>
                    </tr>"
    done < <(echo "$results_json" | jq -c '.[]')
    
    # Generate HTML document
    local current_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$output_path" << 'HTMLEOF'
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
                <div class="value">PASS_COUNT</div>
                <div class="label">URLs Blocked</div>
            </div>
            <div class="summary-card fail">
                <div class="value">FAIL_COUNT</div>
                <div class="label">URLs NOT Blocked</div>
            </div>
            <div class="summary-card total">
                <div class="value">TOTAL_COUNT</div>
                <div class="label">Total URLs Tested</div>
            </div>
            <div class="summary-card total">
                <div class="value">PASS_PERCENTAGE%</div>
                <div class="label">Pass Rate</div>
            </div>
        </div>
        
        <div class="content">
            WARNING_HTML
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
                    TABLE_ROWS
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <p>Report generated on CURRENT_TIMESTAMP | URL Filtering Test Harness</p>
        </div>
    </div>
</body>
</html>
HTMLEOF

    # Replace placeholders
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS sed requires -i '' syntax
        sed -i '' "s/PASS_COUNT/$pass_count/g" "$output_path"
        sed -i '' "s/FAIL_COUNT/$fail_count/g" "$output_path"
        sed -i '' "s/TOTAL_COUNT/$total_count/g" "$output_path"
        sed -i '' "s/PASS_PERCENTAGE/$pass_percentage/g" "$output_path"
        sed -i '' "s|CURRENT_TIMESTAMP|$current_timestamp|g" "$output_path"
    else
        # Linux sed
        sed -i "s/PASS_COUNT/$pass_count/g" "$output_path"
        sed -i "s/FAIL_COUNT/$fail_count/g" "$output_path"
        sed -i "s/TOTAL_COUNT/$total_count/g" "$output_path"
        sed -i "s/PASS_PERCENTAGE/$pass_percentage/g" "$output_path"
        sed -i "s|CURRENT_TIMESTAMP|$current_timestamp|g" "$output_path"
    fi
    
    # Use awk for complex replacements
    awk -v warn="$warning_html" '{gsub(/WARNING_HTML/, warn); print}' "$output_path" > "${output_path}.tmp" && mv "${output_path}.tmp" "$output_path"
    awk -v rows="$table_rows" '{gsub(/TABLE_ROWS/, rows); print}' "$output_path" > "${output_path}.tmp" && mv "${output_path}.tmp" "$output_path"
    
    write_log "INFO" "HTML report generated: $output_path"
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    # Clear previous log
    > "$LOG_FILE"
    
    write_log "INFO" "========================================"
    write_log "INFO" "URL Filtering Test Harness"
    write_log "INFO" "========================================"
    write_log "INFO" "Configuration: $CONFIG_PATH"
    write_log "INFO" "Timeout: $TIMEOUT_SECONDS seconds"
    write_log "INFO" ""
    
    # Load and validate configuration
    load_configuration "$CONFIG_PATH"
    
    # Test all URLs and collect results
    local all_results="["
    local first=true
    
    while IFS= read -r url_entry; do
        local url=$(echo "$url_entry" | jq -r '.url')
        local category=$(echo "$url_entry" | jq -r '.category')
        
        if [[ "$first" == false ]]; then
            all_results+=","
        fi
        first=false
        
        local result=$(test_url_access "$url" "$category" "$TIMEOUT_SECONDS")
        all_results+="$result"
    done < <(jq -c '.urls[]' "$CONFIG_PATH")
    
    all_results+="]"
    
    write_log "INFO" ""
    
    # Calculate summary
    local pass_count=$(echo "$all_results" | jq '[.[] | select(.blocked == true)] | length')
    local fail_count=$(echo "$all_results" | jq '[.[] | select(.blocked == false)] | length')
    
    write_log "INFO" "========================================"
    write_log "INFO" "Summary: $pass_count passed, $fail_count failed"
    write_log "INFO" "========================================"
    
    # Generate HTML report
    generate_html_report "$all_results" "$REPORT_FILE"
    
    # Determine exit code and open report
    if [[ $fail_count -eq 0 ]]; then
        write_log "PASS" "All tests passed! Report: $REPORT_FILE"
        
        # Try to open report in browser if X11/GUI available
        if command -v xdg-open &> /dev/null; then
            xdg-open "$REPORT_FILE" 2>/dev/null || true
        elif command -v open &> /dev/null; then
            open "$REPORT_FILE" 2>/dev/null || true
        fi
        
        return 0
    else
        write_log "FAIL" "Some tests failed! Report: $REPORT_FILE"
        
        # Try to open report
        if command -v xdg-open &> /dev/null; then
            xdg-open "$REPORT_FILE" 2>/dev/null || true
        elif command -v open &> /dev/null; then
            open "$REPORT_FILE" 2>/dev/null || true
        fi
        
        return 1
    fi
}

# Run main function
main
