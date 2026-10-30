
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

    Method OnMessage(pRequest As LabIntegration.FHIRRequest, Output pResponse As %Library.Persistent) As %Status
    {
        Set fhirJSON = pRequest.FHIRJSON
        Set identifierSystem = pRequest.IdentifierSystem
        Set identifierValue = pRequest.IdentifierValue
        Set conditionalCreate = "identifier="_identifierSystem_"|"_identifierValue
        // OPERATIONAL TRACEABILITY:
        // Expose the source occurrence identity directly so that an operator can
        // associate the transport, HTTP, FHIR and retry diagnostics below with
        // the exact HL7 source occurrence being processed.
        Set ^LabIntegrationDebug("SourceOccurrence") = identifierValue
        Set ^LabIntegrationDebug("ConditionalCreate") = conditionalCreate

        // -----------------------------------------
        // STAGE 13.1 - REQUIRED FHIR CONFIGURATION
        // -----------------------------------------
        // FAIL FAST:
        // The Business Operation cannot authenticate successfully with the
        // FHIR server unless both Basic Authentication settings are present.
        //
        // Validate these settings before acquiring the occurrence-specific
        // idempotency lock or constructing/sending an HTTP request.
        If ..FHIRUsername = "" {
            Quit $$$ERROR($$$GeneralError, "FHIR username is not configured")
        }

        If ..FHIRPassword = "" {
            Quit $$$ERROR($$$GeneralError, "FHIR password is not configured")
        }
        // LOCAL IDEMPOTENCY GUARD:
        // The FHIR server currently persists Observation.identifier correctly,
        // but its identifier token search does not find the stored identifier.
        // Because Conditional Create depends on that search, repeated delivery
        // currently creates duplicate Observations.
        //
        // Protect this source occurrence with an occurrence-specific lock.
        // The lock prevents two copies of the same HL7 occurrence from both
        // passing the duplicate check and POSTing at the same time.
        //
        // A timed LOCK sets $TEST:
        //     $TEST = 1  -> the lock was acquired.
        //     $TEST = 0  -> the lock could not be acquired before the timeout.
        Lock +^LabIntegrationIdempotencyLock(identifierSystem,identifierValue):10

        If '$TEST {
            Set ^LabIntegrationDebug("IdempotencyResult") = "LOCK TIMEOUT"

            Set lockFailureStatus = $SYSTEM.Status.Error(
                $$$GeneralError,
                "Unable to acquire idempotency lock for source occurrence"
            )

            Quit lockFailureStatus
        }

        // Now that this process owns the occurrence-specific lock, check whether
        // this source occurrence has already completed successfully.
        //
        // IMPORTANT:
        // The registry is checked AFTER acquiring the lock. This closes the race
        // where two identical messages could otherwise check simultaneously.
        If ..IsOccurrenceProcessed(identifierSystem,identifierValue) {

            Set ^LabIntegrationDebug("IdempotencyResult") = "DUPLICATE SUPPRESSED"

            // This occurrence was successfully processed previously.
            // Do not send another POST to the FHIR server.
            Lock -^LabIntegrationIdempotencyLock(identifierSystem,identifierValue)

            Quit $$$OK
        }

        Set ^LabIntegrationDebug("IdempotencyResult") = "NEW OCCURRENCE"

        Set httpRequest = ##class(%Net.HttpRequest).%New()
        Set httpRequest.Username = ..FHIRUsername
        Set httpRequest.Password = ..FHIRPassword
        Set httpRequest.InitiateAuthentication = "Basic"
        Set httpRequest.Server = "localhost"
        Set httpRequest.Port = 52773
        Set httpRequest.ContentType = "application/fhir+json"

        Do httpRequest.SetHeader("Accept","application/fhir+json")
        // Retain the FHIR Conditional Create header as a second layer of
        // duplicate protection if identifier search is repaired/enabled later.
        Do httpRequest.SetHeader("If-None-Exist",conditionalCreate)
        Set ^LabIntegrationDebug("IfNoneExistHeader") = httpRequest.GetHeader("If-None-Exist")
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

            // IDEMPOTENCY / RETRY:
            // The POST did not complete successfully, so this source occurrence
            // must NOT be recorded as processed.
            //
            // Release the occurrence-specific lock. Because no successful
            // idempotency record has been written, a later delivery of the same
            // HL7 occurrence is allowed to retry the POST.
            Set ^LabIntegrationDebug("IdempotencyResult") = "POST FAILED - RETRY ALLOWED"
            Lock -^LabIntegrationIdempotencyLock(identifierSystem,identifierValue)

            Quit httpStatus
        }

        // Transport succeeded, so it is now safe to inspect the receiver's
        // HTTP response.
        If $$$ISOK(httpStatus) {

            Set responseStatus = httpRequest.HttpResponse.StatusCode

           // For this FHIR Conditional Create operation:
           // HTTP 201 = a new Observation was created.
           // HTTP 200 = an existing matching Observation was found,
           //  so no duplicate Observation was created.
            If (responseStatus = 201) || (responseStatus = 200) {
                Set ^LabIntegrationDebug("FHIRCreateResult") = "SUCCESS"
            }

            If (responseStatus '= 201) && (responseStatus '= 200) {
                Set ^LabIntegrationDebug("FHIRCreateResult") = "FAILURE"
            }

            If (responseStatus '= 201) && (responseStatus '= 200) {
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
            If (responseStatus '= 201) && (responseStatus '= 200) && (responseBody '= "") {

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
            If (responseStatus '= 201) && (responseStatus '= 200) {

                // IDEMPOTENCY / RETRY:
                // The FHIR server responded, but the create operation was not
                // successful. Do NOT record this occurrence as processed.
                //
                // Release the lock so that a later delivery of the same source
                // occurrence can retry the FHIR POST.
                Set ^LabIntegrationDebug("IdempotencyResult") = "FHIR CREATE FAILED - RETRY ALLOWED"
                Lock -^LabIntegrationIdempotencyLock(identifierSystem,identifierValue)

                Quit httpFailureStatus
            }
        }
        // IDEMPOTENCY SUCCESS:
        // Reaching this point means:
        //     1. The HTTP transport succeeded.
        //     2. The FHIR server returned HTTP 200 or HTTP 201.
        //
        // Only now is it safe to record this source occurrence as successfully
        // processed. Future delivery of the same occurrence can then be
        // suppressed before another POST is attempted.
        Do ..RecordProcessedOccurrence(identifierSystem,identifierValue)

        Set ^LabIntegrationDebug("IdempotencyResult") = "PROCESSED"

        // The successful occurrence has now been recorded, so release the
        // occurrence-specific lock.
        Lock -^LabIntegrationIdempotencyLock(identifierSystem,identifierValue)
        Quit $$$OK
    }
    
    Method IsOccurrenceProcessed(identifierSystem As %String, identifierValue As %String) As %Boolean
    {
        // IDEMPOTENCY LOOKUP:
        // The local registry contains an entry only after a source occurrence
        // has completed successfully.
        //
        // $Data() returns a non-zero value when the occurrence exists in the
        // registry. Converting that result to 1 or 0 gives this method a clear
        // Boolean result for the caller.
        If $Data(^LabIntegrationIdempotency(identifierSystem,identifierValue)) {
            Quit 1
        }

        Quit 0
    }

    Method RecordProcessedOccurrence(identifierSystem As %String, identifierValue As %String)
    {
        // IDEMPOTENCY RECORD:
        // This method must be called only after the FHIR create operation has
        // succeeded.
        //
        // The identifier system and identifier value together identify the
        // original HL7 source occurrence. Storing "PROCESSED" means that a
        // later delivery of that same occurrence can be recognised and
        // suppressed before another FHIR POST is attempted.
        Set ^LabIntegrationIdempotency(identifierSystem,identifierValue) = "PROCESSED"

        Quit
    }

}