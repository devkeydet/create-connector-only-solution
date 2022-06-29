# NOTE: Set $tokenInfo before running this script
#       One way would be something like the follwing:
#
#       $tokenInfo = Get-Secret -Name secret-name -AsPlainText

# Load the PowerShell File we depend on
. ./dataverse-webapi-functions.ps1

$token = Get-SpnToken $tokenInfo.tenantId $tokenInfo.clientId $tokenInfo.clientSecret $tokenInfo.dataverseHost $tokenInfo.aadHost



function Get-Solution ($UniqueName) {
    $requestUrlRemainder = 'solutions?$filter=uniquename eq ' + "'" + $UniqueName + "'" + '&$select=solutionid,_publisherid_value'
    $response = Invoke-DataverseHttpGet $token $tokenInfo.dataverseHost $requestUrlRemainder
    return $response.value[0]
}

function New-Solution ($UniqueName, $PublisherId) {
    $body = "{
        `n    `"uniquename`": `"$UniqueName`",
        `n    `"friendlyname`": `"$UniqueName`",
        `n    `"publisherid@odata.bind`": `"publishers($PublisherId)`"
        `n}"

    Invoke-DataverseHttpPost $token $tokenInfo.dataverseHost 'solutions' $body
}

function Remove-Solution ($SolutionId) {
    Invoke-DataverseHttpDelete $token $tokenInfo.dataverseHost "solutions($SolutionId)"
}

function Get-CustomConnectorComponents ($SolutionId) {
    $requestUrlRemainder = 'solutioncomponents?$filter=_solutionid_value eq ' + "'" + $SolutionId + "' and componenttype eq 372" + '&$select=objectid'
    $response = Invoke-DataverseHttpGet $token $tokenInfo.dataverseHost $requestUrlRemainder
    return $response
}

function Add-SolutionComponent ($ObjectId, $SolutionUniqueName) {
    $body = "{
        `n    `"ComponentId`": `"$ObjectId`",
        `n    `"AddRequiredComponents`": true,
        `n    `"ComponentType`": 372,
        `n    `"SolutionUniqueName`":`"$SolutionUniqueName`"
        `n}"

    Invoke-DataverseHttpPost $token $tokenInfo.dataverseHost 'AddSolutionComponent' $body
}

$solutionUniqueName = 'UseCustomConnectorInSolution'
$solution = Get-Solution 'UseCustomConnectorInSolution'
$tempSolutionUniqueName = $solutionUniqueName + '_connector_temp'

$tempSolution = Get-Solution $tempSolutionUniqueName

if ($null -ne $tempSolution) {
    Remove-Solution $tempSolution.solutionid
}

New-Solution $tempSolutionUniqueName $solution._publisherid_value

$components = Get-CustomConnectorComponents $solution.solutionid

foreach ($component in $components.value) {
    $component = Add-SolutionComponent $component.objectid $tempSolutionUniqueName
}

pac solution export --name $tempSolutionUniqueName --path ./$tempSolutionUniqueName.zip --managed true --overwrite true