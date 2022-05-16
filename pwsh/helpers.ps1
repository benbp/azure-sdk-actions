. ./vars.ps1

function sanitizeComment([string]$comment) {
    $result = ""
    $comment = $comment.Trim()
    foreach ($c in $comment.ToCharArray()) {
        if ($c -match "[a-zA-Z0-9\s/-]") {
            $result += $c.ToLowerInvariant()
        }
    }
    return $result
}

function getCheckEnforcerCommand([string]$comment) {
    $comment = sanitizeComment $comment
    $baseCommand = "/check-enforcer"

    if (!($comment.StartsWith($baseCommand))) {
		Write-Warning "Skipping comment that does not start with '$baseCommand'"
        return ""
    }

	$re = "\s*" + $baseCommand + "\s*([A-z]*)"
    if ($comment -match $re) {
        $command = $matches[1]
        if ($command -in "override","evaluate","reset") {
			Write-Host "Parsed check enforcer command $command"
            return $command
        }
		Write-Warning "Supported commands are 'override', 'evaluate', or 'reset' but found: $command"
        return $command
    } else {
		Write-Warning "Command does not match format '/check-enforcer [override|reset|evaluate]'"
        return ""
    }
}

function getUri([string]$target) {
    $targetUrl = [System.UriBuilder]::new($target)
    $targetUrl.Scheme = $BASE_SCHEME
    $targetUrl.Host = $BASE_HOST
    return $targetUrl
}

function getPullRequest([string]$url) {
    $uri = getUri $url
    $resp = /usr/bin/gh api $uri.Uri.AbsoluteUri
    if ($LASTEXITCODE) {
        throw "gh client failed with code $LASTEXITCODE"
    }
    return $resp | ConvertFrom-Json -AsHashtable -Depth 100
}

function getPullsUrlFromIssueComment([hashtable]$ic) {
    return $ic.repository.pulls_url -replace "{/number}","/$($ic.issue.number)"
}

function getCheckSuiteUrlFromPullRequest([hashtable]$pr) {
    return $pr.head.repo.commits_url -replace "{/sha}", "/$($pr.head.sha)/check-suites"
}

function getCheckSuiteStatusFromPullRequest([hashtable]$pr) {
    $csUrl = getCheckSuiteStatusFromPullRequest $pr
    $uri = getUrl $csUrl

    $resp = /usr/bin/gh api $uri.Uri.AbsoluteUri
    if ($LASTEXITCODE) {
        throw "gh client failed with code $LASTEXITCODE"
    }
    $suites = $resp | ConvertFrom-Json -AsHashtable -Depth 100
    foreach ($cs in $suites.check_suites) {
        if ($cs.app.name -ne $AzurePipelinesAppName) {
            continue
        }
        return $cs.conclusion
    }
    return ""
}

function postCommitStatus([string]$url, [object]$body) {
    /usr/bin/gh api `
        --method POST `
        -H "Accept: application/vnd.github.v3+json" `
        $url `
        -f state="$($body.State)" `
        -f description="$($body.Description)" `
        -f context="$($body.Context)" `
        -f target_url="$($body.TargetUrl)"

    if ($LASTEXITCODE) {
        throw "gh client failed with code $LASTEXITCODE"
    }
}

function GetStatusesUrlFromCheckSuite([hashtable]$cs) {
    return $cs.repository.statuses_url -replace "{sha}", $cs.check_suite.head_sha
}

function IsCheckSuiteSucceeded([hashtable]$cs) {
    $conclusion = $cs.check_suite.conclusion
    return $conclusion -eq $CheckSuiteConclusionSuccess
}

function IsCheckSuiteFailed([hashtable]$cs) {
    $conclusion = $cs.check_suite.conclusion
    return $conclusion -eq $CheckSuiteConclusionFailure -or $conclusion -eq $CheckSuiteConclusionTimedOut
}

function NewSucceededBody([string]$targetUrl) {
    return @{
        State       = $CommitStateSuccess
        Description = "All checks passed"
        Context     = $CommitStatusContext
        TargetUrl   = $targetUrl
    }
}

function NewPendingBody([string]$targetUrl) {
    return @{
        State       = $CommitStatePending
        Description = "Waiting for all checks to complete"
        Context     = $CommitStatusContext
        TargetUrl   = $targetUrl
    }
}

function NewFailedBody([string]$targetUrl) {
    return @{
        State       = $CommitStateFailure
        Description = "Some checks failed"
        Context     = $CommitStatusContext
        TargetUrl   = $targetUrl
    }
}
