Import-Module Pester

$BASE_HOST = "localhost:9000"
$BASE_SCHEME = ""

BeforeAll {
    . $PSScriptRoot/main.ps1

    $checkSuiteEventPayload = Get-Content -Raw ./testpayloads/check_suite_event.json
    $issueCommentEventPayload = Get-Content -Raw ./testpayloads/issue_comment_event.json
    $pullRequestResponse = Get-Content -Raw ./testpayloads/pull_request_response.json
    $checkSuiteResponse = Get-Content -Raw ./testpayloads/check_suite_response.json
    $statusResponse = Get-Content -Raw ./testpayloads/status_response.json
}

Describe "Check Suite Handler" {
    It "Should handle a check suite event" {
        $payloadJson = $checkSuiteEventPayload | ConvertFrom-Json -AsHashtable -Depth 100

        $http = [System.Net.HttpListener]::new() 
        $http.Prefixes.Add($BASE_HOST)
        $http.IsListening | Should -Be $true

        while ($http.IsListening) {
        }

        handleEvent $payloadJson
    }
}

Describe "Issue Comment Handler" {
    It "Should handle an issue comment event" -TestCases @(
        @{ },
        @{ }
    ) {
    }
}
