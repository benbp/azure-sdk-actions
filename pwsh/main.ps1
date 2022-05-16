param(
    [string]$PayloadPath
)

. $PSScriptRoot/helpers.ps1

function main([string]$payloadPathParam) {
    if (!(Test-Path $payloadPathParam)) {
        throw "Payload file not found: '$payloadPathParam'"
    }
    $payload = Get-Content -Raw $payloadPathParam | ConvertFrom-Json -AsHashtable -Depth 100
    if (![System.Environment]::GetEnvironmentVariable($GithubTokenKey)) {
        Write-Warning "Environment variable '$GithubTokenKey' is not set"
    }

    handleEvent $payload
}

function handleEvent([hashtable]$payload) {
    if (IsIssueCommentWebhook $payload) {
        HandleIssueComment $payload
        return
    }
    if (IsCheckSuiteWebhook $payload) {
        HandleCheckSuite $payload
        return
    }
	throw "Error: Invalid or unsupported payload body."
}

function IsIssueCommentWebhook([hashtable]$payload) {
    return ![string]::IsNullOrEmpty($payload.issue)
}

function IsCheckSuiteWebhook([hashtable]$payload) {
    return ![string]::IsNullOrEmpty($payload.check_suite)
}

function HandleIssueComment([hashtable]$ic) {
    $command = getCheckEnforcerCommand $ic.comment.body

    if ($command -eq "") {
        return
    }

    if ($command -eq "override") {
        $pr = getPullRequest (getPullsUrlFromIssueComment $ic)
        $body = NewSucceededBody ""
        $body.TargetUrl = $pr.statuses_url
        postCommitStatus $pr.statuses_url $body
        return
    }

    if ($command -eq "evaluate" -or $command -eq "reset") {
		# We cannot use the commits url from the issue object because it
		# is targeted to the main repo. To get all check suites for a commit,
		# a request must be made to the repos API for the repository the pull
		# request branch is from, which may be a fork.
        $pr = getPullRequest (getPullsUrlFromIssueComment $ic)
        $conclusion = getCheckSuiteStatusFromPullRequest $pr
        if (IsCheckSuiteSucceeded $conclusion) {
            postCommitStatus $pr.statuses_url (NewSucceededBody "")
        } elseif (IsCheckSuiteFailed $conclusion) {
            postCommitStatus $pr.statuses_url (NewFailedBody "")
        } else {
            postCommitStatus $pr.statuses_url (NewPendingBody "")
        }
    }
}

function HandleCheckSuite([hashtable]$cs) {
    if ($cs.check_suite.app.name -ne $AzurePipelinesAppName) {
        Write-Warning "Check Enforcer only handles check suites from the '$AzurePipelinesAppName' app. Found: '$($cs.check_suite.app.name)'"
        return
    } elseif ($cs.check_suite.head_branch -eq "main") {
		Write-Warning "Skipping check suite for main branch."
        return
    } elseif (IsCheckSuiteSucceeded $cs) {
        $body = NewSucceededBody $cs.check_suite.url
        $url = GetStatusesUrlFromCheckSuite $cs
        PostCommitStatus $url $body
    } elseif (IsCheckSuiteFailed $cs) {
        $body = NewFailedBody
        $body.TargetUrl = $cs.check_suite.url
        $url = GetStatusesUrlFromCheckSuite $cs
        postCommitStatus $url $body
    } else {
		Write-Warning "Skipping check suite with conclusion: $($cs.check_suite.conclusion)"
    }
}

# Don't call functions when the script is being dot sourced
if ($MyInvocation.InvocationName -ne ".") {
    main $PayloadPath
}
