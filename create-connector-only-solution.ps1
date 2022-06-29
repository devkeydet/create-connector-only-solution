# NOTE: Set $tokenInfo & $solutionUniqueName before running this script
#       One way would be something like the following (which is what I do):
#       
#       $solutionUniqueName = "NameOfUnamangedSolutionToBaseConnetorOnlySolutionOn"
#       $tokenInfo = Get-Secret -Name secret-name -AsPlainText # where secret is an object with the structure below 

# Load the PowerShell file containing the helper functions
. ./dataverse-webapi-functions.ps1

$token = Get-SpnToken $tokenInfo.tenantId $tokenInfo.clientId $tokenInfo.clientSecret $tokenInfo.dataverseHost $tokenInfo.aadHost

function Get-Solution ($UniqueName) {
    $requestUrlRemainder = 'solutions?$filter=uniquename eq ' + "'" + $UniqueName + "'" + '&$select=solutionid,_publisherid_value'
    $response = Invoke-DataverseHttpGet $token $tokenInfo.dataverseHost $requestUrlRemainder
    return $response.value[0]
}

function New-Solution ($UniqueName, $PublisherId) {
    $body = 
@"
{
    "uniquename": "$UniqueName",
    "friendlyname": "$UniqueName",
    "publisherid@odata.bind": "publishers($PublisherId)"
}
"@

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
    $bodyObject = @{
        ComponentId = $ObjectId
        AddRequiredComponents = $true
        ComponentType = 372
        SolutionUniqueName = $SolutionUniqueName
    }

    $body = ConvertTo-Json $bodyObject

    Invoke-DataverseHttpPost $token $tokenInfo.dataverseHost 'AddSolutionComponent' $body
}

# Get the solution we want to base the temporary solution with connectors only on
$solution = Get-Solution $solutionUniqueName

# Check to see if a temp solution of the same name is still in the dev environment.
# If it is, remove it because we will recreate it based on any updates in the actual solution
# such as adding another custom connector or environment variable used by a custom connector.
$tempSolutionUniqueName = $solutionUniqueName + '_temp'

$tempSolution = Get-Solution $tempSolutionUniqueName

if ($null -ne $tempSolution) {
    Remove-Solution $tempSolution.solutionid
}

# Create the temp solution using the same publisher as the solution we are basing the temp solution on
New-Solution $tempSolutionUniqueName $solution._publisherid_value

# Get all the custom connectors in the solution we are basing the temp solution on
$components = Get-CustomConnectorComponents $solution.solutionid

# Add the custom connectors to the temp solution, ensuring we add the required components for the connector (such as enviorment variables)
foreach ($component in $components.value) {
    $component = Add-SolutionComponent $component.objectid $tempSolutionUniqueName
}

# Export the solution as managed so we can import it for the first time into
# the target environment so the connectors will be available to create a connection
pac solution export --name $tempSolutionUniqueName --path ./$tempSolutionUniqueName.zip --managed true --overwrite true

# Delete temp solution from dev environment so we don't have an unnecessary solution in the dev environment
$tempSolution = Get-Solution $tempSolutionUniqueName
Remove-Solution $tempSolution.solutionid

# Import the solution into the target environment
# Create the connection (must be manual for oauth connections where the token represents an interactive user)
# Once we have a connection in the target environment we can import the "full" solution and reference the connection via the connection reference during import
# Once the "full" solution is imported in the target environment we can delete the temp solution so we don't have an unnecessary solution in the target environment