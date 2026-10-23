Class LabIntegration.FHIROperation Extends Ens.BusinessOperation
{
    Property FHIRUsername As %String;
    Property FHIRPassword As %String;

    Parameter SETTINGS = "FHIRUsername,FHIRPassword";

    XData MessageMap
    {
        <MapItems>
            <MapItem MessageType="LabIntegration.FHIRRequest">
                <Method>OnMessage</Method>
            </MapItem>
        </MapItems>
    }

    Method OnMessage(
        pRequest As LabIntegration.FHIRRequest,
        Output pResponse As %Library.Persistent
    ) As %Status
    {
        Set fhirJSON = pRequest.FHIRJSON

        Set httpRequest = ##class(%Net.HttpRequest).%New()
        Set httpRequest.Username = ..FHIRUsername
        Set httpRequest.Password = ..FHIRPassword
        Set httpRequest.InitiateAuthentication = "Basic"
        Set httpRequest.Server = "localhost"
        Set httpRequest.Port = 52773
        Set httpRequest.ContentType = "application/fhir+json"

        Do httpRequest.SetHeader("Accept","application/fhir+json")
        Do httpRequest.EntityBody.Write(fhirJSON)

        // Clear response-specific diagnostic state before each POST.
        // This prevents values from a previous transaction being mistaken
        // for values belonging to the current transaction.
        Kill ^LabIntegrationDebug("HTTPResponseStatus")
        Kill ^LabIntegrationDebug("FHIRCreateResult")
        Kill ^LabIntegrationDebug("FHIRFailureType")
        Kill ^LabIntegrationDebug("Location")
        Kill ^LabIntegrationDebug("ETag")
        Kill ^LabIntegrationDebug("LastModified")
        Kill ^LabIntegrationDebug("HTTPResponseBody")
        Kill ^LabIntegrationDebug("FHIRResponseResourceType")
        Kill ^LabIntegrationDebug("OperationOutcomeDetected")
        Kill ^LabIntegrationDebug("OperationOutcomeIssueCount")
        Kill ^LabIntegrationDebug("OperationOutcomeSeverity")
        Kill ^LabIntegrationDebug("OperationOutcomeCode")
        Kill ^LabIntegrationDebug("OperationOutcomeDiagnostics")
        Kill ^LabIntegrationDebug("OperationOutcomeDetailsText")
        Kill ^LabIntegrationDebug("OperationOutcomeExpressionCount")
        Kill ^LabIntegrationDebug("OperationOutcomeExpression")

        // Send the FHIR request.
        // httpStatus is an InterSystems %Status describing whether the
        // HTTP operation/transport succeeded. It is NOT the HTTP response code.
        Set httpStatus = httpRequest.Post("/csp/healthshare/hl7clean/fhir/r4/Observation")

        If $$$ISOK(httpStatus) {
            Set ^LabIntegrationDebug("FHIRTransportResult") = "SUCCESS"
        }

        If $$$ISERR(httpStatus) {
            Set ^LabIntegrationDebug("FHIRTransportResult") = "FAILURE"
        }

        // Stop here on a transport failure.
        // There may be no valid HttpResponse to inspect.
        If $$$ISERR(httpStatus) {
            Quit httpStatus
        }

        // Transport succeeded, so it is now safe to inspect the receiver's
        // HTTP response.
        If $$$ISOK(httpStatus) {

            Set responseStatus = httpRequest.HttpResponse.StatusCode

            // For this FHIR create operation, HTTP 201 means that the
            // Observation was created successfully.
            If responseStatus = 201 {
                Set ^LabIntegrationDebug("FHIRCreateResult") = "SUCCESS"
            }

            If responseStatus '= 201 {
                Set ^LabIntegrationDebug("FHIRCreateResult") = "FAILURE"
            }

            // Convert a non-201 HTTP response into an InterSystems %Status.
            // The HTTP status (for example 400 or 404) is what the server
            // returned. #5001 is the InterSystems GeneralError used to
            // propagate that failure through HealthShare.
            If responseStatus '= 201 {
                Set httpFailureStatus = $SYSTEM.Status.Error(
                    $$$GeneralError,
                    "FHIR server returned HTTP status "_responseStatus
                )
            }

            // Classify HTTP failures by response family.
            // 4xx = client/request-side failure.
            // 5xx = server-side failure.
            If (responseStatus >= 400) && (responseStatus <= 499) {
                Set ^LabIntegrationDebug("FHIRFailureType") = "CLIENT"
            }

            If (responseStatus >= 500) && (responseStatus <= 599) {
                Set ^LabIntegrationDebug("FHIRFailureType") = "SERVER"
            }

            // Capture the receiver's response details before propagating
            // any HTTP failure.
            Set ^LabIntegrationDebug("HTTPResponseStatus") = responseStatus
            Set ^LabIntegrationDebug("Location") = httpRequest.HttpResponse.GetHeader("Location")
            Set ^LabIntegrationDebug("ETag") = httpRequest.HttpResponse.GetHeader("ETag")
            Set ^LabIntegrationDebug("LastModified") = httpRequest.HttpResponse.GetHeader("Last-Modified")

            Set responseBody = httpRequest.HttpResponse.Data.Read()
            Set ^LabIntegrationDebug("HTTPResponseBody") = responseBody

            // A failed FHIR request may return an OperationOutcome in the
            // response body. Only attempt parsing when a body actually exists.
            If (responseStatus '= 201) && (responseBody '= "") {

                Try {
                    
                    // DESERIALIZATION/PARSING:
                    // Convert the FHIR server's response body from JSON text into a
                    // dynamic JSON object so that its properties can be inspected.
                    // Direction: JSON -> OBJECT.
                    //
                    // %FromJSON() can throw an exception if the response body is not
                    // valid JSON, so the parsing and inspection logic is protected
                    // by TRY/CATCH.

                    Set responseJSON = {}.%FromJSON(responseBody)

                    // DEFENSIVE CHECK:
                    // A JSON response is not guaranteed to contain resourceType.
                    // %IsDefined("resourceType") proves that the property exists
                    // before we attempt to read responseJSON.resourceType.
                    If responseJSON.%IsDefined("resourceType") {

                        Set ^LabIntegrationDebug("FHIRResponseResourceType") = responseJSON.resourceType

                        If responseJSON.resourceType = "OperationOutcome" {

                            Set ^LabIntegrationDebug("OperationOutcomeDetected") = "YES"

                            // DEFENSIVE COLLECTION CHECK:
                            // OperationOutcome.issue is a JSON array/collection.
                            // First prove that the issue property exists. Only then is it
                            // safe to ask the collection how many items it contains with %Size().
                            If responseJSON.%IsDefined("issue") {

                                Set issueCount = responseJSON.issue.%Size()
                                Set ^LabIntegrationDebug("OperationOutcomeIssueCount") = issueCount

                                // DEFENSIVE ITEM CHECK:
                                // %Size() tells us how many items are in the issue collection.
                                // Only when issueCount is greater than zero do we retrieve
                                // the first issue with %Get(0).
                                If issueCount > 0 {

                                    Set firstIssue = responseJSON.issue.%Get(0)

                                    If firstIssue.%IsDefined("severity") {
                                        Set ^LabIntegrationDebug("OperationOutcomeSeverity") = firstIssue.severity
                                    }

                                    If firstIssue.%IsDefined("code") {
                                        Set ^LabIntegrationDebug("OperationOutcomeCode") = firstIssue.code
                                    }

                                    If firstIssue.%IsDefined("diagnostics") {
                                        Set ^LabIntegrationDebug("OperationOutcomeDiagnostics") = firstIssue.diagnostics
                                    }

                                    // DEFENSIVE NESTED OBJECT CHECK:
                                    // details is another dynamic JSON object held by firstIssue.
                                    // First prove that details exists, then prove that its text
                                    // property exists before reading firstIssue.details.text.
                                    If firstIssue.%IsDefined("details") {

                                        If firstIssue.details.%IsDefined("text") {
                                            Set ^LabIntegrationDebug("OperationOutcomeDetailsText") = firstIssue.details.text
                                        }
                                    }

                                    // DEFENSIVE COLLECTION CHECK:
                                    // expression is a JSON array/collection held by firstIssue.
                                    // First prove that expression exists, then use %Size() to determine
                                    // whether the collection contains an item before calling %Get(0).
                                    If firstIssue.%IsDefined("expression") {

                                        Set expressionCount = firstIssue.expression.%Size()
                                        Set ^LabIntegrationDebug("OperationOutcomeExpressionCount") = expressionCount

                                        If expressionCount > 0 {

                                            Set firstExpression = firstIssue.expression.%Get(0)
                                            Set ^LabIntegrationDebug("OperationOutcomeExpression") = firstExpression
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Catch ex {
                    // DEFENSIVE JSON PARSING:
                    // %FromJSON() throws an exception if the response body is not valid JSON.
                    // Catch that parsing exception so it does not replace the real HTTP failure.
                    // After CATCH, execution continues below and the original
                    // httpFailureStatus is returned to HealthShare.
                }
            }

            // Propagate the original HTTP failure whether or not the response
            // body contained a valid, parseable OperationOutcome.
            If responseStatus '= 201 {
                Quit httpFailureStatus
            }
        }

        Quit $$$OK
    }
}